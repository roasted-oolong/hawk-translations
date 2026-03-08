"""
src/preread/chapter_resolver.py
-------------------------------
Responsible for one thing: determining which chapters exist, which are
untranslated, and resolving a user-supplied selection string into a
sorted list of chapter numbers.

Accepts both strict input ("1-20", "all") and natural language
("chapters 1 through 20", "all of them", "just 13 and 15").

This module has no knowledge of the API, bible files, or prompts.
It reads the filesystem and applies selection logic. Nothing more.
"""

import re
from pathlib import Path


# ---------------------------------------------------------------------------
# Filename parsing
# ---------------------------------------------------------------------------

def extract_chapter_number(filename: str) -> int | None:
    """Return the first integer found in a filename, or None if absent."""
    match = re.search(r"(\d+)", filename)
    return int(match.group(1)) if match else None


# ---------------------------------------------------------------------------
# Chapter discovery
# ---------------------------------------------------------------------------

def find_all_korean_chapters(chapters_dir: Path) -> list[int]:
    """Return sorted list of all chapter numbers with a *_korean source file."""
    nums = []
    for f in chapters_dir.iterdir():
        if "korean" in f.name.lower() and f.is_file():
            n = extract_chapter_number(f.name)
            if n is not None:
                nums.append(n)
    return sorted(nums)


def find_translated_chapter_numbers(chapters_dir: Path) -> set[int]:
    """Return the set of chapter numbers that already have a translated .txt file."""
    translated = set()
    for f in chapters_dir.iterdir():
        if not f.is_file():
            continue
        if f.suffix.lower() != ".txt":
            continue
        if "korean" in f.name.lower():
            continue
        n = extract_chapter_number(f.name)
        if n is not None:
            translated.add(n)
    return translated


def find_untranslated_chapters(chapters_dir: Path) -> list[int]:
    """
    Return sorted list of chapter numbers that have a Korean source file
    but no corresponding translated .txt file.
    """
    all_korean = find_all_korean_chapters(chapters_dir)
    translated = find_translated_chapter_numbers(chapters_dir)
    return [n for n in all_korean if n not in translated]


# ---------------------------------------------------------------------------
# Natural language selection parsing
# ---------------------------------------------------------------------------

# Phrases that unambiguously mean "all available chapters"
_ALL_PHRASES = frozenset({
    "all", "all of them", "everything", "all chapters",
    "all of the chapters", "every chapter", "all untranslated",
    "all untranslated chapters", "the rest", "all the rest",
})

# Written-out numbers
_WORD_TO_NUM: dict[str, int] = {
    "one": 1, "two": 2, "three": 3, "four": 4, "five": 5,
    "six": 6, "seven": 7, "eight": 8, "nine": 9, "ten": 10,
    "eleven": 11, "twelve": 12, "thirteen": 13, "fourteen": 14,
    "fifteen": 15, "sixteen": 16, "seventeen": 17, "eighteen": 18,
    "nineteen": 19, "twenty": 20, "thirty": 30, "forty": 40,
    "fifty": 50, "sixty": 60, "seventy": 70, "eighty": 80,
    "ninety": 90, "hundred": 100,
}


def _normalize(text: str) -> str:
    """Lowercase, strip punctuation noise, collapse whitespace."""
    text = text.lower().strip()
    text = re.sub(r"[^\w\s\-,]", "", text)
    text = re.sub(r"\s+", " ", text)
    return text


def _replace_word_numbers(text: str) -> str:
    """
    Replace written-out numbers with digits.
    Handles compound tens+ones: "sixty nine" → "69".
    """
    tens = "twenty|thirty|forty|fifty|sixty|seventy|eighty|ninety"
    ones = "one|two|three|four|five|six|seven|eight|nine"

    def replace_compound(m: re.Match) -> str:
        return str(_WORD_TO_NUM[m.group(1)] + _WORD_TO_NUM[m.group(2)])

    text = re.sub(rf"\b({tens})\s+({ones})\b", replace_compound, text)

    for word, num in sorted(_WORD_TO_NUM.items(), key=lambda x: -len(x[0])):
        text = re.sub(rf"\b{word}\b", str(num), text)

    return text


def _filter_and_warn(requested: list[int], available_set: set[int]) -> list[int]:
    """Filter requested chapters to available ones, warn about any missing."""
    missing = [n for n in requested if n not in available_set]
    if missing:
        print(f"  [note] Skipping chapters not found or already translated: {missing}")
    return sorted(set(n for n in requested if n in available_set))


def parse_chapter_selection(raw: str, available: list[int]) -> list[int]:
    """
    Parse a natural-language or structured chapter selection into a sorted
    list of chapter numbers, filtered to those that actually exist.

    Accepted inputs (examples)
    --------------------------
    Structured : "all", "13", "13-20", "13,15,17"
    Natural    : "all of them", "chapters 1 through 20", "just 13 and 15",
                 "1 to 69", "everything from 5 to 10", "chapter 7"

    Parameters
    ----------
    raw : str
        Raw input string from the user.
    available : list[int]
        Chapter numbers that exist on disk and are untranslated.

    Returns
    -------
    list[int]
        Sorted, de-duplicated list of valid chapter numbers.

    Raises
    ------
    ValueError
        If the input cannot be parsed into any recognisable selection.
    """
    available_set = set(available)
    normalized = _normalize(raw)

    # Strip noise words to check against "all" phrases
    stripped = re.sub(r"\b(just|only|chapters?)\b", "", normalized).strip()
    if normalized in _ALL_PHRASES or stripped in _ALL_PHRASES:
        return sorted(available)

    # Replace written-out numbers before pattern matching
    text = _replace_word_numbers(normalized)

    # Range: "X through Y", "X to Y", "X - Y"
    range_match = re.search(r"(\d+)\s*(?:through|thru|to|-|–)\s*(\d+)", text)
    if range_match:
        lo, hi = int(range_match.group(1)), int(range_match.group(2))
        if lo > hi:
            raise ValueError(f"Invalid range: {lo} to {hi} (start must be ≤ end).")
        return _filter_and_warn(list(range(lo, hi + 1)), available_set)

    # Comma / "and" list: "13, 15 and 17" or just "13"
    list_text = re.sub(r"\band\b", ",", text)
    numbers = [int(m) for m in re.findall(r"\d+", list_text)]
    if numbers:
        return _filter_and_warn(numbers, available_set)

    raise ValueError(
        f"Could not parse '{raw}' as a chapter selection.\n"
        "  Try: 'all', a number, a range ('1 through 20'), "
        "or a list ('13, 15, and 17')."
    )
