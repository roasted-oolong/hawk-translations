"""Translation agents — Phase 1 (Sonnet) and Phase 2 (Opus)."""

from pathlib import Path
from ..base import call_claude, AgentResult
from ...context import build_context
from ...state import TranslationState
from config import SONNET_MODEL, OPUS_MODEL


def run_phase1(state: TranslationState) -> AgentResult:
    system = build_context("phase1", state)
    prompt = (
        "Translate the following Korean chapter into English.\n\n"
        "PHASE 1 GOALS:\n"
        "- Accurate, natural first translation\n"
        "- Preserve all meaning, nuance, and register\n"
        "- Flag uncertain terms inline: [원래 한국어 / proposed translation?]\n"
        "- Do not flatten emotional peaks or cultural nuance\n"
        "- Preserve paragraph structure throughout\n\n"
        f"CHAPTER:\n{state['korean_text']}"
    )

    result = call_claude(
        agent_name="phase1",
        model=SONNET_MODEL,
        system_parts=system,
        user_message=prompt,
        max_tokens=16000,
        label="Phase 1 translation (Sonnet)",
    )

    if result.success and result.output and state.get("output_path"):
        Path(state["output_path"]).write_text(result.output, encoding="utf-8")
        print(f"  ✓ Phase 1 written to: {Path(state['output_path']).name}")

    return result


def run_phase2(state: TranslationState) -> AgentResult:
    # Always read Phase 1 fresh from disk
    phase1_from_file = ""
    if state.get("output_path") and Path(state["output_path"]).exists():
        phase1_from_file = Path(state["output_path"]).read_text(encoding="utf-8")
    else:
        phase1_from_file = state.get("phase1_output", "")

    system = build_context("phase2", state)

    if state.get("style_refs"):
        style_block = "\n\n".join(
            f"=== STYLE REFERENCE ===\n{ref}" for ref in state["style_refs"]
        )
        system.append({
            "type": "text",
            "text": (
                "## STYLE REFERENCES — Use for voice calibration:\n"
                "Dialogue register, laughter and disrupted speech, "
                "colloquial naturalness, emotional pacing.\n\n"
                + style_block
            ),
        })

    prompt = (
        "You are performing Phase 2: full localization and rewrite.\n\n"
        "PHASE 2 GOALS:\n"
        "- Full localization — write as if originally written in English\n"
        "- Calibrate voice from the style references provided\n"
        "- Sentence integration: merge in narration/internal monologue; "
        "preserve separation at emotional peaks and tonal pivots\n"
        "- Before writing any chapter-closing line or emotional peak: "
        "re-read the POV & Narrative Style from novel_info.md and hear "
        "the narrator's voice — do not flatten interiority for a clean landing\n"
        "- Preserve all inline flags: [원래 한국어 / proposed translation?]\n"
        "- Rolling consistency with the story bible\n\n"
        f"PHASE 1 TRANSLATION (rewrite this):\n{phase1_from_file}\n\n"
        f"ORIGINAL KOREAN (reference):\n{state['korean_text']}"
    )

    result = call_claude(
        agent_name="phase2",
        model=OPUS_MODEL,
        system_parts=system,
        user_message=prompt,
        max_tokens=16000,
        label="Phase 2 rewrite (Opus)",
    )

    if result.success and result.output and state.get("output_path"):
        Path(state["output_path"]).write_text(result.output, encoding="utf-8")
        print(f"  ✓ Phase 2 written to: {Path(state['output_path']).name}")

    return result
