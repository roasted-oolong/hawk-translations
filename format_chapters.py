#!/usr/bin/env python3
"""
format_chapters.py
------------------
Entry point for the chapter formatting pipeline.

Reads Korean source files for the specified chapters, sends each batch to
Haiku with instructions to fix broken sentences and unnatural line breaks
without altering content, and overwrites the original source files with the
cleaned text.

Usage examples
--------------
  python format_chapters.py 5
  python format_chapters.py 5-10
  python format_chapters.py 5,7,9
  python format_chapters.py all

An optional novel name can be appended if multiple novels are present:
  python format_chapters.py 5-10 idols-rewind
"""

import math
import sys
from pathlib import Path

from dotenv import load_dotenv

load_dotenv()

sys.path.insert(0, str(Path(__file__).parent))

from config import PROJECT_ROOT, HAIKU_MODEL, FORMAT_MAX_TOKENS
from src.agent import call, make_client
from src.novel_resolver import resolve_novel, find_all_korean_chapters
from src.preread.chapter_resolver import parse_chapter_selection
from src.formatter.runner import run_formatter

DEFAULT_BATCH_SIZE = 5


# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------

def _parse_args() -> tuple[str | None, str | None]:
    """
    Return (chapter_selection, novel_name) from sys.argv.

    Positional arguments: [chapter_selection] [novel_name]
    Both are optional. If only one argument is given it is treated as the
    chapter selection unless it looks like a novel name (no digits, has hyphens
    or is purely alphabetic).
    """
    args = sys.argv[1:]
    if not args:
        return None, None
    if len(args) >= 2:
        return args[0], args[1]
    arg = args[0]
    if arg.isalpha() or (not any(ch.isdigit() for ch in arg) and "-" in arg):
        return None, arg
    return arg, None


# ---------------------------------------------------------------------------
# Chapter selection
# ---------------------------------------------------------------------------

def _prompt_chapters(available: list[int]) -> list[int]:
    """Interactively ask which chapters to format. Returns a resolved list."""
    lo, hi = available[0], available[-1]
    print(f"\n  Available chapters: {lo}–{hi} ({len(available)} total)")

    while True:
        raw = input(
            "\n  Which chapters to format? "
            "(e.g. 'all', '5', '5-10', '5,7,9')  "
        ).strip()
        if not raw:
            continue
        if raw.lower() in {"q", "quit", "cancel"}:
            print("\n  Cancelled.\n")
            sys.exit(0)
        try:
            selected = parse_chapter_selection(raw, available)
        except ValueError as e:
            print(f"\n  {e}")
            continue
        if not selected:
            print("  No valid chapters matched. Try again.")
            continue
        return selected


# ---------------------------------------------------------------------------
# Batch size
# ---------------------------------------------------------------------------

def _prompt_batch_size() -> int:
    """Ask the user for a batch size, defaulting to DEFAULT_BATCH_SIZE."""
    raw = input(
        f"\n  Chapters per batch? (default: {DEFAULT_BATCH_SIZE}, "
        "press Enter to accept)  "
    ).strip()
    if not raw:
        return DEFAULT_BATCH_SIZE
    if raw.isdigit() and int(raw) > 0:
        return int(raw)
    print(f"  Invalid input — using default ({DEFAULT_BATCH_SIZE}).")
    return DEFAULT_BATCH_SIZE


# ---------------------------------------------------------------------------
# Confirmation
# ---------------------------------------------------------------------------

def _prompt_confirm(novel_name: str, selected: list[int], batch_size: int) -> bool:
    total_batches = math.ceil(len(selected) / batch_size)
    ch_range = (
        f"{selected[0]}–{selected[-1]}" if len(selected) > 1 else str(selected[0])
    )
    print(f"""
  ── Plan ─────────────────────────────────────────────
  Novel        : {novel_name}
  Chapters     : {ch_range} ({len(selected)} chapter(s))
  Batch size   : {batch_size}
  Total batches: {total_batches}
  Output       : overwrites ch##_korean source files
  ─────────────────────────────────────────────────────""")

    while True:
        raw = input("\n  Go ahead? (yes / no)  ").strip().lower()
        if raw in {"yes", "y", ""}:
            return True
        if raw in {"no", "n", "q", "quit"}:
            return False
        print("  Please type 'yes' or 'no'.")


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

def main() -> None:
    print("\n" + "═" * 52)
    print("  HAWK TRANSLATIONS — FORMAT CHAPTERS")
    print("═" * 52)

    chapter_arg, novel_arg = _parse_args()

    project_root = Path(PROJECT_ROOT)
    novel_dir = resolve_novel(project_root, name=novel_arg)
    chapters_dir = novel_dir / "chapters"

    all_chapters = find_all_korean_chapters(chapters_dir)
    if not all_chapters:
        print("\n  No Korean source files found.\n")
        return

    if chapter_arg:
        try:
            selected = parse_chapter_selection(chapter_arg, all_chapters)
        except ValueError as e:
            print(f"\n  [error] {e}\n")
            sys.exit(1)
        if not selected:
            print("\n  No matching chapters found.\n")
            sys.exit(1)
    else:
        selected = _prompt_chapters(all_chapters)

    batch_size = _prompt_batch_size()

    if not _prompt_confirm(novel_dir.name, selected, batch_size):
        print("\n  Cancelled.\n")
        return

    client = make_client()

    def api_call(system_prompt: str, user_message: str) -> str:
        return call(
            system_prompt=system_prompt,
            user_message=user_message,
            model=HAIKU_MODEL,
            max_tokens=FORMAT_MAX_TOKENS,
            client=client,
        )

    run_formatter(
        novel_dir=novel_dir,
        chapter_nums=selected,
        batch_size=batch_size,
        api_call_fn=api_call,
    )


if __name__ == "__main__":
    main()
