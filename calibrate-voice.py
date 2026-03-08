"""
calibrate-voice.py
---------
Entry point for the voice review pipeline.

Run with:
    python calibrate-voice.py [novel-name] [chapter-number]

If no chapter number is provided, defaults to the most recently translated
chapter. If no novel name is provided, follows the same resolution logic
as translate.py and preread.py.

This script is responsible for orchestration only:
  1. Resolve the novel directory
  2. Identify the chapter to review
  3. Load the translated chapter and voice calibration document
  4. Call the review agent (Opus)
  5. For each new pattern candidate, confirm before writing to
     voice_calibration.md
  6. For each retirement candidate, confirm before removing from
     voice_calibration.md

Domain logic lives in src/voice_calibration/.
API logic lives in src/agent.py.
Configuration lives in config.py.
This file does not make decisions about voice -- it connects the pieces.
"""

import re
import sys
from pathlib import Path

from dotenv import load_dotenv

load_dotenv()

sys.path.insert(0, str(Path(__file__).parent))

from config import PROJECT_ROOT, OPUS_MODEL, MAX_TOKENS
from src.agent import call, make_client
from src.novel_resolver import resolve_novel
from src.voice_calibration.chapter_reader import (
    find_latest_translated_chapter,
    read_translated_chapter,
    read_voice_calibration,
)
from src.voice_calibration.prompt_builder import ReviewContext, build_system_prompt, build_user_message
from src.voice_calibration.response_parser import parse_response
from src.voice_calibration.calibration_writer import append_pattern, remove_passage
from src.voice_calibration.discussion import run_discussion


# ---------------------------------------------------------------------------
# Chapter resolution
# ---------------------------------------------------------------------------

def _resolve_chapter(chapters_dir: Path, arg: str | None) -> int:
    """
    Resolve the chapter number to review from an optional CLI argument.

    If no argument is provided, defaults to the most recently translated
    chapter. Exits with an error if no translated chapters exist.
    """
    if arg is not None:
        if not arg.isdigit():
            print(f"\n  [error] Chapter number must be an integer, got: '{arg}'")
            sys.exit(1)
        return int(arg)

    latest = find_latest_translated_chapter(chapters_dir)
    if latest is None:
        print("\n  [error] No translated chapters found. Nothing to review.")
        sys.exit(1)

    return latest


# ---------------------------------------------------------------------------
# Confirmation prompts
# ---------------------------------------------------------------------------

def _confirm_pattern(
    pattern: str,
    index: int,
    total: int,
    original_context: str,
    client,
) -> tuple[bool, str]:
    """
    Display a new pattern candidate and ask the user to confirm.

    Returns (accepted, final_content). If the user opens a discussion,
    the returned content may differ from the original pattern.
    """
    print("\n" + "-" * 60)
    print(f"  NEW PATTERN {index}/{total}")
    print("-" * 60)
    print()
    print(pattern)
    print()

    while True:
        raw = input("  Add to voice_calibration.md? [y / n / e to discuss]: ").strip().lower()
        if raw in {"y", "yes"}:
            return True, pattern
        if raw in {"n", "no"}:
            return False, pattern
        if raw in {"e", "edit", "discuss"}:
            result = run_discussion(
                item_label=f"New Pattern {index}/{total}",
                item_content=pattern,
                original_context=original_context,
                client=client,
            )
            return result.accepted, result.content or pattern
        print("  Please type 'y', 'n', or 'e'.")


def _confirm_retirement(
    heading: str,
    reason: str,
    index: int,
    total: int,
    original_context: str,
    client,
) -> bool:
    """
    Display a retirement candidate and ask the user to confirm removal.

    Returns True if confirmed, False if skipped.
    The user may open a discussion before deciding.
    """
    print("\n" + "-" * 60)
    print(f"  RETIREMENT CANDIDATE {index}/{total}")
    print("-" * 60)
    print(f"\n  Passage : {heading}")
    print(f"  Reason  : {reason}\n")

    while True:
        raw = input("  Remove from voice_calibration.md? [y / n / e to discuss]: ").strip().lower()
        if raw in {"y", "yes"}:
            return True
        if raw in {"n", "no"}:
            return False
        if raw in {"e", "edit", "discuss"}:
            result = run_discussion(
                item_label=f"Retirement {index}/{total}",
                item_content=f"Proposed retirement: {heading}\nReason: {reason}",
                original_context=original_context,
                client=client,
            )
            return result.accepted
        print("  Please type 'y', 'n', or 'e'.")


# ---------------------------------------------------------------------------
# Parsing helpers
# ---------------------------------------------------------------------------

