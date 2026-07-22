"""
tests/test_claude_code_agent.py
----------------------------------
Unit tests for src/claude_code_agent.py — the "claude_code" translation
backend, which shells out to `claude -p` instead of calling a metered API.

subprocess.run is mocked throughout; nothing here makes a real Claude Code
call.
"""

import json
import subprocess
import sys
from pathlib import Path
from unittest.mock import MagicMock, patch

import pytest
from dotenv import load_dotenv

sys.path.insert(0, str(Path(__file__).parent.parent))
load_dotenv()  # config.py requires HAWK_PROJECT_ROOT to be set at import time

import src.claude_code_agent as claude_code_agent
from src.claude_code_agent import ClaudeCodeError, call


class _FakeSkill:
    """Minimal stand-in for a Skill, for exercising the --mcp-config wiring."""

    def bridge_spec(self):
        return {"module": "fake.module", "class": "FakeSkill", "kwargs": {"x": 1}}


def _completed_process(stdout: dict | str, returncode: int = 0) -> subprocess.CompletedProcess:
    text = stdout if isinstance(stdout, str) else json.dumps(stdout)
    return subprocess.CompletedProcess(args=[], returncode=returncode, stdout=text, stderr="")


def _success_json(result: str = "translated text") -> dict:
    return {
        "type": "result",
        "subtype": "success",
        "is_error": False,
        "result": result,
        "total_cost_usd": 0.01,
        "session_id": "abc123",
        "terminal_reason": "completed",
    }


def test_call_returns_result_on_success():
    mock_run = MagicMock(return_value=_completed_process(_success_json("hello world")))
    with patch("subprocess.run", mock_run):
        result = call(system_prompt="sys", user_message="msg")

    assert result == "hello world"


def test_call_pipes_user_message_over_stdin():
    mock_run = MagicMock(return_value=_completed_process(_success_json()))
    with patch("subprocess.run", mock_run):
        call(system_prompt="sys", user_message="한국어 텍스트")

    _, kwargs = mock_run.call_args
    assert kwargs["input"] == "한국어 텍스트"


def test_call_writes_system_prompt_to_a_file_and_cleans_up_after():
    written_content = None
    written_path = None

    def side_effect(cmd, **kwargs):
        nonlocal written_content, written_path
        idx = cmd.index("--system-prompt-file")
        written_path = Path(cmd[idx + 1])
        written_content = written_path.read_text(encoding="utf-8")
        return _completed_process(_success_json())

    with patch("subprocess.run", side_effect=side_effect):
        call(system_prompt="the full system prompt", user_message="msg")

    assert written_content == "the full system prompt"
    assert not written_path.exists(), "temp system-prompt file should be deleted after the call"


def test_call_builds_expected_argv():
    mock_run = MagicMock(return_value=_completed_process(_success_json()))
    with patch("subprocess.run", mock_run), \
         patch("src.claude_code_agent.TRANSLATION_MAX_BUDGET_USD", 3.0):
        call(system_prompt="sys", user_message="msg", model="opus")

    cmd, _ = mock_run.call_args
    argv = cmd[0]
    assert argv[0] == claude_code_agent._CLAUDE_BIN
    assert "-p" in argv
    assert "--output-format" in argv and argv[argv.index("--output-format") + 1] == "json"
    assert "--model" in argv and argv[argv.index("--model") + 1] == "opus"
    assert "--tools" in argv and argv[argv.index("--tools") + 1] == ""
    assert "--strict-mcp-config" in argv
    assert "--permission-mode" in argv and argv[argv.index("--permission-mode") + 1] == "bypassPermissions"
    assert "--no-session-persistence" in argv
    assert "--max-budget-usd" in argv and argv[argv.index("--max-budget-usd") + 1] == "3.0"


