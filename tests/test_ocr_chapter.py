"""
tests/test_ocr_chapter.py
--------------------------
Unit tests for ocr_chapter.py's page-spread detection/splitting and the
Tesseract invocation it wraps. Tesseract itself is mocked (via subprocess)
so the suite stays fast and hermetic — it does not require Docker or the
hawk-tesseract image to be present. Real end-to-end OCR accuracy was
validated manually against real chapter photos (see project notes,
2026-07-15) rather than in this automated suite, matching how
OcrChapterJob's own spec mocks Open3 rather than running real OCR.
"""

import subprocess
import sys
from pathlib import Path
from unittest.mock import MagicMock, patch

import pytest
from PIL import Image

sys.path.insert(0, str(Path(__file__).parent.parent))

import ocr_chapter


# ---------------------------------------------------------------------------
# is_page_spread
# ---------------------------------------------------------------------------

def test_is_page_spread_true_for_landscape_ratio():
    # Real e-reader screenshots observed at 1920x1200 (ratio 1.60).
    image = Image.new("RGB", (1920, 1200))
    assert ocr_chapter.is_page_spread(image) is True


def test_is_page_spread_false_for_portrait_ratio():
    # A single book page is taller than wide.
    image = Image.new("RGB", (800, 1200))
    assert ocr_chapter.is_page_spread(image) is False


def test_is_page_spread_false_for_square_image():
    image = Image.new("RGB", (1000, 1000))
    assert ocr_chapter.is_page_spread(image) is False


def test_is_page_spread_respects_custom_threshold():
    image = Image.new("RGB", (1300, 1000))  # ratio 1.30
    assert ocr_chapter.is_page_spread(image, threshold=1.2) is True
    assert ocr_chapter.is_page_spread(image, threshold=1.5) is False


# ---------------------------------------------------------------------------
# split_spread
# ---------------------------------------------------------------------------

def test_split_spread_produces_two_equal_halves():
    image = Image.new("RGB", (1920, 1200))
    left, right = ocr_chapter.split_spread(image)

    assert left.size == (960, 1200)
    assert right.size == (960, 1200)


def test_split_spread_keeps_left_and_right_content_separate():
    # Left half red, right half blue — split must not mix or overlap them.
    image = Image.new("RGB", (1920, 1200))
    for x in range(1920):
        color = (255, 0, 0) if x < 960 else (0, 0, 255)
        for y in (0, 1199):
            image.putpixel((x, y), color)

    left, right = ocr_chapter.split_spread(image)

    assert left.getpixel((0, 0)) == (255, 0, 0)
    assert left.getpixel((959, 0)) == (255, 0, 0)
    assert right.getpixel((0, 0)) == (0, 0, 255)
    assert right.getpixel((959, 0)) == (0, 0, 255)


# ---------------------------------------------------------------------------
# run_tesseract
# ---------------------------------------------------------------------------

def test_run_tesseract_invokes_docker_with_expected_args(tmp_path):
    image_path = tmp_path / "page.png"
    Image.new("RGB", (10, 10)).save(image_path)

    def fake_run(cmd, **kwargs):
        # Simulate tesseract writing its output file alongside the input.
        output_base = tmp_path / "page"
        output_base.with_suffix(".txt").write_text("추출된 텍스트", encoding="utf-8")
        return MagicMock(returncode=0, stderr="")

    with patch("subprocess.run", side_effect=fake_run) as mock_run:
        text = ocr_chapter.run_tesseract(image_path, tmp_path)

    assert text == "추출된 텍스트"
    cmd = mock_run.call_args[0][0]
    assert cmd[0:2] == ["docker", "run"]
    assert f"{tmp_path}:/data" in cmd
    assert "hawk-tesseract:latest" in cmd
    assert "/data/page.png" in cmd
    assert "-l" in cmd and "kor" in cmd
    assert "--psm" in cmd and "4" in cmd


def test_run_tesseract_raises_on_nonzero_exit(tmp_path):
    image_path = tmp_path / "page.png"
    Image.new("RGB", (10, 10)).save(image_path)

    fake_result = MagicMock(returncode=1, stderr="docker: image not found")
    with patch("subprocess.run", return_value=fake_result):
        with pytest.raises(RuntimeError, match="docker: image not found"):
            ocr_chapter.run_tesseract(image_path, tmp_path)


# ---------------------------------------------------------------------------
# transcribe_image
# ---------------------------------------------------------------------------

def test_transcribe_image_single_page_calls_tesseract_once(tmp_path):
    source = tmp_path / "source.jpg"
    Image.new("RGB", (800, 1200)).save(source)  # portrait — not a spread

    with patch.object(ocr_chapter, "run_tesseract", return_value="single page text") as mock_ocr:
        result = ocr_chapter.transcribe_image(str(source), tmp_path)

    assert mock_ocr.call_count == 1
    assert result == "single page text"


def test_transcribe_image_spread_calls_tesseract_twice_in_reading_order(tmp_path):
    source = tmp_path / "source.jpg"
    Image.new("RGB", (1920, 1200)).save(source)  # landscape — a spread

    with patch.object(ocr_chapter, "run_tesseract", side_effect=["left text", "right text"]) as mock_ocr:
        result = ocr_chapter.transcribe_image(str(source), tmp_path)

    assert mock_ocr.call_count == 2
    assert result == "left text\n\nright text"


# ---------------------------------------------------------------------------
# main() CLI contract
# ---------------------------------------------------------------------------

def test_main_exits_1_with_no_arguments(capsys):
    with patch.object(sys, "argv", ["ocr_chapter.py"]):
        with pytest.raises(SystemExit) as exc_info:
            ocr_chapter.main()

    assert exc_info.value.code == 1
    assert "no image paths given" in capsys.readouterr().err


def test_main_exits_1_and_writes_no_stdout_on_transcription_failure(tmp_path, capsys):
    source = tmp_path / "bad.jpg"
    Image.new("RGB", (800, 1200)).save(source)

    with patch.object(sys, "argv", ["ocr_chapter.py", str(source)]):
        with patch.object(ocr_chapter, "transcribe_image", side_effect=RuntimeError("boom")):
            with pytest.raises(SystemExit) as exc_info:
                ocr_chapter.main()

    assert exc_info.value.code == 1
    captured = capsys.readouterr()
    assert captured.out == ""
    assert "boom" in captured.err
