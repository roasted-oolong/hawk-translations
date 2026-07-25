"""
src/translator/chapter_loader.py
---------------------------------
Responsible for one thing: loading all material needed to translate a single
chapter and returning a (system_prompt, korean_text) pair ready for the API.

This module has no knowledge of the Anthropic API, batch mechanics, or
orchestration. It reads files and builds prompts. Nothing more.

Extracted here so both translate.py (single-chapter) and translate_batch.py
(multi-chapter) can share the same loading logic without coupling to each
other.
"""

import re
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path

from config import NOVEL_FILES
from src.novel_resolver import find_korean_file
from src.prompt_builder import TranslationContext, build_translation_prompt


# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------

def _read_file(path: Path) -> str:
    """Read a file and return its contents. Returns empty string if absent."""
    if not path.exists():
        print(f"  [warning] reference file not found: {path.name}")
        return ""
    return path.read_text(encoding="utf-8")


def _extract_narrator_note(novel_info: str) -> str:
    """
    Extract the ## Narrator Note section from novel_info.md content.
    Returns empty string if absent.
    """
    match = re.search(
        r"^## Narrator Note\s*\n(.*?)(?=^##|\Z)",
        novel_info,
        re.MULTILINE | re.DOTALL,
    )
    if not match:
        return ""
    return match.group(1).strip()


# ---------------------------------------------------------------------------
# Public interface
# ---------------------------------------------------------------------------

def load_reference_files(novel_dir: Path) -> dict[str, str]:
    """
    Load all translation reference files for a novel in parallel.

    Parameters
    ----------
    novel_dir : Path
        Root directory of the novel.

    Returns
    -------
    dict[str, str]
        Keys match TranslationContext field names. Values are file contents.
    """
    bible_dir = novel_dir / "bible"
    paths = {
        key: (novel_dir if location == "novel" else bible_dir) / filename
        for key, (filename, location) in NOVEL_FILES.items()
    }

    results: dict[str, str] = {}
    with ThreadPoolExecutor() as executor:
        futures = {executor.submit(_read_file, path): key for key, path in paths.items()}
        for future in as_completed(futures):
            results[futures[future]] = future.result()

    return results


def build_chapter_request(
    novel_dir: Path,
    chapter_num: int,
    reference_data: dict[str, str],
) -> tuple[str, str]:
    """
    Build the (system_prompt, korean_text) pair for a single chapter.

    Reference files are accepted as a parameter rather than loaded here
    so callers can load them once and reuse across many chapters.

    Parameters
    ----------
    novel_dir : Path
        Root directory of the novel.
    chapter_num : int
        The chapter number to prepare.
    reference_data : dict[str, str]
        Pre-loaded reference file contents keyed by TranslationContext field name.

    Returns
    -------
    tuple[str, str]
        (system_prompt, korean_text)

    Raises
    ------
    FileNotFoundError
        If no Korean source file exists for the given chapter number.
    """
    chapters_dir = novel_dir / "chapters"

    korean_path = find_korean_file(chapters_dir, chapter_num)
    if korean_path is None:
        raise FileNotFoundError(
            f"No Korean source file found for chapter {chapter_num} in {chapters_dir}"
        )

    korean_text = korean_path.read_text(encoding="utf-8")

    narrator_note = _extract_narrator_note(reference_data.get("novel_info", ""))
    context = TranslationContext(**reference_data, narrator_note=narrator_note)
    system_prompt = build_translation_prompt(context)

    return system_prompt, korean_text


def derive_output_path(novel_dir: Path, chapter_num: int) -> Path:
    """
    Return the output .txt path for a translated chapter.

    Format: chapters/Chapter {N}.txt
    """
    return novel_dir / "chapters" / f"Chapter {chapter_num}.txt"
