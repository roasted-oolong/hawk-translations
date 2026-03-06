"""
Routing functions for LangGraph conditional edges.
These handle user checkpoints and determine which node runs next.
"""

from typing import Literal
from ..state import TranslationState


def _checkpoint(label: str) -> str | None:
    """Blocking user confirmation. Returns None on CONFIRM, notes otherwise."""
    from .nodes import hr
    hr()
    print(f"  [CHECKPOINT] {label}")
    hr()
    while True:
        response = input("\n> Type CONFIRM to proceed, or enter corrections/notes:\n> ").strip()
        if response.upper() == "CONFIRM":
            return None
        elif response:
            return response
        else:
            print("  (Type CONFIRM or enter your notes.)")


def after_bible_extract(
    state: TranslationState,
) -> Literal["bible_write", "failed"]:
    """
    After bible extraction: present results, get confirmation.
    Injects user corrections into state before bible_write runs.
    """
    errors = state.get("errors", [])
    extractions = state.get("bible_extractions", [])
    success_count = sum(1 for e in extractions if e.get("success"))

    if success_count == 0:
        print("\n  [ERROR] All bible extractors failed. Cannot continue.")
        return "failed"

    corrections = _checkpoint(
        "Review the bible extractions above. Type CONFIRM to write them, "
        "or enter corrections."
    )
    # Inject corrections back into state via a side-channel
    # (LangGraph routing functions can't return state updates directly,
    #  so we write to a mutable slot via the state dict)
    state["bible_corrections"] = corrections  # type: ignore[typeddict-unknown-key]
    return "bible_write"


def after_review(
    state: TranslationState,
) -> Literal["step11", "failed"]:
    """
    After review: apply corrections to output file, then proceed to step 11.
    """
    from pathlib import Path
    from ..agents.base import call_claude
    from ..context import build_context
    from config import SONNET_MODEL

    review_outputs = state.get("review_outputs", [])
    all_review_text = "\n\n".join(
        f"[{r['reviewer'].upper()}]\n{r['output']}"
        for r in review_outputs
        if r.get("success") and r.get("output")
    )

    corrections = _checkpoint(
        "Review the notes above. Type CONFIRM to apply corrections and continue, "
        "or enter additional notes."
    )

    # Apply corrections to output file
    if state.get("output_path") and Path(state["output_path"]).exists():
        current_text = Path(state["output_path"]).read_text(encoding="utf-8")
        correction_note = f"\n\nAdditional user notes: {corrections}" if corrections else ""

        system = build_context("formatting_reviewer", state)
        prompt = (
            "Apply the following review corrections to this translation.\n"
            "Fix only what is listed. Do not make other changes.\n"
            "Return the COMPLETE corrected translation.\n\n"
            f"REVIEW ISSUES TO FIX:\n{all_review_text}"
            f"{correction_note}\n\n"
            f"TRANSLATION:\n{current_text}"
        )

        result = call_claude(
            agent_name="review_corrections",
            model=SONNET_MODEL,
            system_parts=system,
            user_message=prompt,
            max_tokens=16000,
            label="Applying review corrections",
        )

        if result.success and result.output:
            Path(state["output_path"]).write_text(result.output, encoding="utf-8")
            state["post_review_text"] = result.output  # type: ignore[typeddict-unknown-key]
            print(f"  ✓ Corrections applied.")

    return "step11"


def after_step11(
    state: TranslationState,
) -> Literal["audit", "failed"]:
    """After step 11: confirm additional bible updates, write them, then audit."""
    from pathlib import Path
    from ..agents.base import call_claude
    from ..context import build_context
    from config import SONNET_MODEL

    corrections = _checkpoint(
        "Review the Step 11 additional bible updates above. "
        "Type CONFIRM to write them, or enter corrections."
    )
    state["step11_corrections"] = corrections  # type: ignore[typeddict-unknown-key]

    # Write step 11 updates (same write logic as bible_write_node)
    bible_dir = Path(state["novel_dir"]) / "bible"
    correction_note = f"\n\nUser corrections: {corrections}" if corrections else ""

    domain_to_state_key = {
        "characters":       ("bible_characters",  "characters.md"),
        "terminology":      ("bible_terminology",  "terminology.md"),
        "cultural_phrases": ("bible_cultural",     "cultural_phrases.md"),
        "locations":        ("bible_locations",    "locations.md"),
        "story":            ("bible_story",        "story.md"),
    }

    for entry in state.get("step11_extractions", []):
        if not entry.get("success"):
            continue
        domain = entry["domain"]
        if domain not in domain_to_state_key:
            continue

        state_key, filename = domain_to_state_key[domain]
        current = state.get(state_key, "")
        updates = entry["output"]

        system = build_context("characters_extractor", state)
        prompt = (
            f"Update the {domain} bible file by integrating the new information below.\n"
            "Preserve all existing content. Add new entries cleanly.\n"
            "Return the COMPLETE updated file content only — no commentary.\n\n"
            f"CURRENT {domain.upper()} FILE:\n{current}\n\n"
            f"NEW UPDATES TO INTEGRATE:\n{updates}"
            f"{correction_note}"
        )

        result = call_claude(
            agent_name=f"step11_writer_{domain}",
            model=SONNET_MODEL,
            system_parts=system,
            user_message=prompt,
            label=f"Step 11 writing {domain}",
        )

        if result.success and result.output:
            Path(bible_dir / filename).write_text(result.output, encoding="utf-8")
            state[state_key] = result.output  # type: ignore[typeddict-unknown-key]
            print(f"  ✓ Updated: {filename}")

    return "audit"
