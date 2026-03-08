"""
src/preread/response_parser.py
------------------------------
Responsible for one thing: parsing the structured text response from the
preread API call into a dict of section name → content string.

This module has no knowledge of the API, file I/O, or prompt construction.
It receives a raw string and returns a plain dict. Nothing more.

To change the expected output format (section headers), edit only this file.
"""

import re

# The five section headers the model is instructed to produce, in order.
# The key is the canonical section name used as a dict key downstream.
# The value is the exact header string the model produces.
SECTION_HEADERS = {
    "characters":       "=== CHARACTERS ===",
    "locations":        "=== LOCATIONS ===",
    "terminology":      "=== TERMINOLOGY ===",
    "cultural_phrases": "=== CULTURAL PHRASES ===",
    "story":            "=== STORY ===",
}


def parse_response(raw: str) -> dict[str, str]:
    """
    Parse a structured preread API response into a dict of section contents.

    Parameters
    ----------
    raw : str
        The full text response from the API.

    Returns
    -------
    dict[str, str]
        Keys: canonical section names (see SECTION_HEADERS).
        Values: content of that section (stripped), or empty string if the
                section was absent or contained only "NOTHING TO ADD".

    Notes
    -----
    - Sections not found in the response are returned as empty strings,
      with a warning printed to stdout.
    - "NOTHING TO ADD" content is normalized to an empty string.
    """
    results: dict[str, str] = {key: "" for key in SECTION_HEADERS}

    # Build a pattern that splits on any of our known headers.
    header_pattern = "|".join(re.escape(h) for h in SECTION_HEADERS.values())
    # We split on the headers themselves, keeping them as delimiters.
    parts = re.split(f"({header_pattern})", raw)

    # parts alternates: [pre-text, header, content, header, content, ...]
    # Walk through pairs of (header, content).
    i = 1
    while i < len(parts) - 1:
        header_text = parts[i].strip()
        content_text = parts[i + 1].strip() if i + 1 < len(parts) else ""
        i += 2

        # Find which canonical key this header maps to.
        matched_key = next(
            (key for key, h in SECTION_HEADERS.items() if h == header_text),
            None
        )
        if matched_key is None:
            continue

        # Normalize "nothing to add" to empty string.
        if content_text.upper().strip() == "NOTHING TO ADD":
            content_text = ""

        results[matched_key] = content_text

    # Warn about any sections the model failed to produce.
    for key, header in SECTION_HEADERS.items():
        if key not in results or results[key] == "":
            pass  # Silence is fine — empty means nothing to add.

    missing = [h for key, h in SECTION_HEADERS.items()
               if key not in results]
    if missing:
        print(f"  [warning] Response missing expected sections: {missing}")

    return results
