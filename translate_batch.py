#!/usr/bin/env python3
"""
translate_batch.py
------------------
Entry point for batch translation of multiple chapters via the Anthropic
Batch API.

Each chapter is submitted as an independent request in a single batch job.
Reference files are loaded once and reused across all chapters. Results are
written to disk as they are retrieved.

This script does not replace translate.py — it is an alternative for when
you want to translate multiple chapters at once and do not need to review
each one interactively before writing.

Usage examples
--------------
  python translate_batch.py 2
  python translate_batch.py 2-10
  python translate_batch.py 2,4,6
  python translate_batch.py all

An optional novel name can be appended:
  python translate_batch.py 2-10 idols-rewind
"""

import sys
from pathlib import Path

from dotenv import load_dotenv

load_dotenv()

sys.path.insert(0, str(Path(__file__).parent))

from config import PROJECT_ROOT, OPUS_MODEL, MAX_TOKENS
from src.agent import make_client
from src.novel_resolver import resolve_novel, find_untranslated_chapters
from src.preread.chapter_resolver import parse_chapter_selection
from src.translator.chapter_loader import (
    load_reference_files,
    build_chapter_request,
    derive_output_path,
)
from src.translator.batch_runner import run_translation_batch


# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------

def _parse_args() -> tuple[str | None, str | None]:
    """
    Return (chapter_selection, novel_name) from sys.argv.

    If only one argument is given, treat it as a chapter selection unless
    it looks like a novel name (no digits, purely alpha or hyphenated).
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
    """Interactively ask which untranslated chapters to include."""
    lo, hi = available[0], available[-1]
    print(f"\n  Untranslated chapters: {lo}–{hi} ({len(available)} available)")

    while True:
        raw = input(
            "\n  Which chapters to translate? "
            "(e.g. 'all', '2', '2-10', '2,4,6')  "
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
# Confirmation
# ---------------------------------------------------------------------------

def _prompt_confirm(novel_name: str, selected: list[int]) -> bool:
    ch_range = (
        f"{selected[0]}–{selected[-1]}" if len(selected) > 1 else str(selected[0])
    )
    print(f"""
  ── Plan ──────────────────────────────────────────────────
  Novel    : {novel_name}
  Chapters : {ch_range} ({len(selected)} chapter(s))
  Model    : Opus
  Method   : Local LLM (sequential)
  Output   : chapters/Chapter_N.txt per chapter
  ──────────────────────────────────────────────────────────""")

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
    print("\n" + "═" * 58)
    print("  HAWK TRANSLATIONS — BATCH TRANSLATE")
    print("═" * 58)

    chapter_arg, novel_arg = _parse_args()

    project_root = Path(PROJECT_ROOT)
    novel_dir = resolve_novel(project_root, name=novel_arg)
    chapters_dir = novel_dir / "chapters"

    # ── Chapter selection ─────────────────────────────────────────────────
    available = find_untranslated_chapters(chapters_dir)
    if not available:
        print("\n  No untranslated chapters found. All done.\n")
        return

    if chapter_arg:
        try:
            selected = parse_chapter_selection(chapter_arg, available)
        except ValueError as e:
            print(f"\n  [error] {e}\n")
            sys.exit(1)
        if not selected:
            print("\n  No matching untranslated chapters found.\n")
            sys.exit(1)
    else:
        selected = _prompt_chapters(available)

    if not _prompt_confirm(novel_dir.name, selected):
        print("\n  Cancelled.\n")
        return

    # ── Load reference files once ──────────────────────────────────────────
    print("\n  Loading reference files...")
    reference_data = load_reference_files(novel_dir)
    print("  ✓ Reference files loaded.")

    # ── Build one request per chapter ─────────────────────────────────────
    print("\n  Building chapter requests...")
    requests = []
    skipped = []

    for num in selected:
        try:
            system_prompt, korean_text = build_chapter_request(
                novel_dir, num, reference_data
            )
        except FileNotFoundError as e:
            print(f"  [error] {e} — skipping chapter {num}.")
            skipped.append(num)
            continue

        requests.append({
            "custom_id": f"chapter-{num}",
            "params": {
                "model": OPUS_MODEL,
                "max_tokens": MAX_TOKENS,
                "system": system_prompt,
                "messages": [{"role": "user", "content": korean_text}],
            },
        })

    if skipped:
        print(f"  Skipped (missing source files): {skipped}")

    if not requests:
        print("\n  Nothing to submit.\n")
        return

    # ── Result handler: write each chapter as it arrives ──────────────────
    written: list[int] = []

    def on_result(custom_id: str, response_text: str) -> None:
        chapter_num = int(custom_id.removeprefix("chapter-"))
        output_path = derive_output_path(novel_dir, chapter_num)
        output_path.write_text(response_text, encoding="utf-8")
        print(f"  ✓ Chapter {chapter_num} — written to {output_path.name}")
        written.append(chapter_num)

    # ── Submit and retrieve ────────────────────────────────────────────────
    client = make_client()
    run_translation_batch(
        requests=requests,
        client=client,
        on_result=on_result,
    )

    # ── Summary ───────────────────────────────────────────────────────────
    print(f"\n  ✓ Done. {len(written)} chapter(s) translated.", end="")
    if skipped:
        print(f" {len(skipped)} skipped: {skipped}.", end="")
    print()


if __name__ == "__main__":
    main()
