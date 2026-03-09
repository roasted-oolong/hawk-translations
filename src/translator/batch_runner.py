"""
src/translator/batch_runner.py
-------------------------------
Responsible for one thing: submitting a set of translation requests to the
Anthropic Batch API, polling until complete, and writing results to disk.

This module has no knowledge of prompts, reference files, or chapter
discovery. It receives ready-built requests and a write callable. Nothing more.

To change polling behavior, error handling, or result dispatch, edit only
this file.
"""

import time
from pathlib import Path
from typing import Callable

import anthropic


# Seconds between batch status polls.
_POLL_INTERVAL = 30


def run_translation_batch(
    requests: list[dict],
    client: anthropic.Anthropic,
    on_result: Callable[[str, str], None],
) -> None:
    """
    Submit translation requests as a single Batch API job, poll until
    complete, and dispatch each result to the provided callback.

    Parameters
    ----------
    requests : list[dict]
        List of batch request dicts. Each must have:
          - "custom_id": str  (used to identify the result)
          - "params": dict    (model, max_tokens, system, messages)
    client : anthropic.Anthropic
        Pre-built Anthropic client.
    on_result : Callable[[str, str], None]
        Called for each successful result with (custom_id, response_text).
        The caller is responsible for writing the result to disk.
    """
    if not requests:
        print("  No requests to submit.")
        return

    # ── Submit ───────────────────────────────────────────────────────────────
    print(f"\n  Submitting {len(requests)} chapter(s) to Batch API...")
    batch = client.messages.batches.create(requests=requests)
    batch_id = batch.id
    print(f"  Batch ID : {batch_id}")
    print(f"  Status   : {batch.processing_status}")
    print(f"\n  Polling every {_POLL_INTERVAL}s — safe to leave running...")

    # ── Poll ─────────────────────────────────────────────────────────────────
    while True:
        time.sleep(_POLL_INTERVAL)
        batch = client.messages.batches.retrieve(batch_id)
        counts = batch.request_counts
        print(
            f"  [{batch.processing_status}]  "
            f"processing: {counts.processing}  "
            f"succeeded: {counts.succeeded}  "
            f"errored: {counts.errored}"
        )
        if batch.processing_status == "ended":
            break

    # ── Retrieve and dispatch ─────────────────────────────────────────────────
    print("\n  Retrieving results...")
    errors: list[str] = []

    for result in client.messages.batches.results(batch_id):
        if result.result.type == "error":
            err = result.result.error
            errors.append(
                f"  [error] {result.custom_id}: {err.type} — {err.message}"
            )
            continue

        response_text = "".join(
            block.text
            for block in result.result.message.content
            if hasattr(block, "text")
        )
        on_result(result.custom_id, response_text)

    if errors:
        print(f"\n  Errors ({len(errors)}):")
        for e in errors:
            print(e)
