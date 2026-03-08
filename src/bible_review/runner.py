"""
src/bible_review/runner.py
----------------------------
Responsible for one thing: orchestrating the post-translation bible review.

Composes all bible_review modules together via dependency injection.
Contains no domain logic, prompt text, file I/O details, or API logic.

Flow:
  1. Read the translated chapter and current bible state.
  2. Call the API.
  3. Parse the response into new entries, proposed edits, and story updates.
  4. Write new entries immediately.
  5. Present proposed edits one at a time and apply confirmed ones.
  6. Present story updates one at a time and write confirmed ones.
  7. Print a summary.
"""

from pathlib import Path

from src.agent import ApiCallFn
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
    SECTION_TO_FILE,
)


# ---------------------------------------------------------------------------
# File key resolution
# ---------------------------------------------------------------------------

_FILE_LABEL_TO_KEY: dict[str, str] = {
    "characters":       "characters",
    "character":        "characters",
    "locations":        "locations",
    "location":         "locations",
    "terminology":      "terminology",
    "term":             "terminology",
    "cultural_phrases": "cultural_phrases",
    "cultural phrases": "cultural_phrases",
    "cultural phrase":  "cultural_phrases",
    "story":            "story",
}


def _resolve_section_key(raw_file: str) -> str | None:
    """Normalise a FILE field from a proposed edit to a canonical section key."""
    normalised = raw_file.strip().lower().removesuffix(".md").replace("_", " ")
    return _FILE_LABEL_TO_KEY.get(normalised)


# ---------------------------------------------------------------------------
# Display helpers
# ---------------------------------------------------------------------------

def _yn(prompt: str) -> bool:
    """Prompt for a yes/no answer. Returns True for yes."""
    while True:
        raw = input(f"{prompt} (y/n) ").strip().lower()
        if raw in {"y", "yes"}:
            return True
        if raw in {"n", "no"}:
            return False
        print("  Please type y or n.")


def _print_divider(label: str) -> None:
    print("\n" + "═" * 52)
    print(f"  {label}")
    print("═" * 52)


def _display_edit(index: int, total: int, edit: dict) -> None:
    print(f"\n── Proposed edit {index}/{total} ──────────────────────────")
    print(f"  Entry  : {edit['entry']}")
    print(f"  File   : {edit['file']}")
    print(f"  Reason : {edit['reason']}")
    print(f"\n  Current:\n    {edit['current']}")
    print(f"\n  Proposed:\n    {edit['proposed']}")
    print()


def _display_story_update(index: int, total: int, update: dict) -> None:
    print(f"\n── Story update {index}/{total} ──────────────────────────")
    print(f"  Type   : {update['type']}")
    print(f"  Update : {update['update']}")
    print()


# ---------------------------------------------------------------------------
# Main runner
# ---------------------------------------------------------------------------

def run_review(
    novel_dir: Path,
    chapter_num: int,
    today: str,
    api_call_fn: ApiCallFn,
) -> None:
    """
    Execute the full post-translation bible review for one chapter.

    Parameters
    ----------
    novel_dir : Path
        Root directory of the novel.
    chapter_num : int
        Chapter number to review.
    today : str
        ISO date string (YYYY-MM-DD).
    api_call_fn : ApiCallFn
        Injected API call function — callable(system: str, user: str) -> str.
    """
    chapters_dir = novel_dir / "chapters"

    # -- Read inputs ---------------------------------------------------
    print(f"\n  Loading chapter {chapter_num} and bible files...")
    try:
        translated_chapter = read_translated_chapter(chapters_dir, chapter_num)
    except FileNotFoundError as e:
        print(f"\n  [error] {e}")
        return

    bible = read_bible_files(novel_dir)
    novel_info = read_novel_info(novel_dir)

    # -- Build and send API call ---------------------------------------
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

    print("  Running review...")
    raw_response = api_call_fn(system_prompt, user_message)

    # -- Parse ---------------------------------------------------------
    new_entries, proposed_edits, story_updates = parse_response(raw_response)

    # ── Step 1: New entries (written immediately) ──────────────────────
    _print_divider("NEW ENTRIES")
    if new_entries:
        written = write_new_entries(novel_dir, new_entries)
        print(f"\n  ✓ Written immediately to: {written}")
    else:
        print("\n  Nothing new to add.")

    # ── Step 2: Proposed edits (one at a time) ─────────────────────────
    _print_divider("PROPOSED EDITS")

    edits_applied: list[str] = []
    edits_skipped: list[str] = []

    if not proposed_edits:
        print("\n  No proposed edits.")
    else:
        print(f"\n  {len(proposed_edits)} proposed edit(s) to review.")
        for i, edit in enumerate(proposed_edits, start=1):
            _display_edit(i, len(proposed_edits), edit)

            if not _yn("  Apply this edit?"):
                edits_skipped.append(edit["entry"])
                print("  Skipped.")
                continue

            section_key = _resolve_section_key(edit["file"])
            if section_key is None:
                print(f"  [warning] Could not resolve file key from '{edit['file']}'. Skipping.")
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

    # ── Step 3: Story updates (one at a time) ──────────────────────────
    _print_divider("STORY UPDATES")

    story_written: list[str] = []

    if not story_updates:
        print("\n  No story updates.")
    else:
        print(f"\n  {len(story_updates)} story update(s) to review.")
        for i, update in enumerate(story_updates, start=1):
            _display_story_update(i, len(story_updates), update)

            if not _yn("  Add this update?"):
                print("  Skipped.")
                continue

            update_type = update["type"].strip()
            update_text = update["update"].strip()
            append_new_entry(novel_dir, "story", f"**{update_type}** — {update_text}")
            story_written.append(update_type)

    # ── Summary ────────────────────────────────────────────────────────
    _print_divider("REVIEW COMPLETE")
    print(f"  New entries written : {list(new_entries.keys()) or ['none']}")
    print(f"  Edits applied       : {edits_applied or ['none']}")
    print(f"  Edits skipped       : {edits_skipped or ['none']}")
    print(f"  Story updates       : {story_written or ['none']}")
    print()
