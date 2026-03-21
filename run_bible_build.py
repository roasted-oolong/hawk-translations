#!/usr/bin/env python3
"""
run_bible_build.py
------------------
Non-interactive entry point for the BIBLE BUILD pipeline function.
Invoked by the Rails PipelineDispatcher as a background job.

For interactive terminal use, continue using preread.py — it is untouched.

Bible build runs the preread function on already-translated chapters to
rebuild bible entries from existing content. Unlike run_preread.py, which
resolves only untranslated chapters, this script resolves against all
chapters that have a Korean source file (regardless of translation status).

Usage:
    python run_bible_build.py --novel-dir <path> [--chapters <selection>] [--batch-size <n>]

Arguments:
    --novel-dir     Absolute path to the novel directory
                    (e.g. /home/jenna/hawk-translations/idols-rewind)
    --chapters      Chapter selection: single int ("5"), hyphen range ("1-74"),
                    comma list ("1,3,5"), or "all" (default: "all")
    --batch-size    Chapters per API batch (default: 5)

Exit codes:
    0  — completed successfully
    1  — argument error or pipeline error
"""

import argparse
import sys
from pathlib import Path

from dotenv import load_dotenv

load_dotenv()

sys.path.insert(0, str(Path(__file__).parent))

from config import SONNET_MODEL, MAX_TOKENS
from src.agent import call, make_client
from src.novel_resolver import find_all_korean_chapters
from src.preread.chapter_resolver import parse_chapter_selection
from src.preread.runner import run_preread


# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------

def _parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Non-interactive BIBLE BUILD runner")
    parser.add_argument(
        "--novel-dir",
        required=True,
        help="Absolute path to the novel directory"
    )
    parser.add_argument(
        "--chapters",
        default="all",
        help="Chapter selection: '5', '1-74', '1,3,5', or 'all' (default: all)"
    )
    parser.add_argument(
        "--batch-size",
        type=int,
        default=5,
        help="Chapters per API batch (default: 5)"
    )
    return parser.parse_args()


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

def main() -> None:
    args = _parse_args()

    novel_dir = Path(args.novel_dir)
    if not novel_dir.is_dir():
        print(f"[error] Novel directory not found: {novel_dir}", file=sys.stderr)
        sys.exit(1)

    chapters_dir = novel_dir / "chapters"
    if not chapters_dir.is_dir():
        print(f"[error] chapters/ directory not found in: {novel_dir}", file=sys.stderr)
        sys.exit(1)

    # Bible build resolves against ALL chapters with a Korean source file,
    # not just untranslated ones. A rebuild runs on already-translated content.
    all_chapters = find_all_korean_chapters(chapters_dir)
    if not all_chapters:
        print("[info] No chapters found. Nothing to build.")
        sys.exit(0)

    try:
        selected = parse_chapter_selection(args.chapters, all_chapters)
    except ValueError as e:
        print(f"[error] Invalid chapter selection '{args.chapters}': {e}", file=sys.stderr)
        sys.exit(1)

    if not selected:
        print(
            f"[error] No matching chapters for selection: {args.chapters}",
            file=sys.stderr,
        )
        sys.exit(1)

    client = make_client()

    def api_call_fn(system_prompt: str, user_message: str) -> str:
        return call(
            system_prompt=system_prompt,
            user_message=user_message,
            model=SONNET_MODEL,
            max_tokens=MAX_TOKENS,
            client=client,
        )

    run_preread(
        novel_dir=novel_dir,
        chapter_nums=selected,
        batch_size=args.batch_size,
        resume_from=None,
        api_call_fn=api_call_fn,
    )


if __name__ == "__main__":
    main()
