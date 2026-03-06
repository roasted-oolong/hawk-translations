"""
LangGraph graph definition for the translation workflow.

Flow:
  init → prep → bible_extract → [checkpoint] → bible_write
       → translate → review → [checkpoint + corrections]
       → step11 → [checkpoint] → audit → output
"""

from langgraph.graph import StateGraph, END
from ..state import TranslationState
from .nodes import (
    init_node,
    prep_node,
    bible_extract_node,
    bible_write_node,
    translate_node,
    review_node,
    step11_node,
    audit_node,
    output_node,
)
from .routing import (
    after_bible_extract,
    after_review,
    after_step11,
)


def build_graph() -> StateGraph:
    workflow = StateGraph(TranslationState)

    # ── Add nodes ─────────────────────────────────────────────────────────────
    workflow.add_node("init",           init_node)
    workflow.add_node("prep",           prep_node)
    workflow.add_node("bible_extract",  bible_extract_node)
    workflow.add_node("bible_write",    bible_write_node)
    workflow.add_node("translate",      translate_node)
    workflow.add_node("review",         review_node)
    workflow.add_node("step11",         step11_node)
    workflow.add_node("audit",          audit_node)
    workflow.add_node("output",         output_node)

    # ── Entry point ───────────────────────────────────────────────────────────
    workflow.set_entry_point("init")

    # ── Edges ─────────────────────────────────────────────────────────────────
    workflow.add_edge("init",          "prep")
    workflow.add_edge("prep",          "bible_extract")

    # Checkpoint: user reviews extractions → write or fail
    workflow.add_conditional_edges(
        "bible_extract",
        after_bible_extract,
        {"bible_write": "bible_write", "failed": "output"},
    )

    workflow.add_edge("bible_write",   "translate")
    workflow.add_edge("translate",     "review")

    # Checkpoint: user reviews review notes → apply corrections → step11 or fail
    workflow.add_conditional_edges(
        "review",
        after_review,
        {"step11": "step11", "failed": "output"},
    )

    # Checkpoint: user reviews step11 updates → write updates → audit or fail
    workflow.add_conditional_edges(
        "step11",
        after_step11,
        {"audit": "audit", "failed": "output"},
    )

    workflow.add_edge("audit",         "output")
    workflow.add_edge("output",        END)

    return workflow


def compile_graph():
    return build_graph().compile()


_compiled = None

def get_compiled_graph():
    global _compiled
    if _compiled is None:
        _compiled = compile_graph()
    return _compiled


def run_translation(novel_dir: str, korean_file: str) -> TranslationState:
    """Entry point — runs the full translation workflow synchronously."""
    from ..state import create_initial_state

    initial_state = create_initial_state(
        novel_dir=novel_dir,
        korean_file=korean_file,
    )

    graph = get_compiled_graph()
    final_state = graph.invoke(initial_state)
    return final_state
