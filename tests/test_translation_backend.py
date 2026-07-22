"""
tests/test_translation_backend.py
----------------------------------
Unit tests for src/translation_backend.py — the seam that lets
translate.py/translate_batch.py switch between the "local" (Ollama) and
"claude_code" backends without changing call sites.
"""

import sys
from pathlib import Path
from unittest.mock import MagicMock, patch

import pytest
from dotenv import load_dotenv

sys.path.insert(0, str(Path(__file__).parent.parent))
load_dotenv()  # config.py requires HAWK_PROJECT_ROOT to be set at import time

import src.translation_backend as translation_backend


def test_get_backend_unknown_name_raises():
    with pytest.raises(ValueError, match="Unknown backend"):
        translation_backend.get_backend("bogus")


def test_get_backend_local_returns_local_backend():
    assert translation_backend.get_backend("local") is translation_backend._local_backend


def test_get_backend_claude_code_returns_claude_code_backend():
    assert (
        translation_backend.get_backend("claude_code")
        is translation_backend._claude_code_backend
    )


def test_get_backend_defaults_to_config_value(monkeypatch):
    monkeypatch.setattr(translation_backend, "TRANSLATION_BACKEND", "claude_code")
    assert translation_backend.get_backend() is translation_backend._claude_code_backend

    monkeypatch.setattr(translation_backend, "TRANSLATION_BACKEND", "local")
    assert translation_backend.get_backend() is translation_backend._local_backend


def test_local_backend_delegates_to_agent_call(monkeypatch):
    fake_client = object()
    mock_make_client = MagicMock(return_value=fake_client)
    mock_call = MagicMock(return_value="translated text")

    monkeypatch.setattr(translation_backend, "_local_client", None)
    with patch("src.agent.make_client", mock_make_client), \
         patch("src.agent.call", mock_call):
        result = translation_backend._local_backend(
            system_prompt="sys", user_message="msg", skills=["a-skill"],
        )

    assert result == "translated text"
    mock_call.assert_called_once_with(
        system_prompt="sys", user_message="msg", client=fake_client, skills=["a-skill"],
    )


def test_local_backend_caches_client_across_calls(monkeypatch):
    mock_make_client = MagicMock(return_value=object())
    monkeypatch.setattr(translation_backend, "_local_client", None)
    with patch("src.agent.make_client", mock_make_client), \
         patch("src.agent.call", MagicMock(return_value="")):
        translation_backend._local_backend(system_prompt="a", user_message="b")
        translation_backend._local_backend(system_prompt="c", user_message="d")

    mock_make_client.assert_called_once()


def test_local_backend_forwards_model_and_max_tokens_only_when_given(monkeypatch):
    mock_call = MagicMock(return_value="")
    monkeypatch.setattr(translation_backend, "_local_client", object())
    with patch("src.agent.call", mock_call):
        translation_backend._local_backend(
            system_prompt="a", user_message="b", model="qwen2.5:32b", max_tokens=8000,
        )

    _, kwargs = mock_call.call_args
    assert kwargs["model"] == "qwen2.5:32b"
    assert kwargs["max_tokens"] == 8000


def test_claude_code_backend_delegates_and_omits_none_kwargs():
    mock_call = MagicMock(return_value="translated text")
    with patch("src.claude_code_agent.call", mock_call):
        result = translation_backend._claude_code_backend(
            system_prompt="sys", user_message="msg", skills=["a-skill"],
        )

    assert result == "translated text"
    mock_call.assert_called_once_with(
        system_prompt="sys", user_message="msg", skills=["a-skill"],
    )
    _, kwargs = mock_call.call_args
    assert "model" not in kwargs
    assert "max_tokens" not in kwargs


def test_claude_code_backend_forwards_model_when_given():
    mock_call = MagicMock(return_value="")
    with patch("src.claude_code_agent.call", mock_call):
        translation_backend._claude_code_backend(
            system_prompt="a", user_message="b", model="sonnet",
        )

    _, kwargs = mock_call.call_args
    assert kwargs["model"] == "sonnet"
