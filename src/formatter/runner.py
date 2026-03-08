"""
src/formatter/runner.py
------------------------
Responsible for one thing: orchestrating the formatting loop across batches
of chapter numbers.

This module composes chapter_io, prompt_builder, response_parser, and the
injected API call function. It contains no domain logic, prompt text, or
file I/O details — it delegates each concern to the appropriate module.

Batching: multiple chapters are grouped into a single API call. Each batch
produces one response that is parsed back into individual chapter texts, then
each chapter is written (overwriting the original source file).

To change loop behavior (error handling, progress reporting, etc.),
edit only this file.
"""

import time
from pathlib import Path

from src.agent import ApiCallFn
from .chapter_io import read_korean_chapter, overwrite_chapter_file
from .prompt_builder import build_system_prompt, build_user_message
from .response_parser import parse_response


def _make_batches(chapter_list: list[int], batch_size: int) -> list[list[int]]:
    """Split a list of chapter numbers into sequential batches."""
    return [chapter_list[i : i + batch_size] for i in range(0, len(chapter_list), batch_size)]


def run_formatter(
    novel_dir: Path,
    chapter_nums: list[int],
    batch_size: int,
    api_call_fn: ApiCallFn,
) -> None:
    """
    Format each chapter in chapter_nums and overwrite its source file.

    Chapters are grouped into batches and sent to the API together. The
    response is parsed back into individual chapter texts before writing.

    Parameters
    ----------
    novel_dir : Path
        Root directory of the novel.
    chapter_nums : list[int]
        Sorted list of chapter numbers to format.
    batch_size : int
        Number of chapters per API call.
    api_call_fn : ApiCallFn
        Callable with signature (system_prompt: str, user_message: str) -> str.
        Injected so this module has no direct dependency on agent.py.
    """
    chapters_dir = novel_dir / "chapters"
    system_prompt = build_system_prompt()
    batches = _make_batches(chapter_nums, batch_size)
    total_batches = len(batches)

    print(f"\n  Chapters to format : {chapter_nums[0]}–{chapter_nums[-1]} "
          f"({len(chapter_nums)} total)")
    print(f"  Batch size         : {batch_size}")
    print(f"  Total batches      : {total_batches}\n")

    written = 0
    skipped = 0

    for batch_index, batch_nums in enumerate(batches, start=1):
        print(f"── Batch {batch_index}/{total_batches}: chapters {batch_nums} ──")

        # Read all chapters in this batch.
        chapters_content: dict[int, str] = {}
        for num in batch_nums:
            try:
                chapters_content[num] = read_korean_chapter(chapters_dir, num)
            except FileNotFoundError as e:
                print(f"  [error] {e} — skipping chapter {num}.")
                skipped += 1

        if not chapters_content:
            print("  No readable chapters in this batch — skipping.")
            continue

        # Format via API.
        print(f"  Formatting {len(chapters_content)} chapter(s)...")
        user_message = build_user_message(chapters_content)
        raw_response = api_call_fn(system_prompt, user_message)

        # Parse response and write each chapter.
        parsed = parse_response(raw_response, list(chapters_content.keys()))
        for num, formatted_text in parsed.items():
            path = overwrite_chapter_file(chapters_dir, num, formatted_text)
            print(f"  ✓ Chapter {num} — overwritten {path.name}")
            written += 1

        # Brief pause between batches.
        if batch_index < total_batches:
            time.sleep(0.5)

    print(f"\n  ✓ Formatting complete. "
          f"{written} chapter(s) written, {skipped} skipped.")
