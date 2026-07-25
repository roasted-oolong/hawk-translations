"""
tests/test_bible_reader.py
----------------------------
Unit tests for src/preread/bible_reader.py's read_chapter_file — fixed
2026-07-25 to use src.novel_resolver.find_korean_file instead of a hardcoded
"ch{num}_korean" pattern that never matched any real file on disk (real
files are always named like "Chapter 75 (Korean).txt"). This bug meant
every preread/bible_build batch was fed an "[ERROR: ...]" placeholder
instead of real chapter text, silently.
"""

import sys
from pathlib import Path

from dotenv import load_dotenv

sys.path.insert(0, str(Path(__file__).parent.parent))
load_dotenv()  # config.py requires HAWK_PROJECT_ROOT to be set at import time

from src.preread.bible_reader import read_chapter_file


def test_read_chapter_file_reads_real_korean_source(tmp_path):
    chapters_dir = tmp_path / "chapters"
    chapters_dir.mkdir()
    (chapters_dir / "Chapter 75 (Korean).txt").write_text("실제 한국어 텍스트", encoding="utf-8")

    content = read_chapter_file(chapters_dir, 75)

    assert content == "실제 한국어 텍스트"


def test_read_chapter_file_returns_error_marker_when_missing(tmp_path):
    chapters_dir = tmp_path / "chapters"
    chapters_dir.mkdir()

    content = read_chapter_file(chapters_dir, 75)

    assert content.startswith("[ERROR:")
    assert "75" in content
