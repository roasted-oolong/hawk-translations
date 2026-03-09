"""
src/bible_review/bible_writer.py
----------------------------------
Responsible for one thing: writing bible review findings to bible files on disk.

New entries are appended immediately without confirmation, using the same
deduplication logic as src/preread/bible_writer.py — entries whose ## heading
already exists in the file are skipped with a warning.

Confirmed edits are applied by exact string replacement: the runner presents
each proposed edit to the user and passes approved ones here. This module
does not make decisions about what to write — it only writes what it is told.

Deduplication key logic lives in src/bible_utils.py and is shared across
all pipeline modules that read or write bible files.

This module has no knowledge of the API, prompts, interaction flow, or how
findings were generated. It receives content strings and paths. Nothing more.
"""

import re
from pathlib import Path

from src.bible_utils import extract_heading_keys

SECTION_TO_FILE = {
    "characters":       "bible/characters.md",
    "locations":        "bible/locations.md",
    "terminology":      "bible/terminology.md",
    "cultural_phrases": "bible/cultural_phrases.md",
    "story":            "bible/story.md",
}


# ---------------------------------------------------------------------------
# Entry splitting
# ---------------------------------------------------------------------------

def _split_into_entries(content: str) -> list[str]:
    """Split a markdown block into individual ## entries."""
    parts = re.split(r"(?=^## )", content, flags=re.MULTILINE)
    return [p.strip() for p in parts if p.strip()]


# ---------------------------------------------------------------------------
# Append logic
# ---------------------------------------------------------------------------

def append_new_entry(novel_dir: Path, section_key: str, content: str) -> None:
    """
    Append new content to the appropriate bible file, skipping duplicates.

    Parameters
    ----------
    novel_dir : Path
        Root directory of the novel.
    section_key : str
        Canonical section name (must be a key in SECTION_TO_FILE).
    content : str
        The content to append; may contain one or more ## entries.
    """
    if not content or not content.strip():
        return

    rel_path = SECTION_TO_FILE[section_key]
    file_path = novel_dir / rel_path

    if not file_path.exists():
        print(f"  [warning] Bible file not found, creating: {rel_path}")
        file_path.parent.mkdir(parents=True, exist_ok=True)
        file_path.write_text("", encoding="utf-8")

    existing = file_path.read_text(encoding="utf-8")
    existing_keys = extract_heading_keys(existing)

    new_entries = []
    skipped = []

    for entry in _split_into_entries(content):
        entry_keys = extract_heading_keys(entry)
        if not entry_keys:
            new_entries.append(entry)
            continue
        duplicate = entry_keys & existing_keys
        if duplicate:
            skipped.extend(duplicate)
        else:
            new_entries.append(entry)

    if skipped:
        print(f"    [dedup] Skipped already-existing entries: {skipped}")

    if not new_entries:
        return

    combined = "\n\n".join(new_entries)
    separator = "\n\n---\n\n" if existing.strip() else ""
    updated = existing.rstrip() + separator + combined + "\n"
    file_path.write_text(updated, encoding="utf-8")


def apply_edit(
    novel_dir: Path,
    section_key: str,
    entry_heading: str,
    field_current: str,
    field_proposed: str,
) -> bool:
    """
    Apply a single confirmed field edit to an existing bible entry.

    Finds the current text by exact match and replaces it with the proposed
    text. Returns True if the replacement was made, False if the current
    text was not found (e.g. the bible changed since the review ran).

    Parameters
    ----------
    novel_dir : Path
        Root directory of the novel.
    section_key : str
        Canonical section name.
    entry_heading : str
        The ## heading of the entry being edited (for logging only).
    field_current : str
        The exact text to replace.
    field_proposed : str
        The replacement text.

    Returns
    -------
    bool
        True if the edit was applied, False otherwise.
    """
    rel_path = SECTION_TO_FILE.get(section_key)
    if rel_path is None:
        print(f"  [error] Unknown section key: '{section_key}'")
        return False

    file_path = novel_dir / rel_path
    if not file_path.exists():
        print(f"  [error] Bible file not found: {rel_path}")
        return False

    existing = file_path.read_text(encoding="utf-8")

    if field_current not in existing:
        print(f"  [warning] Current text not found in {rel_path} — "
              "the bible may have changed since the review was run.")
        return False

    updated = existing.replace(field_current, field_proposed, 1)
    file_path.write_text(updated, encoding="utf-8")
    print(f"  ✓ Updated '{entry_heading}' in {rel_path}")
    return True


# ---------------------------------------------------------------------------
# Batch write for new entries
# ---------------------------------------------------------------------------

def write_new_entries(novel_dir: Path, new_entries: dict[str, str]) -> list[str]:
    """
    Write all new entries to their respective bible files.

    Parameters
    ----------
    novel_dir : Path
        Root directory of the novel.
    new_entries : dict[str, str]
        Section key → markdown content.

    Returns
    -------
    list[str]
        Section keys that had content written.
    """
    written = []
    for key, content in new_entries.items():
        if content and content.strip():
            append_new_entry(novel_dir, key, content)
            written.append(key)
    return written
