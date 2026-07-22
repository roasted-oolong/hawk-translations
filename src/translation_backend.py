"""
src/translation_backend.py
---------------------------
Selects which LLM backend the translation call sites (translate.py,
translate_batch.py, src/translator/batch_runner.py) use, without those call
sites needing to know or care which one is active.

Two backends exist today:
  - "local": the existing Ollama-backed path (src/agent.py), unchanged.
  - "claude_code": shells out to the Claude Code CLI, authenticated via the
    user's Claude subscription instead of a metered API key
    (src/claude_code_agent.py).

Both backends accept the exact same skills=[...] list (Skill instances from
src/skills/) — see src/mcp_servers/skill_bridge.py for how "claude_code"
exposes them as MCP tools without any per-skill code.

`model` is intentionally optional and backend-specific: "local" model names
(e.g. "gpt-oss-20b") mean nothing to "claude_code" (which expects a Claude
model alias like "opus"), and vice versa. Call sites that don't pass `model`
get that backend's own sensible default — this is what lets
TRANSLATION_BACKEND be flipped without touching translate.py/
translate_batch.py at all.

Selected via config.TRANSLATION_BACKEND (env var TRANSLATION_BACKEND). This
is the only place that decision is made — adding a third backend later means
adding one branch here, not touching any call site.
"""

from typing import TYPE_CHECKING, Protocol

from config import TRANSLATION_BACKEND

if TYPE_CHECKING:
    from src.skills.base import Skill


class TranslationBackend(Protocol):
    def __call__(
        self,
        system_prompt: str,
        user_message: str,
        *,
        model: str | None = None,
        max_tokens: int | None = None,
        skills: "list[Skill] | None" = None,
    ) -> str: ...


# ---------------------------------------------------------------------------
# "local" backend — thin wrapper around the existing src/agent.py
# ---------------------------------------------------------------------------

_local_client = None


def _local_backend(
    system_prompt: str,
    user_message: str,
    *,
    model: str | None = None,
    max_tokens: int | None = None,
    skills: "list[Skill] | None" = None,
) -> str:
    from src.agent import call, make_client

    global _local_client
    if _local_client is None:
        _local_client = make_client()

    # Omit model/max_tokens when not given so src.agent.call()'s own
    # defaults (OPUS_MODEL / MAX_TOKENS) apply — those defaults are already
    # correct for this backend.
    kwargs = {}
    if model is not None:
        kwargs["model"] = model
    if max_tokens is not None:
        kwargs["max_tokens"] = max_tokens

    return call(
        system_prompt=system_prompt,
        user_message=user_message,
        client=_local_client,
        skills=skills,
        **kwargs,
    )


def _claude_code_backend(
    system_prompt: str,
    user_message: str,
    *,
    model: str | None = None,
    max_tokens: int | None = None,
    skills: "list[Skill] | None" = None,
) -> str:
    from src.claude_code_agent import call as claude_code_call

    # Same reasoning as _local_backend above, but the other direction: a
    # caller-supplied "local" model name would be meaningless here.
    kwargs = {}
    if model is not None:
        kwargs["model"] = model
    if max_tokens is not None:
        kwargs["max_tokens"] = max_tokens

    return claude_code_call(
        system_prompt=system_prompt,
        user_message=user_message,
        skills=skills,
        **kwargs,
    )


# ---------------------------------------------------------------------------
# Backend registry
# ---------------------------------------------------------------------------

_BACKENDS: dict[str, TranslationBackend] = {
    "local": _local_backend,
    "claude_code": _claude_code_backend,
}


def get_backend(name: str | None = None) -> TranslationBackend:
    """
    Return the translation backend selected by name, or by
    config.TRANSLATION_BACKEND if name is not given.

    Raises ValueError for an unrecognized backend name so a typo in
    TRANSLATION_BACKEND fails loudly instead of silently picking a default.
    """
    selected = name or TRANSLATION_BACKEND
    try:
        return _BACKENDS[selected]
    except KeyError:
        raise ValueError(
            f"Unknown TRANSLATION_BACKEND {selected!r}. "
            f"Valid options: {sorted(_BACKENDS)}"
        ) from None
