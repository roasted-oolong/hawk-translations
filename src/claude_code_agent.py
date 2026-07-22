"""
src/claude_code_agent.py
--------------------------
The "claude_code" translation backend (see src/translation_backend.py).

Calls Claude by shelling out to the Claude Code CLI in headless mode
(`claude -p`), authenticated through the user's Claude subscription (OAuth
login via `claude auth login`) rather than a metered ANTHROPIC_API_KEY. This
module has no knowledge of prompts, novels, or chapters — like src/agent.py,
it receives a system prompt, a user message, and an optional list of Skill
instances, and returns a plain string.

Tool access for `skills` is provided entirely through a single MCP server
(src/mcp_servers/skill_bridge.py) launched fresh per call, which dynamically
exposes each given Skill as an MCP tool — see that module for details. This
keeps skills backend-agnostic: the same Skill instances translate.py builds
for the "local" backend work here unchanged.
"""

import json
import os
import subprocess
import sys
import tempfile
from contextlib import contextmanager
from pathlib import Path
from typing import TYPE_CHECKING, Iterator

from config import MAX_TOKENS, TRANSLATION_MAX_BUDGET_USD, TRANSLATION_MODEL

if TYPE_CHECKING:
    from src.skills.base import Skill

_BRIDGE_SCRIPT = Path(__file__).parent / "mcp_servers" / "skill_bridge.py"
_CLAUDE_BIN = os.environ.get("CLAUDE_BIN", "claude")
_TIMEOUT_SECONDS = 1200


class ClaudeCodeError(RuntimeError):
    """Raised when the Claude Code CLI fails, refuses, or returns unparseable output."""


def call(
    system_prompt: str,
    user_message: str,
    *,
    model: str = TRANSLATION_MODEL,
    max_tokens: int = MAX_TOKENS,
    skills: "list[Skill] | None" = None,
) -> str:
    """
    Translate via the Claude Code CLI, authenticated through the user's
    subscription rather than a metered API key.

    Parameters mirror src.agent.call() so this function can be used
    interchangeably as a TranslationBackend (see src/translation_backend.py).
    `max_tokens` has no Claude Code CLI equivalent in this mode (Claude Code
    manages its own output budget) — accepted only for interface parity, and
    unused. The real spend guard is TRANSLATION_MAX_BUDGET_USD (a dollar
    ceiling), passed to the CLI via --max-budget-usd.

    Raises
    ------
    ClaudeCodeError
        If the claude binary is missing, the call times out, the CLI's
        output can't be parsed as JSON, or the CLI reports failure
        (nonzero exit code or `is_error: true`).
    """
    del max_tokens  # no CLI equivalent; see docstring

    with _system_prompt_file(system_prompt) as prompt_path:
        cmd = [
            _CLAUDE_BIN,
            "-p",
            "--system-prompt-file", str(prompt_path),
            "--output-format", "json",
            "--model", model,
            # Disable every built-in tool (Bash, Edit, WebSearch, ...) —
            # tool access comes entirely from `skills` via the MCP bridge
            # below, so behavior matches the "local" backend's toolset
            # exactly rather than silently substituting a different
            # built-in capability (e.g. Claude Code's own web search in
            # place of WebSearchSkill).
            "--tools", "",
            # Load MCP servers ONLY from --mcp-config, ignoring anything
            # else configured on this machine, so the toolset this call
            # gets is exactly and only the bridge server below.
            "--strict-mcp-config",
            "--mcp-config", _mcp_config_json(skills),
            # Safe specifically because --tools "" + --strict-mcp-config +
            # the single bridge server above already bound the entire tool
            # surface to exactly `skills`. Do not widen the built-in
            # toolset here without revisiting this permission mode.
            "--permission-mode", "bypassPermissions",
            "--no-session-persistence",
            "--max-budget-usd", str(TRANSLATION_MAX_BUDGET_USD),
        ]

        env = dict(os.environ)
        # An API key present here would silently shadow the subscription
        # (OAuth) auth this backend depends on and switch to metered
        # billing — the exact outcome this backend exists to avoid.
        env.pop("ANTHROPIC_API_KEY", None)
        # Undocumented but empirically required: by default the CLI
        # connects to --mcp-config servers asynchronously and does not
        # reliably wait for the connection before the model's first turn.
        # Verified directly (opus, this exact bridge): with this unset, the
        # model reports the MCP tool as unavailable ~100% of the time even
        # though the CLI's own debug log shows the connection succeeding
        # ~350-400ms later — a startup race, not a config or schema
        # problem. Haiku happened to win the race in testing; opus (this
        # module's default model) consistently lost it. Setting this
        # forces the CLI to wait for the connection first.
        env["MCP_CONNECTION_NONBLOCKING"] = "false"

        try:
            proc = subprocess.run(
                cmd,
                input=user_message,
                capture_output=True,
                text=True,
                encoding="utf-8",
                timeout=_TIMEOUT_SECONDS,
                env=env,
            )
        except FileNotFoundError:
            raise ClaudeCodeError(
                f"Claude Code CLI not found ({_CLAUDE_BIN!r}). "
                "Install it, or set CLAUDE_BIN to its path."
            ) from None
        except subprocess.TimeoutExpired:
            raise ClaudeCodeError(
                f"Claude Code CLI call timed out after {_TIMEOUT_SECONDS}s."
            ) from None

    return _parse_result(proc)


# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------

@contextmanager
def _system_prompt_file(system_prompt: str) -> Iterator[Path]:
    """
    Write system_prompt to a temp file and yield its path, deleting it on
    exit. Used instead of --system-prompt (a raw argv value) to avoid
    shell-escaping issues with markdown content and stay clear of ARG_MAX
    on large prompts.
    """
    fd, path_str = tempfile.mkstemp(suffix=".md", prefix="hawk-system-prompt-")
    path = Path(path_str)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            f.write(system_prompt)
        yield path
    finally:
        path.unlink(missing_ok=True)


def _mcp_config_json(skills: "list[Skill] | None") -> str:
    """
    Build the --mcp-config JSON string: a single MCP server
    (src/mcp_servers/skill_bridge.py) configured to dynamically expose every
    given Skill as an MCP tool via its bridge_spec() (see src/skills/base.py).
    """
    specs = [skill.bridge_spec() for skill in (skills or [])]
    config = {
        "mcpServers": {
            "hawk_skills": {
                "command": sys.executable,
                "args": [str(_BRIDGE_SCRIPT)],
                "env": {"HAWK_SKILLS_SPEC": json.dumps(specs)},
            }
        }
    }
    return json.dumps(config)


def _parse_result(proc: "subprocess.CompletedProcess[str]") -> str:
    try:
        data = json.loads(proc.stdout)
    except json.JSONDecodeError:
        raise ClaudeCodeError(
            f"Claude Code CLI returned unparseable output "
            f"(exit code {proc.returncode}). "
            f"stdout: {proc.stdout[:500]!r} stderr: {proc.stderr[:500]!r}"
        ) from None

    # `is_error` is the reliable success/failure signal — `subtype` alone is
    # not: a bad-model test case returned subtype "success" with
    # is_error true.
    if proc.returncode != 0 or data.get("is_error"):
        raise ClaudeCodeError(
            f"Claude Code CLI call failed "
            f"(subtype={data.get('subtype')!r}, "
            f"api_error_status={data.get('api_error_status')!r}, "
            f"errors={data.get('errors')!r}): {data.get('result')!r}"
        )

    return data.get("result") or ""