def _split_patterns(raw: str) -> list[str]:
    """
    Split the new_patterns section into individual passage entries.

    Each entry begins with a ## heading. Content before the first ##
    heading (e.g. Opus preamble) is preserved as part of the first entry
    rather than being silently dropped.
    """
    parts = re.split(r"(?=^## )", raw, flags=re.MULTILINE)
    return [p.strip() for p in parts if p.strip()]


def _split_retirements(raw: str) -> list[tuple[str, str]]:
    """
    Parse the retirements section into a list of (heading, reason) tuples.

    Each retirement candidate begins with:
        **Retirement candidate -- [passage heading]**
    followed by a Reason: line.
    """
    items = []
    blocks = re.split(r"(?=\*\*Retirement candidate)", raw)
    for block in blocks:
        block = block.strip()
        if not block:
            continue
        heading_match = re.search(
            r"\*\*Retirement candidate[^*]*?[\u2014-]\s*(.+?)\*\*", block
        )
        reason_match = re.search(r"Reason:\s*(.+)", block)
        if heading_match and reason_match:
            items.append((heading_match.group(1).strip(), reason_match.group(1).strip()))
    return items


# ---------------------------------------------------------------------------
# Main pipeline
# ---------------------------------------------------------------------------

def run() -> None:
    """
    Execute the voice review pipeline for a translated chapter.

    Steps:
      1. Resolve the novel directory.
      2. Identify the chapter to review.
      3. Load the translated chapter and voice calibration document.
      4. Call the review agent.
      5. For each new pattern, confirm and write if approved.
      6. For each retirement candidate, confirm and remove if approved.
    """
    print("\n" + "=" * 60)
    print("  HAWK TRANSLATIONS -- VOICE REVIEW")
    print("=" * 60)

    # -- Step 1: Resolve novel -----------------------------------------
    project_root = Path(PROJECT_ROOT)
    novel_name = sys.argv[1] if len(sys.argv) > 1 else None
    chapter_arg = sys.argv[2] if len(sys.argv) > 2 else None

    novel_dir = resolve_novel(project_root, novel_name)
    chapters_dir = novel_dir / "chapters"

    print(f"\n  Novel   : {novel_dir.name}")

    # -- Step 2: Resolve chapter ---------------------------------------
    chapter_num = _resolve_chapter(chapters_dir, chapter_arg)
    print(f"  Chapter : {chapter_num}")

    # -- Step 3: Load content ------------------------------------------
    print("\n  Loading files...")
    try:
        translated = read_translated_chapter(chapters_dir, chapter_num)
    except FileNotFoundError as e:
        print(f"\n  [error] {e}")
        sys.exit(1)

    voice_calibration = read_voice_calibration(novel_dir)
    print("  Done.")

    # -- Step 4: Call review agent -------------------------------------
    print("\n  Reviewing -- this will take a moment...")
    client = make_client()
    system_prompt = build_system_prompt()
    context = ReviewContext(
        voice_calibration=voice_calibration,
        translated_chapter=translated,
        chapter_num=chapter_num,
    )
    user_message = build_user_message(context)

    raw_response = call(
        system_prompt=system_prompt,
        user_message=user_message,
        model=OPUS_MODEL,
        max_tokens=MAX_TOKENS,
        client=client,
    )
    print("  Done.")

    parsed = parse_response(raw_response)

    # -- Step 5: New pattern candidates --------------------------------
    new_patterns_raw = parsed.get("new_patterns", "")
    if not new_patterns_raw:
        print("\n  No new calibration patterns identified.")
    else:
        patterns = _split_patterns(new_patterns_raw)
        if not patterns:
            print("\n  No new calibration patterns identified.")
        else:
            print(f"\n  {len(patterns)} new pattern(s) identified for voice_calibration.md.")
            added = 0
            for i, pattern in enumerate(patterns, start=1):
                accepted, final_content = _confirm_pattern(
                    pattern, i, len(patterns), user_message, client
                )
                if accepted:
                    append_pattern(novel_dir, final_content)
                    added += 1
                else:
                    print("  Skipped.")
            print(f"\n  Done. {added}/{len(patterns)} pattern(s) added to voice_calibration.md.")

    # -- Step 6: Retirement candidates ---------------------------------
    retirements_raw = parsed.get("retirements", "")
    if not retirements_raw:
        print()
        return

    retirement_items = _split_retirements(retirements_raw)
    if not retirement_items:
        print()
        return

    print(f"\n  {len(retirement_items)} retirement candidate(s) identified.")
    removed = 0
    for i, (heading, reason) in enumerate(retirement_items, start=1):
        if _confirm_retirement(
            heading, reason, i, len(retirement_items), user_message, client
        ):
            if remove_passage(novel_dir, heading):
                removed += 1
        else:
            print("  Skipped.")

    print(f"\n  Done. {removed}/{len(retirement_items)} passage(s) removed from voice_calibration.md.\n")


if __name__ == "__main__":
    run()
