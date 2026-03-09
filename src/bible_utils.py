"""
src/bible_utils.py
------------------
Shared utilities for bible file parsing and deduplication.

The Korean name/term is the canonical unique identifier for every bible entry.
This module provides the single source of truth for heading key extraction,
used by all modules that read or write bible files.
"""

import re


def heading_key(raw_heading: str) -> str:
    """
    Derive a canonical deduplication key from a raw ## heading string
    (everything after the leading "## ").

    Key selection priority:
    1. If the heading contains a parenthetical with Korean characters,
       use the Korean string as the key (lowercased, stripped).
       This makes the Korean name the single source of truth regardless
       of how the English romanisation is spelled.
    2. Otherwise, normalise the English text:
       - Strip everything after " — " (drops "— English" label suffixes)
       - Drop any remaining parentheticals
       - Lowercase and strip whitespace

    Examples
    --------
    "Hee-yeon Lee (이희연) — English"  → "이희연"
    "LOAN (로안) — English"            → "로안"
    "Ro-an (로안) — English"           → "로안"   ← same key as above
    "SM Entertainment — English"       → "sm entertainment"
    "Debut — English"                  → "debut"
    """
    korean_match = re.search(
        r"\(([^)]*[\uAC00-\uD7A3\u1100-\u11FF\u3130-\u318F][^)]*)\)",
        raw_heading
    )
    if korean_match:
        return korean_match.group(1).strip().lower()

    text = raw_heading
    text = re.split(r"\s+[—–-]\s+", text)[0]
    text = re.sub(r"\(.*?\)", "", text)
    return text.strip().lower()


def extract_heading_keys(text: str) -> set[str]:
    """
    Return the set of canonical deduplication keys for all ## headings
    found in a markdown string.

    Parameters
    ----------
    text : str
        Full contents of a bible file or a single entry block.

    Returns
    -------
    set[str]
        One key per ## heading found, derived via heading_key().
    """
    keys = set()
    for match in re.finditer(r"^##\s+(.+)$", text, re.MULTILINE):
        keys.add(heading_key(match.group(1)))
    return keys


def extract_headings_with_keys(text: str) -> list[tuple[str, str]]:
    """
    Return a list of (raw_heading, key) pairs for all ## headings found
    in a markdown string. Used for diagnostic/audit purposes.

    Parameters
    ----------
    text : str
        Full contents of a bible file.

    Returns
    -------
    list[tuple[str, str]]
        Each item is (raw heading text, canonical key).
    """
    results = []
    for match in re.finditer(r"^##\s+(.+)$", text, re.MULTILINE):
        raw = match.group(1)
        results.append((raw, heading_key(raw)))
    return results
