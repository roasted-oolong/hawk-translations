#!/usr/bin/env python3
"""
preread.py
----------
Entry point for the PREREAD function of the Hawk Translations pipeline.

Run with no arguments:
    python preread.py

The script will guide you through novel selection, chapter selection,
batch size, and confirmation before running. Once confirmed, it runs
unattended to completion.
"""

import sys
from pathlib import Path

from dotenv import load_dotenv

load_dotenv()

sys.path.insert(0, str(Path(__file__).parent))

from config import PROJECT_ROOT, SONNET_MODEL, MAX_TOKENS
from src.agent import call
from src.preread.chapter_resolver import (
    find_untranslated_chapters,
    parse_chapter_selection,
)
from src.preread.runner import run_preread

DEFAULT_BATCH_SIZE = 7


# ---------------------------------------------------------------------------
# Novel resolution
# ---------------------------------------------------------------------------

def _list_novels(project_root: Path) -> list[Path]:
    return sorted(
        d for d in project_root.iterdir()
        if d.is_dir()
        and not d.name.startswith("_")
        and not d.name.startswith(".")
        and (d / "chapters").is_dir()
        and (d / "bible").is_dir()
    )


def _prompt_novel(project_root: Path) -> Path:
    """Ask the user which novel to work on. Returns the resolved novel dir."""
    novels = _list_novels(project_root)
    if not novels:
        print("\n  No novel directories found. Exiting.")
        sys.exit(1)

    if len(novels) == 1:
        print(f"  Novel: {novels[0].name}")
        return novels[0]

    print("\n  Available novels:")
    for i, n in enumerate(novels, 1):
        print(f"    {i}. {n.name}")

    while True:
        raw = input("\n  Which novel? ").strip()
        if not raw:
            continue

        # Accept a number
        if raw.isdigit():
            idx = int(raw) - 1
            if 0 <= idx < len(novels):
                return novels[idx]
            print("  Not a valid number. Try again.")
            continue

        # Accept a name (partial match)
        matches = [n for n in novels if raw.lower() in n.name.lower()]
        if len(matches) == 1:
            return matches[0]
        if len(matches) > 1:
            print(f"  '{raw}' matches more than one novel. Be more specific.")
            continue
        print(f"  No novel matching '{raw}'. Try again.")


# ---------------------------------------------------------------------------
# Chapter selection
# ---------------------------------------------------------------------------

def _prompt_chapters(untranslated: list[int]) -> list[int]:
    """Ask the user which chapters to preread. Returns a resolved list."""
    lo, hi = untranslated[0], untranslated[-1]
    print(f"\n  Untranslated chapters available: {lo}–{hi} ({len(untranslated)} total)")

    while True:
        raw = input(
            "\n  Which chapters? (e.g. 'all', '1 through 20', '13, 15, 17') "
        ).strip()
        if not raw:
            continue
        try:
            selected = parse_chapter_selection(raw, untranslated)
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
        "press Enter to accept) "
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
    """Show the plan and ask for confirmation. Returns True if confirmed."""
    import math
    total_batches = math.ceil(len(selected) / batch_size)
    ch_range = (
        f"{selected[0]}–{selected[-1]}"
        if len(selected) > 1
        else str(selected[0])
    )

    print(f"""
  ── Plan ──────────────────────────────────────────
  Novel        : {novel_name}
  Chapters     : {ch_range} ({len(selected)} chapters)
  Batch size   : {batch_size}
  Total batches: {total_batches}
  ──────────────────────────────────────────────────""")

    while True:
        raw = input("\n  Go ahead? (yes / no) ").strip().lower()
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
    print("  HAWK TRANSLATIONS — PREREAD")
    print("═" * 52)

    project_root = Path(PROJECT_ROOT)

    novel_dir = _prompt_novel(project_root)
    chapters_dir = novel_dir / "chapters"

    untranslated = find_untranslated_chapters(chapters_dir)
    if not untranslated:
        print("\n  No untranslated chapters found. Nothing to preread.\n")
        return

    selected = _prompt_chapters(untranslated)
    batch_size = _prompt_batch_size()

    if not _prompt_confirm(novel_dir.name, selected, batch_size):
        print("\n  Cancelled.\n")
        return

    def api_call(system_prompt: str, user_message: str) -> str:
        return call(
            system_prompt=system_prompt,
            user_message=user_message,
            model=SONNET_MODEL,
            max_tokens=MAX_TOKENS,
        )

    run_preread(
        novel_dir=novel_dir,
        chapter_nums=selected,
        batch_size=batch_size,
        resume_from=None,
        api_call_fn=api_call,
    )


if __name__ == "__main__":
    main()
