"""
src/formatter/runner.py
------------------------
Responsible for one thing: orchestrating chapter formatting via a local LLM.

Each chapter is processed sequentially. The prompt format, file I/O, and
response parsing are unchanged — only the API interaction pattern differs
from the previous Anthropic Batch API version.
"""

from pathlib import Path

from openai import OpenAI

from config import HAIKU_MODEL, FORMAT_MAX_TOKENS
from .chapter_io import read_korean_chapter, overwrite_chapter_file
from .prompt_builder import build_system_prompt, build_user_message
from .response_parser import parse_response


def run_formatter(
    novel_dir: Path,
    chapter_nums: list[int],
    client: OpenAI,
) -> None:
    """
    Format each chapter in chapter_nums using the local LLM.

    Parameters
    ----------
    novel_dir : Path
        Root directory of the novel.
    chapter_nums : list[int]
        Sorted list of chapter numbers to format.
    client : OpenAI
        Pre-built OpenAI-compatible client.
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

    total = len(chapters_content)
    print(f"\n  Formatting {total} chapter(s) via local LLM...")

    written = 0
    errors: list[str] = []

    for i, num in enumerate(sorted(chapters_content.keys()), 1):
        print(f"  [{i}/{total}] chapter {num}...", end=" ", flush=True)
        user_message = build_user_message({num: chapters_content[num]})

        try:
            response = client.chat.completions.create(
                model=HAIKU_MODEL,
                max_tokens=FORMAT_MAX_TOKENS,
                messages=[
                    {"role": "system", "content": system_prompt},
                    {"role": "user", "content": user_message},
                ],
            )
            raw_response = response.choices[0].message.content or ""
        except Exception as exc:
            errors.append(f"  [error] Chapter {num}: {exc}")
            print("failed")
            continue

        parsed = parse_response(raw_response, [num])
        if num not in parsed:
            errors.append(
                f"  [error] Chapter {num}: response parsed but chapter missing from output."
            )
            print("failed")
            continue

        path = overwrite_chapter_file(chapters_dir, num, parsed[num])
        print(f"done — {path.name}")
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
