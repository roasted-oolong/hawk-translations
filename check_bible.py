#!/usr/bin/env python3
"""
check_bible.py
--------------
Diagnostic tool for detecting duplicate entries in bible files.

Checks for:
  1. Within-file duplicates — the same Korean name/term appearing more than
     once in the same bible file.
  2. Cross-file duplicates — the same Korean name/term appearing in more than
     one bible file.

Read-only. Makes no changes to any file.

Usage:
    python check_bible.py
"""

import sys
from collections import defaultdict
from pathlib import Path

from dotenv import load_dotenv

load_dotenv()

sys.path.insert(0, str(Path(__file__).parent))

from config import PROJECT_ROOT
from src.bible_utils import extract_headings_with_keys
from src.novel_resolver import resolve_novel

BIBLE_FILES = [
    "bible/characters.md",
    "bible/locations.md",
    "bible/terminology.md",
    "bible/cultural_phrases.md",
    "bible/story.md",
]


def check_bible(novel_dir: Path) -> bool:
    """
    Scan all bible files for duplicate entries.

    Parameters
    ----------
    novel_dir : Path
        Root directory of the novel.

    Returns
    -------
    bool
        True if no duplicates were found, False if any were found.
    """
    # key → list of (file, raw_heading) — for cross-file detection
    all_keys: dict[str, list[tuple[str, str]]] = defaultdict(list)

    within_file_issues = []
    clean = True

    print()

    for rel_path in BIBLE_FILES:
        file_path = novel_dir / rel_path
        if not file_path.exists():
            print(f"  [skip] {rel_path} — file not found")
            continue

        text = file_path.read_text(encoding="utf-8")
        pairs = extract_headings_with_keys(text)

        if not pairs:
            print(f"  [skip] {rel_path} — no entries found")
            continue

        # Within-file: look for duplicate keys in this file
        seen: dict[str, list[str]] = defaultdict(list)
        for raw, key in pairs:
            seen[key].append(raw)
            all_keys[key].append((rel_path, raw))

        file_dupes = {k: v for k, v in seen.items() if len(v) > 1}
        if file_dupes:
            within_file_issues.append((rel_path, file_dupes))
            clean = False

    # Report within-file duplicates
    if within_file_issues:
        print("  ── Within-file duplicates ─────────────────────────────")
        for rel_path, dupes in within_file_issues:
            print(f"\n  {rel_path}:")
            for key, headings in dupes.items():
                print(f"    Key: '{key}'")
                for h in headings:
                    print(f"      ## {h}")
    else:
        print("  ✓ No within-file duplicates found.")

    print()

    # Report cross-file duplicates
    cross_file = {
        k: v for k, v in all_keys.items()
        if len({f for f, _ in v}) > 1  # appears in more than one file
    }

    if cross_file:
        clean = False
        print("  ── Cross-file duplicates ──────────────────────────────")
        for key, occurrences in sorted(cross_file.items()):
            print(f"\n  Key: '{key}'")
            for rel_path, raw in occurrences:
                print(f"    {rel_path}: ## {raw}")
    else:
        print("  ✓ No cross-file duplicates found.")

    print()
    return clean


def main() -> None:
    print("\n" + "═" * 52)
    print("  HAWK TRANSLATIONS — BIBLE CHECK")
    print("═" * 52)

    project_root = Path(PROJECT_ROOT)
    novel_dir = resolve_novel(project_root, name=None)

    print(f"\n  Novel: {novel_dir.name}")
    print(f"  Checking {len(BIBLE_FILES)} bible files...\n")
    print("─" * 52)

    clean = check_bible(novel_dir)

    print("─" * 52)
    if clean:
        print("\n  ✓ Bible is clean. No duplicates found.\n")
    else:
        print("\n  ✗ Duplicates found — review output above.\n")


if __name__ == "__main__":
    main()
