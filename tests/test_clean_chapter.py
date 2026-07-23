"""
tests/test_clean_chapter.py
----------------------------
Unit tests for clean_chapter.py's LLM call parameters. The actual LLM call
is mocked — this only pins down what gets sent, not real model behavior.
"""

import sys
from io import BytesIO
from pathlib import Path
from unittest.mock import MagicMock, patch

sys.path.insert(0, str(Path(__file__).parent.parent))

import clean_chapter


def make_fake_response(content):
    message = MagicMock(content=content)
    choice = MagicMock(message=message)
    return MagicMock(choices=[choice])


def test_main_requests_low_reasoning_effort(monkeypatch, capsys):
    # clean_chapter.py is the mechanical/HAIKU-tier formatting step — it
    # shouldn't spend the model's default (medium) reasoning budget on a
    # task that's just "fix line breaks, preserve everything exactly."
    # Measured 2026-07-16: reasoning_effort="low" produced ~half the
    # completion tokens of the default on the same prompt (303 vs 583).
    fake_response = make_fake_response("=== CHAPTER 1 ===\ncleaned text\n=== END CHAPTER 1 ===")
    mock_client = MagicMock()
    mock_client.chat.completions.create.return_value = fake_response

    monkeypatch.setattr(sys, "stdin", MagicMock(buffer=BytesIO("raw text".encode("utf-8"))))
    with patch.object(clean_chapter, "make_client", return_value=mock_client):
        clean_chapter.main()

    _, kwargs = mock_client.chat.completions.create.call_args
    assert kwargs["reasoning_effort"] == "low"


def test_main_still_writes_cleaned_output_to_stdout(monkeypatch, capsys):
    fake_response = make_fake_response("=== CHAPTER 1 ===\ncleaned text\n=== END CHAPTER 1 ===")
    mock_client = MagicMock()
    mock_client.chat.completions.create.return_value = fake_response

    monkeypatch.setattr(sys, "stdin", MagicMock(buffer=BytesIO("raw text".encode("utf-8"))))
    with patch.object(clean_chapter, "make_client", return_value=mock_client):
        clean_chapter.main()

    assert capsys.readouterr().out == "cleaned text"
