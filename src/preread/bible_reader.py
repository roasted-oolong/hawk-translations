"""
src/preread/bible_reader.py
---------------------------
Responsible for one thing: reading all bible files and novel_info for a given
novel into memory, returning plain strings.

This module has no knowledge of the API, prompts, or chapter content.
It reads files. Nothing more.

The set of bible files to load is derived from config.NOVEL_FILES, filtered
to the subset the preread function actually needs. This means adding a new
bible file to config.py is sufficient — no changes needed here.
"""

import sys
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent.parent))

from config import NOVEL_FILES

# Keys from NOVEL_FILES that preread does not need.
# Translation-specific files are excluded — preread has no use for them.
_PREREAD_SKIP = {"translation_guidelines", "voice_calibration", "novel_info"}

# Relative paths (from novel_dir) of the bible files preread reads and may update.
# Derived from config so there is a single source of truth.
PREREAD_BIBLE_FILES: list[str] = [
    f"bible/{filename}"
    for key, (filename, location) in NOVEL_FILES.items()
    if key not in _PREREAD_SKIP and location == "bible"
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
