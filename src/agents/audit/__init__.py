"""Dash audit agent."""

from pathlib import Path
from ..base import call_claude, AgentResult
from ...context import build_context
from ...state import TranslationState
from config import SONNET_MODEL


def run_dash_auditor(state: TranslationState) -> AgentResult:
    if state.get("output_path") and Path(state["output_path"]).exists():
        current_text = Path(state["output_path"]).read_text(encoding="utf-8")
    else:
        current_text = state.get("post_review_text", "")

    system = build_context("dash_auditor", state)

    prompt = (
        "Perform a Phase 3 dash audit on this translation.\n\n"
        "Read line by line. Find every long dash (—) in the text.\n"
        "For each one:\n"
        "1. Copy the original line\n"
        "2. Rewrite it without the dash — restructure, break into two sentences, "
        "or find the word that carries the weight the dash was doing\n\n"
        "Return the COMPLETE corrected translation with all instances resolved.\n"
        "No long dashes should remain anywhere in the output.\n\n"
        f"TRANSLATION:\n{current_text}"
    )

    result = call_claude(
        agent_name="dash_auditor",
        model=SONNET_MODEL,
        system_parts=system,
        user_message=prompt,
        max_tokens=16000,
        label="Dash audit (Sonnet)",
    )

    if result.success and result.output and state.get("output_path"):
        Path(state["output_path"]).write_text(result.output, encoding="utf-8")
        print(f"  ✓ Dash audit complete. Written to: {Path(state['output_path']).name}")

    return result
