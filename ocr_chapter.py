#!/usr/bin/env python3
"""
ocr_chapter.py
--------------
Transcribes Korean text from one or more photo images, in the order given,
and writes the concatenated text to stdout.

Usage:
    ocr_chapter.py <image_path_1> <image_path_2> ... <image_path_N>

Called by OcrChapterJob whenever a chapter is uploaded as photo scans.
Order is taken from argv order and is never re-sorted — the caller (the
browser drop order, resynced through the upload form) is the sole authority
on page order.

Switched from Tesseract (Docker) to Claude vision 2026-07-23: this
project's real source photos are uniformly clean e-reader screenshots (not
degraded physical-book photos), and on that input Tesseract's per-character
Hangul misreads (e.g. "콩개홀" for "공개홀" — jamo-level confusion) turned out
unfixable by image preprocessing. Autocontrast, hard thresholding, and 2x
upscaling were all tested directly against a real page; none reduced the
error count, they only shifted which characters came out wrong. Claude reads
the same pages with no character errors in testing, because grammatical/
lexical plausibility resolves visually-ambiguous strokes that pixel-level
classification alone can't.

Each source photo may be a single page or a two-page spread (e-reader
screenshots showing two facing pages side by side). Unlike the Tesseract
path, spreads are NOT split before transcription — Claude reads a full
spread directly in correct left-then-right reading order and rejoins a
sentence split across the page boundary on its own (verified against real
chapter photos), which is exactly the ordering problem that forced the
Tesseract path to split spreads into halves in the first place.

Anti-fabrication guardrail: PaddleOCR (this script's OCR engine before
Tesseract) was replaced specifically because it produced confident-looking
*fabricated* text with no reliable way to detect it. A generative model
doing this job has the same underlying risk, so the prompt explicitly
instructs Claude to mark genuinely illegible characters with a literal
"[?]" instead of guessing a plausible-looking substitute — the failure mode
this script depends on is "visibly flagged," not "silently smoothed over."

Uses the Claude Code CLI in headless mode (`claude -p`), authenticated via
the user's Claude subscription rather than a metered ANTHROPIC_API_KEY —
same auth pattern as src/claude_code_agent.py (the translation backend).
Deliberately not implemented as a call through that module: this needs an
image content block via `--input-format stream-json`, which
claude_code_agent.call() (plain-text stdin only) doesn't support.

Exit code 0 on success, 1 on failure. On any per-image failure the script
exits immediately without writing partial output to stdout, so the caller
never attaches a half-transcribed chapter.
"""

import base64
import json
import mimetypes
import os
import subprocess
import sys

CLAUDE_BIN = os.environ.get("CLAUDE_BIN", "claude")
TIMEOUT_SECONDS = 120

# Real two-page spread cost ~$0.037 in testing; $0.50 leaves headroom
# without being a meaningless placeholder.
OCR_MODEL = os.environ.get("OCR_MODEL", "claude-sonnet-5")
OCR_MAX_BUDGET_USD = os.environ.get("OCR_MAX_BUDGET_USD", "0.50")

SYSTEM_PROMPT = """You transcribe Korean text from an image of a novel manuscript page, exactly as written.

Rules:
- Preserve paragraph breaks, dialogue quotation marks, and line structure as they appear.
- Do not translate, summarize, paraphrase, or add anything not present in the image.
- If the image shows a two-page spread, transcribe the left page fully, then the
  right page. If a sentence is split across the page boundary, join it into one
  sentence rather than leaving it broken.
- If a character is genuinely illegible (not just stylistically unusual), write
  the literal placeholder [?] in its place instead of guessing a plausible-looking
  substitute. Never silently invent or "correct" text.
- Output only the transcribed text. No commentary, no preamble, no markdown fencing."""


def transcribe_image(path: str) -> str:
    """
    Transcribe one source photo via the Claude Code CLI.

    Raises RuntimeError on any failure (CLI missing, timeout, non-success
    response) with enough detail for the caller to log and surface as an
    ocr_failed status.
    """
    media_type = mimetypes.guess_type(path)[0] or "image/jpeg"

    with open(path, "rb") as f:
        image_b64 = base64.standard_b64encode(f.read()).decode("ascii")

    stream_input = json.dumps({
        "type": "user",
        "message": {
            "role": "user",
            "content": [
                {"type": "image", "source": {"type": "base64", "media_type": media_type, "data": image_b64}},
                {"type": "text", "text": "Transcribe this page."},
            ],
        },
    }) + "\n"

    cmd = [
        CLAUDE_BIN, "-p",
        "--system-prompt", SYSTEM_PROMPT,
        "--input-format", "stream-json",
        "--output-format", "stream-json",
        "--verbose",
        "--model", OCR_MODEL,
        "--tools", "",
        "--permission-mode", "bypassPermissions",
        "--no-session-persistence",
        "--max-budget-usd", str(OCR_MAX_BUDGET_USD),
    ]

    env = dict(os.environ)
    # As in src/claude_code_agent.py: a stray API key here would silently
    # shadow the subscription (OAuth) auth this depends on.
    env.pop("ANTHROPIC_API_KEY", None)

    try:
        proc = subprocess.run(
            cmd,
            input=stream_input,
            capture_output=True,
            text=True,
            encoding="utf-8",
            timeout=TIMEOUT_SECONDS,
            env=env,
        )
    except FileNotFoundError:
        raise RuntimeError(
            f"Claude Code CLI not found ({CLAUDE_BIN!r}). Install it, or set CLAUDE_BIN to its path."
        ) from None
    except subprocess.TimeoutExpired:
        raise RuntimeError(f"claude CLI timed out after {TIMEOUT_SECONDS}s on {path}") from None

    if proc.returncode != 0:
        raise RuntimeError(f"claude CLI exited {proc.returncode} on {path}: {proc.stderr}")

    return _extract_result_text(proc.stdout, path)


def _extract_result_text(stdout: str, path: str) -> str:
    """
    --output-format stream-json emits one JSON object per line; the final
    line (type "result") carries the completed response and error state.
    """
    result_event = None
    for line in stdout.splitlines():
        line = line.strip()
        if not line:
            continue
        event = json.loads(line)
        if event.get("type") == "result":
            result_event = event

    if result_event is None:
        raise RuntimeError(f"claude CLI produced no result event for {path}: {stdout[:500]!r}")

    if result_event.get("is_error"):
        raise RuntimeError(
            f"claude CLI reported error for {path} "
            f"(subtype={result_event.get('subtype')!r}): {result_event.get('result')!r}"
        )

    return (result_event.get("result") or "").strip()


def main() -> None:
    paths = sys.argv[1:]
    if not paths:
        sys.stderr.write("ocr_chapter.py: no image paths given\n")
        sys.exit(1)

    transcriptions = []
    for path in paths:
        try:
            transcriptions.append(transcribe_image(path))
        except Exception as exc:
            sys.stderr.write(f"ocr_chapter.py: failed to transcribe {path!r}: {exc}\n")
            sys.exit(1)

    sys.stdout.buffer.write("\n\n".join(transcriptions).encode("utf-8"))


if __name__ == "__main__":
    main()
