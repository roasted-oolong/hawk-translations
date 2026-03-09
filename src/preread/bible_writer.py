"""
src/preread/bible_writer.py
---------------------------
Responsible for one thing: appending preread findings to bible files on disk,
without creating duplicate entries.

Before writing, each incoming entry is checked against the headings already
present in the file. Entries whose heading already exists are skipped.

The Korean name/term is the canonical unique identifier for every entry.
Deduplication key logic lives in src/bible_utils.py and is shared across
all pipeline modules that read or write bible files.

This module has no knowledge of the API, prompts, or chapter discovery.
It receives parsed content strings and writes them to the correct files.
Nothing more.
"""

import re
from pathlib import Path

from src.bible_utils import extract_heading_keys

# Maps canonical section key → relative path within novel_dir.
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
    """
    Split a block of markdown content into individual ## entries.

    Each entry begins with a ## heading and runs until the next ## heading
    or the end of the string. Entries with no ## heading are returned as a
    single block (e.g. plain prose in the STORY section).

    Parameters
    ----------
    content : str
        Raw content string, possibly containing multiple ## entries.

    Returns
    -------
    list[str]
        List of individual entry strings, each starting with "## ...".
        If no ## headings are found, returns [content] as a single item.
    """
    parts = re.split(r"(?=^## )", content, flags=re.MULTILINE)
    return [p.strip() for p in parts if p.strip()]


# ---------------------------------------------------------------------------
# Write logic
# ---------------------------------------------------------------------------

def append_to_bible(novel_dir: Path, section_key: str, content: str) -> None:
    """
    Append a parsed section's content to the appropriate bible file,
    skipping any entries whose Korean name (or normalised English fallback)
    already exists in the file.

    Parameters
    ----------
    novel_dir : Path
        Root directory of the novel.
    section_key : str
        Canonical section name (must be a key in SECTION_TO_FILE).
    content : str
        The content to append, may contain one or more ## entries.

    Raises
    ------
    KeyError
        If section_key is not recognised.
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

    entries = _split_into_entries(content)

    new_entries = []
    skipped_headings = []

    for entry in entries:
        entry_keys = extract_heading_keys(entry)

        if not entry_keys:
            # No ## heading — plain prose (e.g. STORY section). Always include.
            new_entries.append(entry)
            continue

        # Check each key in this entry against what's already in the file.
        duplicate = entry_keys & existing_keys
        if duplicate:
            skipped_headings.extend(duplicate)
        else:
            new_entries.append(entry)

    if skipped_headings:
        print(f"    [dedup] Skipped existing entries: {skipped_headings}")

    if not new_entries:
        return

    combined = "\n\n".join(new_entries)
    separator = "\n\n---\n\n" if existing.strip() else ""
    updated = existing.rstrip() + separator + combined + "\n"

    file_path.write_text(updated, encoding="utf-8")


def write_batch_findings(
    novel_dir: Path,
    parsed_sections: dict[str, str],
    batch_nums: list[int],
) -> None:
    """
    Write all non-empty sections from a parsed batch response to bible files.

    Parameters
    ----------
    novel_dir : Path
        Root directory of the novel.
    parsed_sections : dict[str, str]
        Output of response_parser.parse_response().
    batch_nums : list[int]
        Chapter numbers in this batch (for logging only).
    """
    written = []
    skipped = []

    for key in SECTION_TO_FILE:
        content = parsed_sections.get(key, "")
        if content and content.strip():
            append_to_bible(novel_dir, key, content)
            written.append(key)
        else:
            skipped.append(key)

    chapters_str = ", ".join(str(n) for n in batch_nums)
    print(f"  ✓ Chapters {chapters_str} — wrote: {written or ['(nothing)']}")
    if skipped:
        print(f"    Skipped (nothing to add): {skipped}")
