#!/usr/bin/env python3
"""
run_review.py
-------------
Non-interactive entry point for the POST-TRANSLATION BIBLE REVIEW pipeline function.
Invoked by the Rails PipelineDispatcher as a background job.

For interactive terminal use, continue using review.py — it is untouched.

Interactive review.py presents proposed edits and story updates one at a time
and requires human confirmation before writing. This wrapper runs headlessly:
new entries are written immediately (same as the interactive flow), and proposed
edits and story updates are also applied automatically without prompting.

This is appropriate for a background job context — the user triggered the job
from the UI and is not present to confirm individual edits. All changes made
are reported in stdout so the result_payload in the Rails UI shows what happened.

Usage:
    python run_review.py --novel-dir <path> --chapter <n>

Arguments:
    --novel-dir     Absolute path to the novel directory
                    (e.g. /home/jenna/hawk-translations/idols-rewind)
    --chapter       Chapter number to review (integer)

Exit codes:
    0  — completed successfully
    1  — argument error or pipeline error
"""

import argparse
import sys
from datetime import date
from pathlib import Path

from dotenv import load_dotenv

load_dotenv()

sys.path.insert(0, str(Path(__file__).parent))

from config import REVIEW_BACKEND
from src.translation_backend import get_backend
from src.bible_review.bible_reader import (
    read_novel_info,
    read_bible_files,
    read_translated_chapter,
)
from src.bible_review.prompt_builder import ReviewContext, build_system_prompt, build_user_message
from src.bible_review.response_parser import parse_response
from src.bible_review.bible_writer import (
    write_new_entries,
    apply_edit,
    append_new_entry,
)
from src.bible_review.runner import _resolve_section_key
from src.progress import report_progress


# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------

def _parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Non-interactive POST-TRANSLATION REVIEW runner")
    parser.add_argument(
        "--novel-dir",
        required=True,
        help="Absolute path to the novel directory"
    )
    parser.add_argument(
        "--chapter",
        required=True,
        type=int,
        help="Chapter number to review"
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
    chapter_num = args.chapter
    today = date.today().isoformat()

    # -- Read inputs ---------------------------------------------------
    print(f"Loading chapter {chapter_num} and bible files...")
    try:
        translated_chapter = read_translated_chapter(chapters_dir, chapter_num)
    except FileNotFoundError as e:
        print(f"[error] {e}", file=sys.stderr)
        sys.exit(1)

    bible = read_bible_files(novel_dir)
    novel_info = read_novel_info(novel_dir)

    # -- Build prompt and call API -------------------------------------
    context = ReviewContext(
        novel_info=novel_info,
        characters=bible.get("bible/characters.md", ""),
        cultural_phrases=bible.get("bible/cultural_phrases.md", ""),
        locations=bible.get("bible/locations.md", ""),
        story=bible.get("bible/story.md", ""),
        terminology=bible.get("bible/terminology.md", ""),
        translated_chapter=translated_chapter,
        chapter_num=chapter_num,
        today=today,
    )

    system_prompt = build_system_prompt(today, chapter_num)
    user_message = build_user_message(context)

    backend = get_backend(REVIEW_BACKEND)

    def api_call_fn(system_prompt: str, user_message: str) -> str:
        return backend(system_prompt=system_prompt, user_message=user_message)

    report_progress(50)
    print("Running review API call...")
    raw_response = api_call_fn(system_prompt, user_message)
    report_progress(100)

    # -- Parse response ------------------------------------------------
    new_entries, proposed_edits, story_updates = parse_response(raw_response)

    # -- Write new entries (same as interactive flow) ------------------
    print("\n── New entries ──")
    if new_entries:
        written = write_new_entries(novel_dir, new_entries)
        print(f"Written to: {written}")
    else:
        print("None.")

    # -- Apply proposed edits (auto-apply — no human prompt) -----------
    print("\n── Proposed edits ──")
    edits_applied: list[str] = []
    edits_skipped: list[str] = []

    if not proposed_edits:
        print("None.")
    else:
        print(f"{len(proposed_edits)} proposed edit(s) — applying automatically.")
        for edit in proposed_edits:
            section_key = _resolve_section_key(edit["file"])
            if section_key is None:
                print(f"  [warning] Could not resolve file key from '{edit['file']}' — skipping.")
                edits_skipped.append(edit["entry"])
                continue

            success = apply_edit(
                novel_dir=novel_dir,
                section_key=section_key,
                entry_heading=edit["entry"],
                field_current=edit["current"],
                field_proposed=edit["proposed"],
            )
            (edits_applied if success else edits_skipped).append(edit["entry"])

    # -- Apply story updates (auto-apply — no human prompt) ------------
    print("\n── Story updates ──")
    story_written: list[str] = []

    if not story_updates:
        print("None.")
    else:
        print(f"{len(story_updates)} story update(s) — applying automatically.")
        for update in story_updates:
            update_type = update["type"].strip()
            update_text = update["update"].strip()
            append_new_entry(novel_dir, "story", f"**{update_type}** — {update_text}")
            story_written.append(update_type)
            print(f"  + story: {update_type}")

    # -- Summary -------------------------------------------------------
    print("\n── Review complete ──")
    print(f"New entries written : {list(new_entries.keys()) or ['none']}")
    print(f"Edits applied       : {edits_applied or ['none']}")
    print(f"Edits skipped       : {edits_skipped or ['none']}")
    print(f"Story updates       : {story_written or ['none']}")


if __name__ == "__main__":
    main()
