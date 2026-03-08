"""
src/formatter/response_parser.py
---------------------------------
Responsible for one thing: parsing the batched formatting response from the
API into a dict of chapter number → formatted text.

This module has no knowledge of the API, file I/O, or prompt construction.
It receives a raw string and returns a plain dict. Nothing more.

Expected input format (produced by prompt_builder.py instructions):

    === CHAPTER N ===
    [formatted text]
    === END CHAPTER N ===

Chapters missing from the response are reported as warnings so the caller
can decide how to handle them.
"""

import re


def parse_response(raw: str, expected_chapters: list[int]) -> dict[int, str]:
    """
    Parse a batched formatting API response into per-chapter formatted text.

    Parameters
    ----------
    raw : str
        The full text response from the API.
    expected_chapters : list[int]
        Chapter numbers that were sent in the request, used to warn on missing.

    Returns
    -------
    dict[int, str]
        Keys: chapter numbers. Values: formatted chapter text (stripped).
        Chapters absent from the response are not included in the dict.
    """
    results: dict[int, str] = {}

    # Match === CHAPTER N === ... === END CHAPTER N === blocks.
    pattern = re.compile(
        r"=== CHAPTER (\d+) ===\s*(.*?)\s*=== END CHAPTER \1 ===",
        re.DOTALL,
    )

    for match in pattern.finditer(raw):
        chapter_num = int(match.group(1))
        content = match.group(2).strip()
        results[chapter_num] = content

    # Warn about any chapters the model failed to return.
    missing = [n for n in expected_chapters if n not in results]
    if missing:
        print(f"  [warning] Response missing formatted output for chapters: {missing}")

    return results
