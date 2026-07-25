"""
tests/test_clean_chapter.py
----------------------------
Unit tests for clean_chapter.py's LLM call wiring. The actual LLM call is
mocked — this only pins down what gets sent to get_backend()'s returned
callable and how the response is parsed, not real model behavior.

2026-07-25: clean_chapter.py switched from a direct make_client()/raw OpenAI
client call to src.translation_backend.get_backend(FORMAT_BACKEND) — the
same seam every other pipeline script uses (see config.py's FORMAT_BACKEND).
The old reasoning_effort="low" test was removed: that tuning only applied to
the raw OpenAI client call, which is no longer on the default (claude_code)
path, and the seam has no reasoning_effort passthrough for the "local" path
either — a deliberate, documented tradeoff, not something to keep pinning.
"""

import sys
from io import BytesIO
from pathlib import Path
from unittest.mock import MagicMock, patch

sys.path.insert(0, str(Path(__file__).parent.parent))

import clean_chapter


def test_main_writes_cleaned_output_to_stdout(monkeypatch, capsys):
    fake_backend = MagicMock(
        return_value="=== CHAPTER 1 ===\ncleaned text\n=== END CHAPTER 1 ==="
    )

    monkeypatch.setattr(sys, "stdin", MagicMock(buffer=BytesIO("raw text".encode("utf-8"))))
    with patch.object(clean_chapter, "get_backend", return_value=fake_backend):
        clean_chapter.main()

    assert capsys.readouterr().out == "cleaned text"


def test_main_selects_backend_via_format_backend_config(monkeypatch):
    fake_backend = MagicMock(
        return_value="=== CHAPTER 1 ===\ncleaned text\n=== END CHAPTER 1 ==="
    )
    mock_get_backend = MagicMock(return_value=fake_backend)

    monkeypatch.setattr(sys, "stdin", MagicMock(buffer=BytesIO("raw text".encode("utf-8"))))
    with patch.object(clean_chapter, "get_backend", mock_get_backend):
        clean_chapter.main()

    mock_get_backend.assert_called_once_with(clean_chapter.FORMAT_BACKEND)


def test_main_passes_format_max_tokens_to_backend(monkeypatch):
    fake_backend = MagicMock(
        return_value="=== CHAPTER 1 ===\ncleaned text\n=== END CHAPTER 1 ==="
    )

    monkeypatch.setattr(sys, "stdin", MagicMock(buffer=BytesIO("raw text".encode("utf-8"))))
    with patch.object(clean_chapter, "get_backend", return_value=fake_backend):
        clean_chapter.main()

    _, kwargs = fake_backend.call_args
    assert kwargs["max_tokens"] == clean_chapter.FORMAT_MAX_TOKENS
