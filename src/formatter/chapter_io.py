"""
src/formatter/chapter_io.py
---------------------------
Responsible for one thing: reading Korean source files and overwriting them
with formatted content for a given chapter.

This module has no knowledge of the API, prompts, or formatting logic.
It reads and writes files. Nothing more.

Formatted output overwrites the original ch##_korean source file in-place.
Once a chapter is formatted, the pipeline downstream automatically reads
the clean version.
"""

from pathlib import Path


# ---------------------------------------------------------------------------
# Path resolution
# ---------------------------------------------------------------------------

def resolve_chapter_path(chapters_dir: Path, chapter_num: int) -> Path:
    """
    Locate the Korean source file for a given chapter number.

    Tries zero-padded name first (ch05_korean), then plain integer (ch5_korean).

    Parameters
    ----------
    chapters_dir : Path
        The chapters/ directory for the novel.
    chapter_num : int
        The chapter number to look up.

    Returns
    -------
    Path
        The resolved path to the Korean source file.

    Raises
    ------
    FileNotFoundError
        If no matching file is found under either naming convention.
    """
    for name in (f"ch{chapter_num:02d}_korean", f"ch{chapter_num}_korean"):
        path = chapters_dir / name
        if path.exists():
            return path
    raise FileNotFoundError(
        f"No Korean source file found for chapter {chapter_num} in {chapters_dir}"
    )


# ---------------------------------------------------------------------------
# Read / write
# ---------------------------------------------------------------------------

def read_korean_chapter(chapters_dir: Path, chapter_num: int) -> str:
    """
    Read a Korean source chapter file.

    Parameters
    ----------
    chapters_dir : Path
        The chapters/ directory for the novel.
    chapter_num : int
        The chapter number to read.

    Returns
    -------
    str
        File contents as a string.

    Raises
    ------
    FileNotFoundError
        If no matching Korean source file exists for the given chapter number.
    """
    path = resolve_chapter_path(chapters_dir, chapter_num)
    return path.read_text(encoding="utf-8")


def overwrite_chapter_file(chapters_dir: Path, chapter_num: int, content: str) -> Path:
    """
    Overwrite the Korean source file for a chapter with formatted content.

    Resolves the original file path so the same naming convention is preserved.

    Parameters
    ----------
    chapters_dir : Path
        The chapters/ directory for the novel.
    chapter_num : int
        The chapter number being written.
    content : str
        The formatted text to write.

    Returns
    -------
    Path
        The path to the overwritten file.

    Raises
    ------
    FileNotFoundError
        If the source file cannot be found (nothing to overwrite).
    """
    path = resolve_chapter_path(chapters_dir, chapter_num)
    path.write_text(content, encoding="utf-8")
    return path
