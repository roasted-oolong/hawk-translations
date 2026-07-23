"""
tests/test_ocr_chapter.py
--------------------------
Unit tests for ocr_chapter.py's Claude Code CLI invocation. The CLI itself
is mocked (via subprocess) so the suite stays fast and hermetic — it does
not require a live claude binary or Claude subscription auth. Real
end-to-end OCR accuracy was validated manually against real chapter photos
(see project notes, 2026-07-23) rather than in this automated suite,
matching how OcrChapterJob's own spec mocks Open3 rather than running real
OCR.
"""

import json
import subprocess
import sys
from pathlib import Path
from unittest.mock import MagicMock, patch

import pytest

sys.path.insert(0, str(Path(__file__).parent.parent))

import ocr_chapter


def _stream_json_stdout(result_text: str, is_error: bool = False) -> str:
    """Build a minimal --output-format stream-json transcript ending in a result event."""
    events = [
        {"type": "system", "subtype": "init"},
        {"type": "assistant", "message": {"content": [{"type": "text", "text": result_text}]}},
        {"type": "result", "is_error": is_error, "subtype": "success", "result": result_text},
    ]
    return "\n".join(json.dumps(e) for e in events) + "\n"


# ---------------------------------------------------------------------------
# transcribe_image
# ---------------------------------------------------------------------------

def test_transcribe_image_invokes_claude_cli_with_expected_args(tmp_path):
    image_path = tmp_path / "page.jpg"
    image_path.write_bytes(b"\xff\xd8\xff\xe0fake-jpeg-bytes")

    fake_result = MagicMock(
        returncode=0,
        stdout=_stream_json_stdout("추출된 텍스트"),
        stderr="",
    )

    with patch("subprocess.run", return_value=fake_result) as mock_run:
        text = ocr_chapter.transcribe_image(str(image_path))

    assert text == "추출된 텍스트"

    cmd = mock_run.call_args[0][0]
    assert cmd[0:2] == ["claude", "-p"]
    assert "--input-format" in cmd and "stream-json" in cmd
    assert "--output-format" in cmd and "stream-json" in cmd
    assert "--model" in cmd
    assert "--max-budget-usd" in cmd

    kwargs = mock_run.call_args.kwargs
    assert "ANTHROPIC_API_KEY" not in kwargs["env"]

    sent = json.loads(kwargs["input"])
    content_types = [block["type"] for block in sent["message"]["content"]]
    assert "image" in content_types
    assert "text" in content_types


def test_transcribe_image_raises_on_nonzero_exit(tmp_path):
    image_path = tmp_path / "page.jpg"
    image_path.write_bytes(b"fake")

    fake_result = MagicMock(returncode=1, stdout="", stderr="claude: auth error")
    with patch("subprocess.run", return_value=fake_result):
        with pytest.raises(RuntimeError, match="auth error"):
            ocr_chapter.transcribe_image(str(image_path))


def test_transcribe_image_raises_when_result_event_reports_error(tmp_path):
    image_path = tmp_path / "page.jpg"
    image_path.write_bytes(b"fake")

    fake_result = MagicMock(
        returncode=0,
        stdout=_stream_json_stdout("budget exceeded", is_error=True),
        stderr="",
    )
    with patch("subprocess.run", return_value=fake_result):
        with pytest.raises(RuntimeError, match="claude CLI reported error"):
            ocr_chapter.transcribe_image(str(image_path))


def test_transcribe_image_raises_on_missing_claude_binary(tmp_path):
    image_path = tmp_path / "page.jpg"
    image_path.write_bytes(b"fake")

    with patch("subprocess.run", side_effect=FileNotFoundError):
        with pytest.raises(RuntimeError, match="Claude Code CLI not found"):
            ocr_chapter.transcribe_image(str(image_path))


def test_transcribe_image_raises_on_timeout(tmp_path):
    image_path = tmp_path / "page.jpg"
    image_path.write_bytes(b"fake")

    with patch("subprocess.run", side_effect=subprocess.TimeoutExpired(cmd="claude", timeout=120)):
        with pytest.raises(RuntimeError, match="timed out"):
            ocr_chapter.transcribe_image(str(image_path))


# ---------------------------------------------------------------------------
# main() CLI contract
# ---------------------------------------------------------------------------

def test_main_exits_1_with_no_arguments(capsys):
    with patch.object(sys, "argv", ["ocr_chapter.py"]):
        with pytest.raises(SystemExit) as exc_info:
            ocr_chapter.main()

    assert exc_info.value.code == 1
    assert "no image paths given" in capsys.readouterr().err


def test_main_concatenates_transcriptions_in_argv_order(tmp_path, capsys):
    paths = [str(tmp_path / "a.jpg"), str(tmp_path / "b.jpg")]

    with patch.object(sys, "argv", ["ocr_chapter.py", *paths]):
        with patch.object(ocr_chapter, "transcribe_image", side_effect=["first page", "second page"]) as mock_ocr:
            ocr_chapter.main()

    assert mock_ocr.call_args_list == [((paths[0],),), ((paths[1],),)]
    assert capsys.readouterr().out == "first page\n\nsecond page"


def test_main_exits_1_and_writes_no_stdout_on_transcription_failure(tmp_path, capsys):
    source = tmp_path / "bad.jpg"
    source.write_bytes(b"fake")

    with patch.object(sys, "argv", ["ocr_chapter.py", str(source)]):
        with patch.object(ocr_chapter, "transcribe_image", side_effect=RuntimeError("boom")):
            with pytest.raises(SystemExit) as exc_info:
                ocr_chapter.main()

    assert exc_info.value.code == 1
    captured = capsys.readouterr()
    assert captured.out == ""
    assert "boom" in captured.err
