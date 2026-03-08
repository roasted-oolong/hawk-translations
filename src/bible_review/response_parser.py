"""
src/bible_review/response_parser.py
-------------------------------------
Responsible for one thing: parsing the structured text response from the
bible review API call into its three components.

Returns:
  new_entries    : dict[str, str]  — bible section key → markdown to write immediately
  proposed_edits : list[dict]      — one dict per proposed edit block
  story_updates  : list[dict]      — one dict per story update block

This module has no knowledge of the API, file I/O, or prompt construction.
It receives a raw string and returns structured data. Nothing more.
"""

import re

# Top-level section headers the model is instructed to produce.
_SECTION_HEADERS = {
    "new_entries":    "=== NEW ENTRIES ===",
    "proposed_edits": "=== PROPOSED EDITS ===",
    "story_updates":  "=== STORY UPDATES ===",
}

# Maps the ### file-label headers inside NEW ENTRIES to canonical section keys.
_FILE_LABEL_TO_KEY = {
    "characters.md":       "characters",
    "characters":          "characters",
    "locations.md":        "locations",
    "locations":           "locations",
    "terminology.md":      "terminology",
    "terminology":         "terminology",
    "cultural_phrases.md": "cultural_phrases",
    "cultural_phrases":    "cultural_phrases",
    "cultural phrases.md": "cultural_phrases",
    "cultural phrases":    "cultural_phrases",
    "story.md":            "story",
    "story":               "story",
}


# ---------------------------------------------------------------------------
# Top-level section splitting
# ---------------------------------------------------------------------------

def _split_top_sections(raw: str) -> dict[str, str]:
    """Split the raw response on the three known top-level section headers."""
    results = {key: "" for key in _SECTION_HEADERS}
    header_pattern = "|".join(re.escape(h) for h in _SECTION_HEADERS.values())
    parts = re.split(f"({header_pattern})", raw)

    i = 1
    while i < len(parts) - 1:
        header = parts[i].strip()
        content = parts[i + 1].strip() if i + 1 < len(parts) else ""
        i += 2
        key = next((k for k, h in _SECTION_HEADERS.items() if h == header), None)
        if key is None:
            continue
        results[key] = "" if content.upper() == "NOTHING TO ADD" else content

    return results


# ---------------------------------------------------------------------------
# New entries parsing
# ---------------------------------------------------------------------------

def _parse_new_entries(raw: str) -> dict[str, str]:
    """
    Parse the NEW ENTRIES section into a dict keyed by bible section.

    Entries are grouped under ### file-label headers, e.g.:
        ### characters.md
        ## [Character Name]
        ...
    """
    if not raw.strip():
        return {}

    file_label_re = re.compile(
        r"###\s*([a-zA-Z_\s]+?(?:\.md)?)\s*$",
        re.MULTILINE | re.IGNORECASE,
    )

    parts = file_label_re.split(raw)
    # parts: [pre-text, label, content, label, content, ...]

    if len(parts) <= 1:
        print("  [warning] NEW ENTRIES section has no ### file-label headers. "
              "Cannot route entries to bible files.")
        return {}

    result: dict[str, list[str]] = {}
    i = 1
    while i < len(parts) - 1:
        label = parts[i].strip().lower()
        content = parts[i + 1].strip()
        i += 2

        key = _FILE_LABEL_TO_KEY.get(label)
        if key is None:
            print(f"  [warning] Unrecognised file label in NEW ENTRIES: '{label}'")
            continue
        if content and content.upper() != "NOTHING TO ADD":
            result.setdefault(key, []).append(content)

    return {key: "\n\n".join(blocks) for key, blocks in result.items()}


# ---------------------------------------------------------------------------
# Proposed edits parsing
# ---------------------------------------------------------------------------

def _parse_proposed_edits(raw: str) -> list[dict]:
    """
    Parse the PROPOSED EDITS section into a list of edit dicts.

    Each block has the shape:
      ENTRY: ...
      FILE: ...
      CURRENT: ...
      PROPOSED: ...
      REASON: ...
    """
    if not raw.strip():
        return []

    edits = []
    for block in re.split(r"\n{2,}", raw.strip()):
        if not block.strip():
            continue

        edit: dict[str, str] = {
            "entry": "", "file": "", "current": "", "proposed": "", "reason": ""
        }
        current_key: str | None = None
        current_lines: list[str] = []

        for line in block.splitlines():
            match = re.match(
                r"^(ENTRY|FILE|CURRENT|PROPOSED|REASON)\s*:\s*(.*)", line, re.IGNORECASE
            )
            if match:
                if current_key:
                    edit[current_key] = "\n".join(current_lines).strip()
                current_key = match.group(1).lower()
                current_lines = [match.group(2)]
            elif current_key:
                current_lines.append(line)

        if current_key:
            edit[current_key] = "\n".join(current_lines).strip()

        if edit["entry"]:
            edits.append(edit)

    return edits


# ---------------------------------------------------------------------------
# Story updates parsing
# ---------------------------------------------------------------------------

def _parse_story_updates(raw: str) -> list[dict]:
    """
    Parse the STORY UPDATES section into a list of update dicts.

    Each block has the shape:
      TYPE: ...
      UPDATE: ...
    """
    if not raw.strip():
        return []

    updates = []
    for block in re.split(r"\n{2,}", raw.strip()):
        if not block.strip():
            continue

        update: dict[str, str] = {"type": "", "update": ""}
        current_key: str | None = None
        current_lines: list[str] = []

        for line in block.splitlines():
            match = re.match(r"^(TYPE|UPDATE)\s*:\s*(.*)", line, re.IGNORECASE)
            if match:
                if current_key:
                    update[current_key] = "\n".join(current_lines).strip()
                current_key = match.group(1).lower()
                current_lines = [match.group(2)]
            elif current_key:
                current_lines.append(line)

        if current_key:
            update[current_key] = "\n".join(current_lines).strip()

        if update["type"] or update["update"]:
            updates.append(update)

    return updates


# ---------------------------------------------------------------------------
# Public entry point
# ---------------------------------------------------------------------------

def parse_response(raw: str) -> tuple[dict[str, str], list[dict], list[dict]]:
    """
    Parse the full bible review API response into its three components.

    Parameters
    ----------
    raw : str
        The full text response from the API.

    Returns
    -------
    tuple of:
        new_entries     : dict[str, str]  — section key → markdown to write immediately
        proposed_edits  : list[dict]      — one dict per proposed edit
        story_updates   : list[dict]      — one dict per story update
    """
    sections = _split_top_sections(raw)
    return (
        _parse_new_entries(sections["new_entries"]),
        _parse_proposed_edits(sections["proposed_edits"]),
        _parse_story_updates(sections["story_updates"]),
    )
