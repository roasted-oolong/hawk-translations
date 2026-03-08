"""
src/preread/runner.py
---------------------
Responsible for one thing: orchestrating the preread batch loop.

This module composes all other preread modules together. It does not contain
domain logic, prompt text, file I/O details, or API logic directly — it
delegates each concern to the appropriate module and wires the results together.

To change batch behavior (retry logic, progress tracking, etc.), edit only
this file. Domain logic changes go in their respective modules.
"""

import time
from datetime import date
from pathlib import Path

from src.agent import ApiCallFn
from .bible_reader import read_novel_info, read_bible_files, read_chapter_file
from .prompt_builder import PrereadContext, build_system_prompt, build_user_message
from .response_parser import parse_response
from .bible_writer import write_batch_findings


def _make_batches(chapter_list: list[int], batch_size: int) -> list[list[int]]:
    """Split a list of chapter numbers into sequential batches."""
    return [chapter_list[i : i + batch_size] for i in range(0, len(chapter_list), batch_size)]


def run_preread(
    novel_dir: Path,
    chapter_nums: list[int],
    batch_size: int,
    resume_from: int | None,
    api_call_fn: ApiCallFn,
) -> None:
    """
    Execute the full preread operation: read chapters in batches, call the
    API, parse the response, and write findings to bible files after each batch.

    Parameters
    ----------
    novel_dir : Path
        Root directory of the novel.
    chapter_nums : list[int]
        Sorted list of chapter numbers to preread.
    batch_size : int
        Number of chapters per API call.
    resume_from : int | None
        If set, skip all chapters before this number (resume after crash).
    api_call_fn : ApiCallFn
        Callable with signature (system_prompt: str, user_message: str) -> str.
        Injected so this module has no direct dependency on agent.py.
    """
    today = date.today().isoformat()

    # Apply resume filter.
    if resume_from is not None:
        original_count = len(chapter_nums)
        chapter_nums = [n for n in chapter_nums if n >= resume_from]
        skipped = original_count - len(chapter_nums)
        if skipped:
            print(f"  Resuming from chapter {resume_from} — skipping {skipped} earlier chapters.")

    if not chapter_nums:
        print("  No chapters to process.")
        return

    batches = _make_batches(chapter_nums, batch_size)
    chapters_dir = novel_dir / "chapters"
    system_prompt = build_system_prompt(today)

    total_batches = len(batches)
    print(f"\n  Chapters selected : {chapter_nums[0]}–{chapter_nums[-1]} "
          f"({len(chapter_nums)} total)")
    print(f"  Batch size        : {batch_size}")
    print(f"  Total batches     : {total_batches}")
    print()

    for batch_index, batch_nums in enumerate(batches, start=1):
        print(f"── Batch {batch_index}/{total_batches}: chapters {batch_nums} ──")

        # Read bible state fresh before each batch so prior writes are reflected.
        bible = read_bible_files(novel_dir)
        novel_info = read_novel_info(novel_dir)

        # Read chapter files for this batch.
        chapters_content: dict[int, str] = {
            n: read_chapter_file(chapters_dir, n)
            for n in batch_nums
        }

        # Build context and messages.
        context = PrereadContext(
            novel_info=novel_info,
            characters=bible.get("bible/characters.md", ""),
            cultural_phrases=bible.get("bible/cultural_phrases.md", ""),
            locations=bible.get("bible/locations.md", ""),
            story=bible.get("bible/story.md", ""),
            terminology=bible.get("bible/terminology.md", ""),
            chapters=chapters_content,
            today=today,
        )
        user_message = build_user_message(context)

        # Call the API.
        print(f"  Pre-reading...")
        raw_response = api_call_fn(system_prompt, user_message)

        # Parse and write.
        parsed = parse_response(raw_response)
        write_batch_findings(novel_dir, parsed, batch_nums)

        # Brief pause between batches to be kind to the API.
        if batch_index < total_batches:
            time.sleep(1)

    print(f"\n  ✓ Preread complete. {len(chapter_nums)} chapters processed in "
          f"{total_batches} batches.")
