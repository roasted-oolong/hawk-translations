"""
src/bible_review/bible_reader.py
---------------------------------
Responsible for one thing: reading the translated chapter file and all
bible files needed for a post-translation review into memory as plain strings.

This module has no knowledge of the API, prompts, or pipeline orchestration.
It reads files. Nothing more.
"""

from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path

from src.novel_resolver import extract_chapter_number, find_translated_chapter_numbers

REVIEW_BIBLE_FILES = [
    "bible/characters.md",
    "bible/cultural_phrases.md",
    "bible/locations.md",
    "bible/story.md",
    "bible/terminology.md",
]


def _read_file(path: Path) -> str:
    """Read a file and return its text. Returns empty string if missing."""
    if not path.exists():
        print(f"  [warning] File not found: {path}")
        return ""
    return path.read_text(encoding="utf-8")


def read_novel_info(novel_dir: Path) -> str:
    """Read and return novel_info.md for the given novel directory."""
    return _read_file(novel_dir / "novel_info.md")


def read_bible_files(novel_dir: Path) -> dict[str, str]:
    """
    Read all review-relevant bible files in parallel.

    Parameters
    ----------
    novel_dir : Path
        Root directory of the novel.

    Returns
    -------
    dict[str, str]
        Keys are relative paths (e.g. "bible/characters.md").
        Values are file contents as strings.
    """
    paths = {rel: novel_dir / rel for rel in REVIEW_BIBLE_FILES}

    results = {}
    with ThreadPoolExecutor() as executor:
        futures = {executor.submit(_read_file, path): key for key, path in paths.items()}
        for future in as_completed(futures):
            key = futures[future]
            results[key] = future.result()

    return results


def find_latest_translated_chapter(chapters_dir: Path) -> int | None:
    """
    Return the highest chapter number that has a translated .txt file,
    or None if no translated chapters exist.
    """
    translated = find_translated_chapter_numbers(chapters_dir)
    return max(translated) if translated else None


def read_translated_chapter(chapters_dir: Path, chapter_num: int) -> str:
    """
    Read and return the translated .txt file for a given chapter number.

    Parameters
    ----------
    chapters_dir : Path
        The chapters/ directory for the novel.
    chapter_num : int
        The chapter number to read.

    Returns
    -------
    str
        File contents.

    Raises
    ------
    FileNotFoundError
        If no translated .txt file exists for the given chapter number.
    """
    for f in chapters_dir.iterdir():
        if not f.is_file():
            continue
        if f.suffix.lower() != ".txt":
            continue
        if "korean" in f.name.lower():
            continue
        if any("another translation" in part.lower() for part in f.parts):
            continue
        if extract_chapter_number(f.name) == chapter_num:
            return f.read_text(encoding="utf-8")

    raise FileNotFoundError(
        f"No translated .txt file found for chapter {chapter_num} in {chapters_dir}"
    )
