"""
Context builder — assembles step-scoped system prompts.

Each agent declares exactly what it needs. Nothing more is sent.
Tier 1 (novel_info + guidelines) is always included and cache-eligible.
Bible files are included only when the step genuinely requires them.
"""

from typing import List, Optional
from ..state import TranslationState
from config import CACHE_TYPE as _CACHE_TYPE

# ── Context keys ──────────────────────────────────────────────────────────────
NOVEL_INFO    = "novel_info"
GUIDELINES    = "guidelines"
CHARACTERS    = "characters"
TERMINOLOGY   = "terminology"
CULTURAL      = "cultural"
LOCATIONS     = "locations"
STORY         = "story"

# ── Per-step context declarations ─────────────────────────────────────────────
CONTEXT_FOR = {
    # Prep — mechanical, no bible needed
    "formatter":        [NOVEL_INFO],
    "file_namer":       [NOVEL_INFO],

    # Bible extraction — each agent only sees its own file
    "characters_extractor":   [NOVEL_INFO, GUIDELINES, CHARACTERS],
    "terminology_extractor":  [NOVEL_INFO, GUIDELINES, TERMINOLOGY],
    "cultural_extractor":     [NOVEL_INFO, GUIDELINES, CULTURAL],
    "locations_extractor":    [NOVEL_INFO, GUIDELINES, LOCATIONS],
    "story_extractor":        [NOVEL_INFO, GUIDELINES, STORY],

    # Translation — full literary context, no chapter log
    "phase1":   [NOVEL_INFO, GUIDELINES, CHARACTERS, TERMINOLOGY, CULTURAL, LOCATIONS, STORY],
    "phase2":   [NOVEL_INFO, GUIDELINES, CHARACTERS, TERMINOLOGY, CULTURAL, LOCATIONS, STORY],

    # Review — targeted per reviewer
    "consistency_reviewer": [NOVEL_INFO, CHARACTERS, TERMINOLOGY, CULTURAL],
    "tone_reviewer":        [NOVEL_INFO, GUIDELINES, STORY],
    "formatting_reviewer":  [NOVEL_INFO, GUIDELINES],
    "voice_reviewer":       [NOVEL_INFO, GUIDELINES, STORY],

    # Step 11 — post-translation bible updates, same scope as extraction
    "step11_characters":   [NOVEL_INFO, GUIDELINES, CHARACTERS],
    "step11_terminology":  [NOVEL_INFO, GUIDELINES, TERMINOLOGY],
    "step11_cultural":     [NOVEL_INFO, GUIDELINES, CULTURAL],
    "step11_locations":    [NOVEL_INFO, GUIDELINES, LOCATIONS],
    "step11_story":        [NOVEL_INFO, GUIDELINES, STORY],

    # Audit — guidelines only
    "dash_auditor":     [NOVEL_INFO, GUIDELINES],
}

CACHE_TYPE = _CACHE_TYPE


def build_context(step: str, state: TranslationState) -> List[dict]:
    """
    Build a system prompt block list for a given step.
    Tier 1 (novel_info + guidelines if declared) gets a cache_control marker.
    Bible files are appended as a second uncached block.
    """
    keys = CONTEXT_FOR.get(step, [NOVEL_INFO, GUIDELINES])

    # ── Tier 1: stable, cache-eligible ───────────────────────────────────────
    tier1_parts = []
    if NOVEL_INFO in keys:
        tier1_parts.append(f"## NOVEL INFO\n{state['novel_info']}")
    if GUIDELINES in keys:
        tier1_parts.append(f"## TRANSLATION GUIDELINES\n{state['guidelines']}")

    tier1_text = (
        "You are a professional Korean-to-English literary translator "
        "working on novels for potential publishing. Quality is the top priority.\n\n"
        + "\n\n".join(tier1_parts)
    )

    blocks = [
        {
            "type": "text",
            "text": tier1_text,
            "cache_control": {"type": CACHE_TYPE},
        }
    ]

    # ── Tier 2: bible files, assembled fresh ─────────────────────────────────
    bible_parts = []
    if CHARACTERS in keys and state.get("bible_characters"):
        bible_parts.append(f"=== CHARACTERS ===\n{state['bible_characters']}")
    if TERMINOLOGY in keys and state.get("bible_terminology"):
        bible_parts.append(f"=== TERMINOLOGY ===\n{state['bible_terminology']}")
    if CULTURAL in keys and state.get("bible_cultural"):
        bible_parts.append(f"=== CULTURAL PHRASES ===\n{state['bible_cultural']}")
    if LOCATIONS in keys and state.get("bible_locations"):
        bible_parts.append(f"=== LOCATIONS ===\n{state['bible_locations']}")
    if STORY in keys and state.get("bible_story"):
        bible_parts.append(f"=== STORY (Watch List & Current State) ===\n{state['bible_story']}")

    if bible_parts:
        blocks.append({
            "type": "text",
            "text": "## STORY BIBLE\n\n" + "\n\n".join(bible_parts),
        })

    return blocks
