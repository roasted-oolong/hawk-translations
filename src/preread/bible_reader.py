"""
src/preread/bible_reader.py
---------------------------
Responsible for one thing: reading all bible files and novel_info for a given
novel into memory, returning plain strings.

This module has no knowledge of the API, prompts, or chapter content.
It reads files. Nothing more.

Mirrors the reference-loading pattern from translate.py, restricted to the
files the preread function actually needs (no translation_guidelines,
no voice_calibration).
"""

from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path

# Bible files that the preread function reads and may update.
PREREAD_BIBLE_FILES = [
    "bible/characters.md",
    "bible/cultural_phrases.md",
    "bible/locations.md",
    "bible/story.md",
    "bible/terminology.md",
]


def _read_file(path: Path) -> str:
    """Read a file and return its text. Returns empty string if missing."""
    if not path.exists():
        print(f"  [warning] Bible file not found: {path.name}")
        return ""
    return path.read_text(encoding="utf-8")


def read_novel_info(novel_dir: Path) -> str:
    """Read and return novel_info.md for the given novel directory."""
    return _read_file(novel_dir / "novel_info.md")


def read_bible_files(novel_dir: Path) -> dict[str, str]:
    """
    Read all preread-relevant bible files in parallel.

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
    paths = {rel: novel_dir / rel for rel in PREREAD_BIBLE_FILES}

    results = {}
    with ThreadPoolExecutor() as executor:
        futures = {executor.submit(_read_file, path): key for key, path in paths.items()}
        for future in as_completed(futures):
            key = futures[future]
            results[key] = future.result()

    return results


def read_chapter_file(chapters_dir: Path, chapter_num: int) -> str:
    """
    Read a single Korean chapter file.

    Parameters
    ----------
    chapters_dir : Path
        The chapters/ directory for the novel.
    chapter_num : int
        The chapter number to read.

    Returns
    -------
    str
        File contents, or an error marker if the file cannot be read.
    """
    path = chapters_dir / f"ch{chapter_num}_korean"
    if not path.exists():
        return f"[ERROR: ch{chapter_num}_korean not found at {path}]"
    return path.read_text(encoding="utf-8")
