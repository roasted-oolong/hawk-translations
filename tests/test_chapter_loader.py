"""
tests/test_chapter_loader.py
------------------------------
Unit tests for src/translator/chapter_loader.py's build_chapter_request —
fixed 2026-07-25 to use src.novel_resolver.find_korean_file instead of a
hardcoded "ch{num:02d}_korean"/"ch{num}_korean" pattern that never matched
any real file on disk. This is the function translate_batch.py (invoked
directly by Rails' PipelineDispatcher for every translate_batch job) uses
to load each chapter's source text — the bug meant every chapter in every
batch translate job was silently skipped ("No Korean source file found"),
so batch translate jobs completed having translated nothing.
"""

import sys
from pathlib import Path

import pytest
from dotenv import load_dotenv

sys.path.insert(0, str(Path(__file__).parent.parent))
load_dotenv()  # config.py requires HAWK_PROJECT_ROOT to be set at import time

from config import NOVEL_FILES
from src.translator.chapter_loader import build_chapter_request

_EMPTY_REFERENCE_DATA = {key: "" for key in NOVEL_FILES}


def test_build_chapter_request_finds_real_korean_source(tmp_path):
    chapters_dir = tmp_path / "chapters"
    chapters_dir.mkdir()
    (chapters_dir / "Chapter 75 (Korean).txt").write_text("실제 한국어 텍스트", encoding="utf-8")

    _, korean_text = build_chapter_request(tmp_path, 75, _EMPTY_REFERENCE_DATA)

    assert korean_text == "실제 한국어 텍스트"


def test_build_chapter_request_raises_when_source_missing(tmp_path):
    chapters_dir = tmp_path / "chapters"
    chapters_dir.mkdir()

    with pytest.raises(FileNotFoundError, match="75"):
        build_chapter_request(tmp_path, 75, _EMPTY_REFERENCE_DATA)
