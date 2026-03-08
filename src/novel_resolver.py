"""
src/novel_resolver.py
---------------------
Responsible for two related concerns:
  1. Resolving a novel directory from a name or interactive prompt.
  2. Discovering which chapters exist and which are untranslated.

Previously this logic was duplicated across translate.py and preread.py
(novel listing/resolution) and between translate.py and
src/preread/chapter_resolver.py (chapter number extraction and next-chapter
discovery). It lives here now — one canonical version for both entry points.

This module has no knowledge of the API, prompts, or bible files. It reads
the filesystem and applies selection logic. Nothing more.
"""

import re
import sys
from pathlib import Path


# ---------------------------------------------------------------------------
# Novel listing and resolution
# ---------------------------------------------------------------------------

def list_novels(project_root: Path) -> list[Path]:
    """
    Return all valid novel directories under the project root.

    A valid novel directory contains both a chapters/ and bible/ subdirectory.
    Template directories (prefixed with _) and hidden directories are excluded.
    """
    return sorted(
        d for d in project_root.iterdir()
        if d.is_dir()
        and not d.name.startswith("_")
        and not d.name.startswith(".")
        and (d / "chapters").is_dir()
        and (d / "bible").is_dir()
    )


def resolve_novel(project_root: Path, name: str | None) -> Path:
    """
    Resolve the novel directory from an optional name argument.

    If name is provided, match it against available novels (case-insensitive,
    partial match allowed). If no name is provided and only one novel exists,
    select it automatically. Otherwise prompt the user to choose.

    Parameters
    ----------
    project_root : Path
        Root of the translations project.
    name : str | None
        Novel name from CLI argument or user input, or None to prompt.

    Returns
    -------
    Path
        The resolved novel directory.

    Raises
    ------
    SystemExit
        If no novels are found, or if the provided name is ambiguous or
        unrecognised.
    """
    novels = list_novels(project_root)

    if not novels:
        print("\n  [error] No novel directories found in project root.")
        sys.exit(1)

    if name:
        matches = [n for n in novels if name.lower() in n.name.lower()]
        if len(matches) == 1:
            return matches[0]
        if len(matches) > 1:
            print(f"\n  [error] '{name}' matches multiple novels:")
            for m in matches:
                print(f"    - {m.name}")
            sys.exit(1)
        print(f"\n  [error] No novel matching '{name}' found.")
        sys.exit(1)

    if len(novels) == 1:
        print(f"  Novel: {novels[0].name}")
        return novels[0]

    print("\n  Available novels:")
    for i, novel in enumerate(novels, 1):
        print(f"    {i}. {novel.name}")

    while True:
        choice = input("\n  Select a novel (number or name):\n  > ").strip()
        if not choice:
            continue

        if choice.isdigit():
            index = int(choice) - 1
            if 0 <= index < len(novels):
                return novels[index]
            print("\n  [error] Invalid selection. Try again.")
            continue

        matches = [n for n in novels if choice.lower() in n.name.lower()]
        if len(matches) == 1:
            return matches[0]
        if len(matches) > 1:
            print(f"  '{choice}' matches more than one novel. Be more specific.")
            continue
        print(f"  No novel matching '{choice}'. Try again.")


# ---------------------------------------------------------------------------
# Chapter number extraction
# ---------------------------------------------------------------------------

def extract_chapter_number(filename: str) -> int | None:
    """Return the first integer found in a filename, or None if absent."""
    match = re.search(r"(\d+)", filename)
    return int(match.group(1)) if match else None


# ---------------------------------------------------------------------------
# Chapter discovery
# ---------------------------------------------------------------------------

def find_translated_chapter_numbers(chapters_dir: Path) -> set[int]:
    """
    Return the set of chapter numbers that already have a translated .txt file.

    Excludes Korean source files and reference translations (any file or
    directory whose name contains "another translation").
    """
    translated = set()
    for f in chapters_dir.iterdir():
        if not f.is_file():
            continue
        if f.suffix.lower() != ".txt":
            continue
        if "korean" in f.name.lower():
            continue
        if "another translation" in f.name.lower():
            continue
        n = extract_chapter_number(f.name)
        if n is not None:
            translated.add(n)
    return translated


def find_all_korean_chapters(chapters_dir: Path) -> list[int]:
    """Return sorted list of all chapter numbers with a *_korean source file."""
    nums = []
    for f in chapters_dir.iterdir():
        if "korean" in f.name.lower() and f.is_file():
            n = extract_chapter_number(f.name)
            if n is not None:
                nums.append(n)
    return sorted(nums)


def find_untranslated_chapters(chapters_dir: Path) -> list[int]:
    """
    Return sorted list of chapter numbers that have a Korean source file
    but no corresponding translated .txt file.
    """
    all_korean = find_all_korean_chapters(chapters_dir)
    translated = find_translated_chapter_numbers(chapters_dir)
    return [n for n in all_korean if n not in translated]


def find_next_chapter(chapters_dir: Path) -> Path | None:
    """
    Find the lowest-numbered Korean source file that has no corresponding
    translated output file in the chapters directory.

    Parameters
    ----------
    chapters_dir : Path
        The chapters directory for the selected novel.

    Returns
    -------
    Path | None
        Path to the next untranslated Korean file, or None if all are done.
    """
    untranslated = find_untranslated_chapters(chapters_dir)
    if not untranslated:
        return None

    next_num = untranslated[0]
    # Find the actual file path for this chapter number.
    for f in chapters_dir.iterdir():
        if "korean" in f.name.lower() and f.is_file():
            if extract_chapter_number(f.name) == next_num:
                return f
    return None
