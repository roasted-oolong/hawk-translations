"""
src/formatter/runner.py
------------------------
Responsible for one thing: orchestrating chapter formatting via the Anthropic
Batch API.

Each chapter is submitted as an independent request in a single batch job.
The batch is polled until complete, then results are parsed and written.

This replaces the previous synchronous loop. The prompt format, file I/O,
and response parsing are unchanged — only the API interaction pattern differs.

To change polling behavior or error handling, edit only this file.
"""

import time
from pathlib import Path

import anthropic

from config import HAIKU_MODEL, FORMAT_MAX_TOKENS
from .chapter_io import read_korean_chapter, overwrite_chapter_file
from .prompt_builder import build_system_prompt, build_user_message
from .response_parser import parse_response


# How long to wait between polling the batch for completion (seconds).
_POLL_INTERVAL = 30


def run_formatter(
    novel_dir: Path,
    chapter_nums: list[int],
    client: anthropic.Anthropic,
) -> None:
    """
    Format each chapter in chapter_nums using the Anthropic Batch API.

    Each chapter is submitted as a separate request within a single batch job.
    Results are retrieved once the batch completes and written back to source files.

    Parameters
    ----------
    novel_dir : Path
        Root directory of the novel.
    chapter_nums : list[int]
        Sorted list of chapter numbers to format.
    client : anthropic.Anthropic
        Pre-built Anthropic client.
    """
    chapters_dir = novel_dir / "chapters"
    system_prompt = build_system_prompt()

    # ── Read all chapters ────────────────────────────────────────────────────
    chapters_content: dict[int, str] = {}
    skipped: list[int] = []

    for num in chapter_nums:
        try:
            chapters_content[num] = read_korean_chapter(chapters_dir, num)
        except FileNotFoundError as e:
            print(f"  [error] {e} — skipping chapter {num}.")
            skipped.append(num)

    if not chapters_content:
        print("  No readable chapters found — aborting.")
        return

    # ── Build batch requests (one per chapter) ───────────────────────────────
    requests = []
    for num in sorted(chapters_content.keys()):
        user_message = build_user_message({num: chapters_content[num]})
        requests.append({
            "custom_id": f"chapter-{num}",
            "params": {
                "model": HAIKU_MODEL,
                "max_tokens": FORMAT_MAX_TOKENS,
                "system": system_prompt,
                "messages": [{"role": "user", "content": user_message}],
            },
        })

    print(f"\n  Submitting {len(requests)} chapter(s) to Batch API...")

    # ── Submit batch ─────────────────────────────────────────────────────────
    batch = client.messages.batches.create(requests=requests)
    batch_id = batch.id
    print(f"  Batch ID : {batch_id}")
    print(f"  Status   : {batch.processing_status}")

    # ── Poll until complete ──────────────────────────────────────────────────
    print(f"\n  Waiting for batch to complete (polling every {_POLL_INTERVAL}s)...")
    while True:
        time.sleep(_POLL_INTERVAL)
        batch = client.messages.batches.retrieve(batch_id)
        counts = batch.request_counts
        print(
            f"  [{batch.processing_status}] "
            f"processing: {counts.processing}  "
            f"succeeded: {counts.succeeded}  "
            f"errored: {counts.errored}"
        )
        if batch.processing_status == "ended":
            break

    # ── Retrieve and write results ───────────────────────────────────────────
    print("\n  Retrieving results...")
    written = 0
    errors: list[str] = []

    for result in client.messages.batches.results(batch_id):
        custom_id = result.custom_id
        chapter_num = int(custom_id.removeprefix("chapter-"))

        if result.result.type == "error":
            err = result.result.error
            errors.append(f"  [error] Chapter {chapter_num}: {err.type} — {err.message}")
            continue

        raw_response = "".join(
            block.text
            for block in result.result.message.content
            if hasattr(block, "text")
        )

        parsed = parse_response(raw_response, [chapter_num])
        if chapter_num not in parsed:
            errors.append(
                f"  [error] Chapter {chapter_num}: response parsed but chapter missing from output."
            )
            continue

        path = overwrite_chapter_file(chapters_dir, chapter_num, parsed[chapter_num])
        print(f"  ✓ Chapter {chapter_num} — overwritten {path.name}")
        written += 1

    # ── Summary ──────────────────────────────────────────────────────────────
    print(f"\n  ✓ Formatting complete. {written} chapter(s) written.", end="")
    if skipped:
        print(f" {len(skipped)} skipped (missing files): {skipped}.", end="")
    if errors:
        print(f"\n\n  Errors encountered:")
        for e in errors:
            print(e)
    else:
        print()
