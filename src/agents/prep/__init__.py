"""Prep agents — formatter and file namer."""

from pathlib import Path
from ..base import call_claude, AgentResult
from ...context import build_context
from ...state import TranslationState
from config import HAIKU_MODEL


def run_formatter(state: TranslationState) -> AgentResult:
    raw = Path(state["korean_file"]).read_text(encoding="utf-8")
    system = build_context("formatter", state)

    prompt = (
        "Format and clean the following raw Korean chapter text so it reads naturally.\n"
        "Fix spacing, line breaks, and any OCR or encoding artifacts.\n"
        "Return ONLY the cleaned Korean text — no commentary, no translation.\n\n"
        f"RAW TEXT:\n{raw}"
    )

    result = call_claude(
        agent_name="formatter",
        model=HAIKU_MODEL,
        system_parts=system,
        user_message=prompt,
        max_tokens=16000,
        label="Formatting Korean",
    )

    if result.success and result.output:
        Path(state["korean_file"]).write_text(result.output, encoding="utf-8")

    return result


def run_file_namer(state: TranslationState, existing_titles: list, korean_text: str = "") -> AgentResult:
    system = build_context("file_namer", state)
    examples = "\n".join(existing_titles[-5:]) if existing_titles else "(none yet)"

    # Include the opening lines of the Korean text so Haiku can read the chapter title
    korean_preview = ""
    if korean_text:
        preview_lines = [ln for ln in korean_text.splitlines() if ln.strip()][:10]
        korean_preview = (
            f"\n\nKorean chapter opening (use this to identify the chapter title):\n"
            + "\n".join(preview_lines)
        )

    prompt = (
        f"Korean source filename: {Path(state['korean_file']).name}"
        f"{korean_preview}\n\n"
        "Derive the correct English output filename.\n"
        "Format: Chapter [##] - [English Chapter Title].txt\n"
        f"Existing filenames for reference (match this pattern exactly):\n{examples}\n\n"
        "Return ONLY the filename — nothing else. No explanation."
    )

    return call_claude(
        agent_name="file_namer",
        model=HAIKU_MODEL,
        system_parts=system,
        user_message=prompt,
        max_tokens=256,
        label="Naming output file",
    )
