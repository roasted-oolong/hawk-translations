"""
tests/test_novel_resolver.py
------------------------------
Unit tests for src/novel_resolver.py's chapter discovery, focused on
find_korean_file — the shared per-chapter lookup extracted 2026-07-25 to
replace two separate, both-wrong hardcoded "ch{num}_korean" patterns in
src/preread/bible_reader.py and src/translator/chapter_loader.py. Neither
of those ever matched a real file on disk; real files are always named
like "Chapter 75 (Korean).txt".
"""

import sys
from pathlib import Path

from dotenv import load_dotenv

sys.path.insert(0, str(Path(__file__).parent.parent))
load_dotenv()  # config.py requires HAWK_PROJECT_ROOT to be set at import time

from src.novel_resolver import find_korean_file, find_next_chapter


def test_find_korean_file_matches_real_naming_convention(tmp_path):
    chapters_dir = tmp_path / "chapters"
    chapters_dir.mkdir()
    (chapters_dir / "Chapter 75 (Korean).txt").write_text("raw korean text", encoding="utf-8")

    found = find_korean_file(chapters_dir, 75)

    assert found == chapters_dir / "Chapter 75 (Korean).txt"


def test_find_korean_file_returns_none_when_missing(tmp_path):
    chapters_dir = tmp_path / "chapters"
    chapters_dir.mkdir()

    assert find_korean_file(chapters_dir, 75) is None


def test_find_korean_file_does_not_confuse_adjacent_chapter_numbers(tmp_path):
    chapters_dir = tmp_path / "chapters"
    chapters_dir.mkdir()
    (chapters_dir / "Chapter 7 (Korean).txt").write_text("chapter 7", encoding="utf-8")
    (chapters_dir / "Chapter 75 (Korean).txt").write_text("chapter 75", encoding="utf-8")

    found_7 = find_korean_file(chapters_dir, 7)
    found_75 = find_korean_file(chapters_dir, 75)

    assert found_7.read_text(encoding="utf-8") == "chapter 7"
    assert found_75.read_text(encoding="utf-8") == "chapter 75"


def test_find_korean_file_ignores_non_korean_files(tmp_path):
    chapters_dir = tmp_path / "chapters"
    chapters_dir.mkdir()
    (chapters_dir / "Chapter 75.txt").write_text("translated output, not source", encoding="utf-8")

    assert find_korean_file(chapters_dir, 75) is None


def test_find_next_chapter_still_works_via_shared_lookup(tmp_path):
    chapters_dir = tmp_path / "chapters"
    chapters_dir.mkdir()
    (chapters_dir / "Chapter 1 (Korean).txt").write_text("one", encoding="utf-8")
    (chapters_dir / "Chapter 1.txt").write_text("translated one", encoding="utf-8")
    (chapters_dir / "Chapter 2 (Korean).txt").write_text("two", encoding="utf-8")

    found = find_next_chapter(chapters_dir)

    assert found == chapters_dir / "Chapter 2 (Korean).txt"
