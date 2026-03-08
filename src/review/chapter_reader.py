"""
src/review/chapter_reader.py
-----------------------------
Responsible for one thing: reading the translated chapter file and
voice_calibration.md for a given novel into memory as plain strings.

This module has no knowledge of the API, prompts, or calibration logic.
It reads files. Nothing more.
"""

from pathlib import Path

from src.novel_resolver import extract_chapter_number, find_translated_chapter_numbers


def find_latest_translated_chapter(chapters_dir: Path) -> int | None:
    """
    Return the highest chapter number that has a translated .txt file,
    or None if no translated chapters exist.

    Parameters
    ----------
    chapters_dir : Path
        The chapters/ directory for the novel.
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
        if f.suffix.lower() != ".txt":
            continue
        if "korean" in f.name.lower():
            continue
        if "another translation" in f.name.lower():
            continue
        if extract_chapter_number(f.name) == chapter_num:
            return f.read_text(encoding="utf-8")

    raise FileNotFoundError(
        f"No translated .txt file found for chapter {chapter_num} "
        f"in {chapters_dir}"
    )


def read_voice_calibration(novel_dir: Path) -> str:
    """
    Read and return the contents of voice_calibration.md.

    Returns an empty string if the file does not exist, which the prompt
    builder will handle gracefully by omitting the section.

    Parameters
    ----------
    novel_dir : Path
        Root directory of the novel.
    """
    path = novel_dir / "bible" / "voice_calibration.md"
    if not path.exists():
        print(f"  [warning] voice_calibration.md not found — review will proceed without it.")
        return ""
    return path.read_text(encoding="utf-8")
