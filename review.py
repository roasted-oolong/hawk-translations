#!/usr/bin/env python3
"""
review.py
---------
Entry point for the POST-TRANSLATION BIBLE REVIEW function.

Usage:
    python review.py              # reviews the highest-numbered translated chapter
    python review.py 5            # reviews chapter 5 by number
    python review.py [novel-name] # specify novel when multiple exist

Domain logic lives in src/bible_review/.
API logic lives in src/agent.py.
Configuration lives in config.py.
This file does not make decisions about the bible — it connects the pieces.
"""

import sys
from datetime import date
from pathlib import Path

from dotenv import load_dotenv

load_dotenv()

sys.path.insert(0, str(Path(__file__).parent))

from config import PROJECT_ROOT, SONNET_MODEL, MAX_TOKENS
from src.agent import call, make_client
from src.novel_resolver import resolve_novel
from src.bible_review.bible_reader import find_latest_translated_chapter
from src.bible_review.runner import run_review


# ---------------------------------------------------------------------------
# Chapter resolution
# ---------------------------------------------------------------------------

def _resolve_chapter(chapters_dir: Path, arg: str | None) -> int:
    """
    Resolve the chapter number to review from an optional CLI argument.

    If no argument is given, defaults to the highest-numbered translated chapter.
    Exits with an error if the argument is not a valid integer or no translated
    chapters exist.
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
# Entry point
# ---------------------------------------------------------------------------

def main() -> None:
    print("\n" + "═" * 52)
    print("  HAWK TRANSLATIONS — BIBLE REVIEW")
    print("═" * 52)

    project_root = Path(PROJECT_ROOT)

    # Allow an optional novel name as argv[1] if it is not a digit.
    novel_arg = sys.argv[1] if len(sys.argv) > 1 and not sys.argv[1].isdigit() else None
    chapter_arg = next((a for a in sys.argv[1:] if a.isdigit()), None)

    novel_dir = resolve_novel(project_root, novel_arg)
    chapters_dir = novel_dir / "chapters"

    chapter_num = _resolve_chapter(chapters_dir, chapter_arg)

    print(f"\n  Novel   : {novel_dir.name}")
    print(f"  Chapter : {chapter_num}")

    today = date.today().isoformat()
    client = make_client()

    def api_call_fn(system_prompt: str, user_message: str) -> str:
        return call(
            system_prompt=system_prompt,
            user_message=user_message,
            model=SONNET_MODEL,
            max_tokens=MAX_TOKENS,
            client=client,
        )

    run_review(
        novel_dir=novel_dir,
        chapter_num=chapter_num,
        today=today,
        api_call_fn=api_call_fn,
    )


if __name__ == "__main__":
    main()
