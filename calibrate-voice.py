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
  5. Parse new pattern candidates and retirement candidates
  6. Print a JSON object to stdout for the Rails pipeline to persist

All diagnostic output goes to stderr. Stdout contains only the final JSON.

Domain logic lives in src/voice_calibration/.
API logic lives in src/translation_backend.py (backend selected by
config.CALIBRATION_BACKEND; defaults to the Claude Code CLI backend,
src/claude_code_agent.py — see docs/DECISIONS.md, 2026-07-21).
Configuration lives in config.py.
This file does not make decisions about voice -- it connects the pieces.
"""

import json
import re
import sys
from pathlib import Path

from dotenv import load_dotenv

load_dotenv()

sys.path.insert(0, str(Path(__file__).parent))

from config import PROJECT_ROOT, CALIBRATION_BACKEND
from src.translation_backend import get_backend
from src.novel_resolver import resolve_novel
from src.voice_calibration.chapter_reader import (
    find_latest_translated_chapter,
    read_translated_chapter,
    read_voice_calibration,
)
from src.voice_calibration.prompt_builder import ReviewContext, build_system_prompt, build_user_message
from src.voice_calibration.response_parser import parse_response


# ---------------------------------------------------------------------------
# Chapter resolution
# ---------------------------------------------------------------------------

def _resolve_chapter(chapters_dir: Path, arg: str | None) -> int:
    if arg is not None:
        if not arg.isdigit():
            print(f"\n  [error] Chapter number must be an integer, got: '{arg}'", file=sys.stderr)
            sys.exit(1)
        return int(arg)

    latest = find_latest_translated_chapter(chapters_dir)
    if latest is None:
        print("\n  [error] No translated chapters found. Nothing to review.", file=sys.stderr)
        sys.exit(1)

    return latest


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
    """
    items = []
    blocks = re.split(r"(?=\*\*Retirement candidate)", raw)
    for block in blocks:
        block = block.strip()
        if not block:
            continue
        heading_match = re.search(
            r"\*\*Retirement candidate[^*]*?[—-]\s*(.+?)\*\*", block
        )
        reason_match = re.search(r"Reason:\s*(.+)", block)
        if heading_match and reason_match:
            items.append((heading_match.group(1).strip(), reason_match.group(1).strip()))
    return items


def _parse_pattern_entry(text: str) -> dict:
    """
    Parse a single ## Passage block into a structured dict matching
    the VoiceCalibrationPassage model fields.
    """
    heading_match = re.match(r"^##\s+(.+)", text)
    chapter_match = re.search(r"^\*(.+?)\*\s*$", text, re.MULTILINE)

    quote_lines = [line[2:] for line in text.split("\n") if line.startswith("> ")]
    quote = "\n".join(quote_lines).strip()

    demonstrates_match = re.search(
        r"\*\*What it demonstrates:\*\*\s*(.+?)(?=\*\*What the wrong|\Z)", text, re.DOTALL
    )
    wrong_match = re.search(
        r"\*\*What the wrong version looks like:\*\*\s*(.+?)(?=\*\*The rule|\Z)", text, re.DOTALL
    )
    rule_match = re.search(
        r"\*\*The rule it demonstrates:\*\*\s*(.+?)(?=---|\Z)", text, re.DOTALL
    )

    return {
        "heading":              heading_match.group(1).strip() if heading_match else "",
        "chapter_ref":          chapter_match.group(1).strip() if chapter_match else "",
        "quote":                quote,
        "what_it_demonstrates": demonstrates_match.group(1).strip() if demonstrates_match else "",
        "wrong_version":        wrong_match.group(1).strip() if wrong_match else "",
        "rule":                 rule_match.group(1).strip() if rule_match else "",
    }


# ---------------------------------------------------------------------------
# Main pipeline
# ---------------------------------------------------------------------------

def run() -> None:
    print("\n" + "=" * 60, file=sys.stderr)
    print("  HAWK TRANSLATIONS -- VOICE REVIEW", file=sys.stderr)
    print("=" * 60, file=sys.stderr)

    # -- Step 1: Resolve novel
    project_root = Path(PROJECT_ROOT)
    novel_name  = sys.argv[1] if len(sys.argv) > 1 else None
    chapter_arg = sys.argv[2] if len(sys.argv) > 2 else None

    novel_dir    = resolve_novel(project_root, novel_name)
    chapters_dir = novel_dir / "chapters"

    print(f"\n  Novel   : {novel_dir.name}", file=sys.stderr)

    # -- Step 2: Resolve chapter
    chapter_num = _resolve_chapter(chapters_dir, chapter_arg)
    print(f"  Chapter : {chapter_num}", file=sys.stderr)

    # -- Step 3: Load content
    print("\n  Loading files...", file=sys.stderr)
    try:
        translated = read_translated_chapter(chapters_dir, chapter_num)
    except FileNotFoundError as e:
        print(f"\n  [error] {e}", file=sys.stderr)
        sys.exit(1)

    voice_calibration = read_voice_calibration(novel_dir)
    print("  Done.", file=sys.stderr)

    # -- Step 4: Call review agent
    print("\n  Reviewing -- this will take a moment...", file=sys.stderr)
    backend       = get_backend(CALIBRATION_BACKEND)
    system_prompt = build_system_prompt()
    context       = ReviewContext(
        voice_calibration=voice_calibration,
        translated_chapter=translated,
        chapter_num=chapter_num,
    )
    user_message = build_user_message(context)

    raw_response = backend(
        system_prompt=system_prompt,
        user_message=user_message,
    )
    print("  Done.", file=sys.stderr)

    parsed = parse_response(raw_response)

    # -- Step 5: Build cards list
    cards = []

    new_patterns_raw = parsed.get("new_patterns", "")
    if new_patterns_raw:
        patterns = _split_patterns(new_patterns_raw)
        for i, pattern_text in enumerate(patterns):
            entry = _parse_pattern_entry(pattern_text)
            entry["id"]        = f"new_pattern_{i}"
            entry["card_type"] = "new_pattern"
            cards.append(entry)
        print(f"\n  {len(cards)} new pattern(s) found.", file=sys.stderr)
    else:
        print("\n  No new calibration patterns identified.", file=sys.stderr)

    retirements_raw = parsed.get("retirements", "")
    if retirements_raw:
        retirement_items = _split_retirements(retirements_raw)
        for i, (heading, reason) in enumerate(retirement_items):
            cards.append({
                "id":        f"retirement_{i}",
                "card_type": "retirement",
                "heading":   heading,
                "reason":    reason,
            })
        print(f"  {len(retirement_items)} retirement candidate(s) found.", file=sys.stderr)
    else:
        print("  No retirement candidates.", file=sys.stderr)

    # -- Step 6: Output JSON for Rails to store as result_payload
    print(json.dumps({"cards": cards}))


if __name__ == "__main__":
    run()