def test_call_mcp_config_serializes_given_skills():
    mock_run = MagicMock(return_value=_completed_process(_success_json()))
    with patch("subprocess.run", mock_run):
        call(system_prompt="sys", user_message="msg", skills=[_FakeSkill()])

    cmd, _ = mock_run.call_args
    argv = cmd[0]
    mcp_config = json.loads(argv[argv.index("--mcp-config") + 1])
    server = mcp_config["mcpServers"]["hawk_skills"]
    assert server["command"] == sys.executable
    specs = json.loads(server["env"]["HAWK_SKILLS_SPEC"])
    assert specs == [{"module": "fake.module", "class": "FakeSkill", "kwargs": {"x": 1}}]


def test_call_mcp_config_is_empty_when_no_skills_given():
    mock_run = MagicMock(return_value=_completed_process(_success_json()))
    with patch("subprocess.run", mock_run):
        call(system_prompt="sys", user_message="msg")

    cmd, _ = mock_run.call_args
    argv = cmd[0]
    mcp_config = json.loads(argv[argv.index("--mcp-config") + 1])
    specs = json.loads(mcp_config["mcpServers"]["hawk_skills"]["env"]["HAWK_SKILLS_SPEC"])
    assert specs == []


def test_call_strips_anthropic_api_key_from_subprocess_env(monkeypatch):
    monkeypatch.setenv("ANTHROPIC_API_KEY", "sk-should-never-be-sent")
    mock_run = MagicMock(return_value=_completed_process(_success_json()))
    with patch("subprocess.run", mock_run):
        call(system_prompt="sys", user_message="msg")

    _, kwargs = mock_run.call_args
    assert "ANTHROPIC_API_KEY" not in kwargs["env"]


def test_call_forces_mcp_connection_blocking():
    # Regression guard: empirically, without this the CLI does not
    # reliably wait for the --mcp-config server to connect before the
    # model's first turn, so MCP-provided skills silently go unseen (see
    # the code comment in claude_code_agent.py for how this was found).
    mock_run = MagicMock(return_value=_completed_process(_success_json()))
    with patch("subprocess.run", mock_run):
        call(system_prompt="sys", user_message="msg")

    _, kwargs = mock_run.call_args
    assert kwargs["env"]["MCP_CONNECTION_NONBLOCKING"] == "false"


def test_call_raises_on_is_error_true():
    error_json = {
        "is_error": True,
        "subtype": "success",  # verified: subtype is NOT a reliable signal
        "api_error_status": None,
        "errors": ["There's an issue with the selected model"],
        "result": "explanation text",
    }
    mock_run = MagicMock(return_value=_completed_process(error_json, returncode=1))
    with patch("subprocess.run", mock_run):
        with pytest.raises(ClaudeCodeError, match="explanation text"):
            call(system_prompt="sys", user_message="msg")


def test_call_raises_on_nonzero_exit_even_without_is_error_flag():
    # Defensive: don't trust a missing/false is_error if the exit code says
    # otherwise.
    mock_run = MagicMock(return_value=_completed_process({"result": "?"}, returncode=1))
    with patch("subprocess.run", mock_run):
        with pytest.raises(ClaudeCodeError):
            call(system_prompt="sys", user_message="msg")


def test_call_raises_on_unparseable_stdout():
    mock_run = MagicMock(return_value=_completed_process("not json", returncode=0))
    with patch("subprocess.run", mock_run):
        with pytest.raises(ClaudeCodeError, match="unparseable"):
            call(system_prompt="sys", user_message="msg")


def test_call_raises_on_timeout():
    mock_run = MagicMock(side_effect=subprocess.TimeoutExpired(cmd="claude", timeout=1200))
    with patch("subprocess.run", mock_run):
        with pytest.raises(ClaudeCodeError, match="timed out"):
            call(system_prompt="sys", user_message="msg")


def test_call_raises_when_claude_binary_missing():
    mock_run = MagicMock(side_effect=FileNotFoundError())
    with patch("subprocess.run", mock_run):
        with pytest.raises(ClaudeCodeError, match="not found"):
            call(system_prompt="sys", user_message="msg")
