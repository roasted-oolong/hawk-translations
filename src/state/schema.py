"""State schema for the translation workflow."""

from typing import TypedDict, List, Optional, Annotated
from operator import add


class TranslationState(TypedDict):
    """
    Central state object flowing through the LangGraph translation workflow.
    All agents read from and write to this state.
    """

    # ── INPUT ────────────────────────────────────────────────────────────────
    novel_dir: str
    korean_file: str
    novel_info: str
    guidelines: str

    # ── STAGE 1: PREP ────────────────────────────────────────────────────────
    korean_text: str          # Cleaned/formatted Korean source
    output_path: str          # Path to output .txt file

    # ── STAGE 2: BIBLE ───────────────────────────────────────────────────────
    # One entry per bible agent, accumulated via add
    bible_extractions: Annotated[List[dict], add]
    bible_corrections: Optional[str]   # User input at checkpoint

    # ── STAGE 3: TRANSLATION ─────────────────────────────────────────────────
    phase1_output: str
    phase2_output: str

    # ── STAGE 4: REVIEW ──────────────────────────────────────────────────────
    # One entry per review agent, accumulated via add
    review_outputs: Annotated[List[dict], add]
    post_review_text: str
    step11_corrections: Optional[str]  # User input at checkpoint

    # ── STAGE 5: AUDIT ───────────────────────────────────────────────────────
    final_text: str

    # ── METADATA ─────────────────────────────────────────────────────────────
    current_stage: str
    errors: Annotated[List[str], add]


def create_initial_state(
    novel_dir: str,
    korean_file: str,
    novel_info: str,
    guidelines: str,
) -> TranslationState:
    """Create initial workflow state from session inputs."""
    return TranslationState(
        novel_dir=novel_dir,
        korean_file=korean_file,
        novel_info=novel_info,
        guidelines=guidelines,
        korean_text="",
        output_path="",
        bible_extractions=[],
        bible_corrections=None,
        phase1_output="",
        phase2_output="",
        review_outputs=[],
        post_review_text="",
        step11_corrections=None,
        final_text="",
        current_stage="init",
        errors=[],
    )
