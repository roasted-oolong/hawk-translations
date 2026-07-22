"""
src/translator/batch_runner.py
-------------------------------
Responsible for one thing: submitting a set of translation requests through
the active translation backend (src/translation_backend.py) and writing
results via the provided callback.

Requests are processed sequentially — neither the local-LLM path nor the
Claude Code CLI has a true batch API. The interface is intentionally
backend-agnostic so callers require no changes when TRANSLATION_BACKEND
changes.

This module has no knowledge of prompts, reference files, or chapter
discovery. It receives ready-built requests and a write callable. Nothing
more.
"""

from typing import TYPE_CHECKING, Callable

from src.translation_backend import get_backend

if TYPE_CHECKING:
    from src.skills.base import Skill


def run_translation_batch(
    requests: list[dict],
    on_result: Callable[[str, str], None],
    skills: "list[Skill] | None" = None,
) -> None:
    """
    Translate each request sequentially via the active translation backend,
    dispatching each result to the provided callback as it completes.

    Parameters
    ----------
    requests : list[dict]
        List of request dicts. Each must have:
          - "custom_id": str  (used to identify the result)
          - "params": dict    (must contain "system" and "messages"; may
            optionally contain "model"/"max_tokens" to override the active
            backend's defaults for that request)
    on_result : Callable[[str, str], None]
        Called for each successful result with (custom_id, response_text).
        The caller is responsible for writing the result to disk.
    skills : list[Skill] | None
        Optional skills (e.g. BibleLookupSkill, WebSearchSkill), passed
        through unchanged to every request.
    """
    if not requests:
        print("  No requests to submit.")
        return

    backend = get_backend()
    total = len(requests)
    print(f"\n  Translating {total} chapter(s)...")
    errors: list[str] = []

    for i, req in enumerate(requests, 1):
        custom_id = req["custom_id"]
        params = req["params"]

        print(f"  [{i}/{total}] {custom_id}...", end=" ", flush=True)
        try:
            response_text = backend(
                system_prompt=params["system"],
                user_message=params["messages"][0]["content"],
                model=params.get("model"),
                max_tokens=params.get("max_tokens"),
                skills=skills,
            )
            on_result(custom_id, response_text)
            print("done")
        except Exception as exc:
            errors.append(f"  [error] {custom_id}: {exc}")
            print("failed")

    if errors:
        print(f"\n  Errors ({len(errors)}):")
        for e in errors:
            print(e)
