"""
src/translator/batch_runner.py
-------------------------------
Responsible for one thing: submitting a set of translation requests to a
local LLM and writing results via the provided callback.

Requests are processed sequentially — local models have no batch API.
The interface is intentionally identical to the previous Anthropic Batch API
version so callers require no changes.

This module has no knowledge of prompts, reference files, or chapter
discovery. It receives ready-built requests and a write callable. Nothing more.
"""

from typing import Callable

from openai import OpenAI


def run_translation_batch(
    requests: list[dict],
    client: OpenAI,
    on_result: Callable[[str, str], None],
) -> None:
    """
    Process translation requests sequentially via a local LLM, dispatching
    each result to the provided callback as it completes.

    Parameters
    ----------
    requests : list[dict]
        List of request dicts. Each must have:
          - "custom_id": str  (used to identify the result)
          - "params": dict    (model, max_tokens, system, messages)
    client : OpenAI
        Pre-built OpenAI-compatible client.
    on_result : Callable[[str, str], None]
        Called for each successful result with (custom_id, response_text).
        The caller is responsible for writing the result to disk.
    """
    if not requests:
        print("  No requests to submit.")
        return

    total = len(requests)
    print(f"\n  Translating {total} chapter(s) via local LLM...")
    errors: list[str] = []

    for i, req in enumerate(requests, 1):
        custom_id = req["custom_id"]
        params = req["params"]

        print(f"  [{i}/{total}] {custom_id}...", end=" ", flush=True)
        try:
            response = client.chat.completions.create(
                model=params["model"],
                max_tokens=params["max_tokens"],
                messages=[
                    {"role": "system", "content": params["system"]},
                    *params["messages"],
                ],
            )
            response_text = response.choices[0].message.content or ""
            on_result(custom_id, response_text)
            print("done")
        except Exception as exc:
            errors.append(f"  [error] {custom_id}: {exc}")
            print("failed")

    if errors:
        print(f"\n  Errors ({len(errors)}):")
        for e in errors:
            print(e)
