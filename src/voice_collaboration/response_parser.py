"""
src/voice_collaboration/response_parser.py
------------------------------
Responsible for one thing: parsing the structured text response from the
voice review API call into a dict of section name → content string.

This module has no knowledge of the API, file I/O, or prompt construction.
It receives a raw string and returns a plain dict. Nothing more.

To change the expected output format (section headers), edit only this file.
"""

import re

# The two section headers the model is instructed to produce.
# Key: canonical section name used downstream.
# Value: exact header string the model produces.
SECTION_HEADERS = {
    "new_patterns": "=== NEW PATTERNS ===",
    "retirements":  "=== RETIREMENTS ===",
}

_NOTHING = "NOTHING TO REPORT"


def parse_response(raw: str) -> dict[str, str]:
    """
    Parse a structured voice review API response into a dict of section contents.

    Parameters
    ----------
    raw : str
        The full text response from the API.

    Returns
    -------
    dict[str, str]
        Keys: "drift_findings", "new_patterns".
        Values: content of that section (stripped), or empty string if the
                section was absent or contained only "NOTHING TO REPORT".
    """
    results: dict[str, str] = {key: "" for key in SECTION_HEADERS}

    header_pattern = "|".join(re.escape(h) for h in SECTION_HEADERS.values())
    parts = re.split(f"({header_pattern})", raw)

    i = 1
    while i < len(parts) - 1:
        header_text = parts[i].strip()
        content_text = parts[i + 1].strip() if i + 1 < len(parts) else ""
        i += 2

        matched_key = next(
            (key for key, h in SECTION_HEADERS.items() if h == header_text),
            None,
        )
        if matched_key is None:
            continue

        if content_text.upper().strip() == _NOTHING:
            content_text = ""

        results[matched_key] = content_text

    missing = [h for key, h in SECTION_HEADERS.items() if key not in results]
    if missing:
        print(f"  [warning] Response missing expected sections: {missing}")

    return results
