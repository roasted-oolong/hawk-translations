"""
TranslationState — the single state object that flows through
the entire LangGraph workflow. Every node reads from and writes to this.
"""

from typing import TypedDict, List, Optional, Annotated
from operator import add
from pathlib import Path


class TranslationState(TypedDict):
    # ── Session inputs ────────────────────────────────────────────────────────
    novel_dir: str          # absolute path to novel directory
    korean_file: str        # absolute path to _korean source file
    output_path: str        # absolute path to output .txt file (set in prep)

    # ── Reference content (loaded once, passed through) ───────────────────────
    novel_info: str
    guidelines: str

    # ── Bible content (loaded per-agent, updated after extraction) ────────────
    bible_characters: str
    bible_terminology: str
    bible_cultural: str
    bible_locations: str
    bible_story: str        # watch list + current state only (not chapter log)

    # ── Prep stage ────────────────────────────────────────────────────────────
    korean_text: str        # cleaned Korean source after formatting

    # ── Bible extraction (parallel, one dict per agent) ───────────────────────
    bible_extractions: Annotated[List[dict], add]
    bible_corrections: Optional[str]    # your confirmation notes

    # ── Translation ───────────────────────────────────────────────────────────
    phase1_output: str
    phase2_output: str
    style_refs: List[str]   # content of _ANOTHER TRANSLATION files

    # ── Review (parallel, one dict per reviewer) ──────────────────────────────
    review_outputs: Annotated[List[dict], add]
    post_review_text: str

    # ── Step 11 ───────────────────────────────────────────────────────────────
    step11_extractions: Annotated[List[dict], add]
    step11_corrections: Optional[str]

    # ── Audit ─────────────────────────────────────────────────────────────────
    final_text: str

    # ── Workflow metadata ─────────────────────────────────────────────────────
    current_stage: str
    errors: Annotated[List[str], add]


def create_initial_state(
    novel_dir: str,
    korean_file: str,
) -> TranslationState:
    """Create a blank initial state from session inputs."""
    return TranslationState(
        novel_dir=novel_dir,
        korean_file=korean_file,
        output_path="",
        novel_info="",
        guidelines="",
        bible_characters="",
        bible_terminology="",
        bible_cultural="",
        bible_locations="",
        bible_story="",
        korean_text="",
        bible_extractions=[],
        bible_corrections=None,
        phase1_output="",
        phase2_output="",
        style_refs=[],
        review_outputs=[],
        post_review_text="",
        step11_extractions=[],
        step11_corrections=None,
        final_text="",
        current_stage="init",
        errors=[],
    )
