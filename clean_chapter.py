#!/usr/bin/env python3
"""
clean_chapter.py
----------------
Reads raw Korean text from stdin, fixes structural issues (broken words,
unnatural line breaks) via the local LLM, and writes the cleaned text to
stdout.

Called by FormatKoreanChapterJob whenever a Korean chapter is uploaded.

Selected via FORMAT_BACKEND (config.py), same get_backend() seam as every
other pipeline script — defaults to "claude_code". Set FORMAT_BACKEND=local
to fall back to the Ollama path unchanged. Note: the reasoning_effort="low"
tuning below (this is the mechanical/HAIKU-tier task — fix line breaks,
preserve content exactly, no judgment calls) only applies on the "local"
path; the seam has no reasoning_effort passthrough and claude_code has no
equivalent flag. Measured 2026-07-16 on the same prompt: low produced ~half
the completion tokens of the default (303 vs 583) — meaningful on a
CPU-only box generating at ~9-12 tokens/sec, where a full chapter's
default-effort cleanup was taking 20-40+ minutes. That measurement no
longer applies once FORMAT_BACKEND=claude_code.

Exit code 0 on success, 1 on failure.
"""

import sys
from pathlib import Path

from dotenv import load_dotenv

load_dotenv()

sys.path.insert(0, str(Path(__file__).parent))

from config import FORMAT_BACKEND, FORMAT_MAX_TOKENS
from src.translation_backend import get_backend
from src.formatter.prompt_builder import build_system_prompt, build_user_message
from src.formatter.response_parser import parse_response

_CHAPTER_KEY = 1


def main() -> None:
    raw = sys.stdin.buffer.read().decode("utf-8", errors="replace")
    if not raw.strip():
        sys.stderr.write("clean_chapter.py: empty input\n")
        sys.exit(1)

    backend = get_backend(FORMAT_BACKEND)
    system_prompt = build_system_prompt()
    user_message = build_user_message({_CHAPTER_KEY: raw})

    try:
        raw_response = backend(
            system_prompt=system_prompt,
            user_message=user_message,
            max_tokens=FORMAT_MAX_TOKENS,
        )
    except Exception as exc:
        sys.stderr.write(f"clean_chapter.py: LLM error: {exc}\n")
        sys.exit(1)

    parsed = parse_response(raw_response, [_CHAPTER_KEY])
    if _CHAPTER_KEY not in parsed:
        sys.stderr.write("clean_chapter.py: failed to parse LLM response\n")
        sys.stderr.write(f"Raw response:\n{raw_response[:500]}\n")
        sys.exit(1)

    sys.stdout.buffer.write(parsed[_CHAPTER_KEY].encode("utf-8"))


if __name__ == "__main__":
    main()
