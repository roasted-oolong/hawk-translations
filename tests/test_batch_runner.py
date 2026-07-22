"""
tests/test_batch_runner.py
----------------------------
Unit tests for src/translator/batch_runner.py — sequential dispatch of
translation requests through the active backend (src/translation_backend.py).
"""

import sys
from pathlib import Path
from unittest.mock import MagicMock, patch

from dotenv import load_dotenv

sys.path.insert(0, str(Path(__file__).parent.parent))
load_dotenv()  # config.py requires HAWK_PROJECT_ROOT to be set at import time

from src.translator.batch_runner import run_translation_batch


def test_no_requests_does_not_call_backend():
    mock_backend = MagicMock()
    with patch("src.translator.batch_runner.get_backend", return_value=mock_backend):
        run_translation_batch(requests=[], on_result=MagicMock())

    mock_backend.assert_not_called()


def test_dispatches_each_request_and_reports_result():
    mock_backend = MagicMock(side_effect=["translated one", "translated two"])
    on_result = MagicMock()
    requests = [
        {"custom_id": "chapter-1", "params": {"system": "sys1", "messages": [{"role": "user", "content": "msg1"}]}},
        {"custom_id": "chapter-2", "params": {"system": "sys2", "messages": [{"role": "user", "content": "msg2"}]}},
    ]

    with patch("src.translator.batch_runner.get_backend", return_value=mock_backend):
        run_translation_batch(requests=requests, on_result=on_result)

    assert on_result.call_args_list == [
        (("chapter-1", "translated one"),),
        (("chapter-2", "translated two"),),
    ]


def test_passes_system_prompt_and_user_message_from_request_params():
    mock_backend = MagicMock(return_value="ok")
    requests = [{
        "custom_id": "chapter-1",
        "params": {"system": "the system prompt", "messages": [{"role": "user", "content": "the korean text"}]},
    }]

    with patch("src.translator.batch_runner.get_backend", return_value=mock_backend):
        run_translation_batch(requests=requests, on_result=MagicMock())

    _, kwargs = mock_backend.call_args
    assert kwargs["system_prompt"] == "the system prompt"
    assert kwargs["user_message"] == "the korean text"


def test_forwards_skills_unchanged_to_every_request():
    mock_backend = MagicMock(return_value="ok")
    fake_skills = ["skill-a", "skill-b"]
    requests = [
        {"custom_id": "chapter-1", "params": {"system": "s1", "messages": [{"role": "user", "content": "m1"}]}},
        {"custom_id": "chapter-2", "params": {"system": "s2", "messages": [{"role": "user", "content": "m2"}]}},
    ]

    with patch("src.translator.batch_runner.get_backend", return_value=mock_backend):
        run_translation_batch(requests=requests, on_result=MagicMock(), skills=fake_skills)

    for _, kwargs in mock_backend.call_args_list:
        assert kwargs["skills"] is fake_skills


def test_per_request_model_and_max_tokens_override_forwarded_when_present():
    mock_backend = MagicMock(return_value="ok")
    requests = [{
        "custom_id": "chapter-1",
        "params": {
            "system": "s", "messages": [{"role": "user", "content": "m"}],
            "model": "sonnet", "max_tokens": 5000,
        },
    }]

    with patch("src.translator.batch_runner.get_backend", return_value=mock_backend):
        run_translation_batch(requests=requests, on_result=MagicMock())

    _, kwargs = mock_backend.call_args
    assert kwargs["model"] == "sonnet"
    assert kwargs["max_tokens"] == 5000


def test_missing_model_and_max_tokens_forwarded_as_none():
    mock_backend = MagicMock(return_value="ok")
    requests = [{
        "custom_id": "chapter-1",
        "params": {"system": "s", "messages": [{"role": "user", "content": "m"}]},
    }]

    with patch("src.translator.batch_runner.get_backend", return_value=mock_backend):
        run_translation_batch(requests=requests, on_result=MagicMock())

    _, kwargs = mock_backend.call_args
    assert kwargs["model"] is None
    assert kwargs["max_tokens"] is None


def test_one_failure_does_not_stop_remaining_requests_and_is_reported(capsys):
    def side_effect(**kwargs):
        if kwargs["user_message"] == "bad":
            raise RuntimeError("boom")
        return "ok"

    mock_backend = MagicMock(side_effect=side_effect)
    on_result = MagicMock()
    requests = [
        {"custom_id": "chapter-1", "params": {"system": "s", "messages": [{"role": "user", "content": "bad"}]}},
        {"custom_id": "chapter-2", "params": {"system": "s", "messages": [{"role": "user", "content": "good"}]}},
    ]

    with patch("src.translator.batch_runner.get_backend", return_value=mock_backend):
        run_translation_batch(requests=requests, on_result=on_result)

    on_result.assert_called_once_with("chapter-2", "ok")
    assert "chapter-1: boom" in capsys.readouterr().out
