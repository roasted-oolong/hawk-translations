"""Phase 1 translation — Sonnet with targeted context."""

from ..base import call_claude, AgentResult
from ...config import SONNET_MODEL
from ...context.builder import build_system


async def run_phase1(
    korean_text: str,
    novel_info: str,
    guidelines: str,
    characters: str,
    terminology: str,
    cultural_phrases: str,
) -> AgentResult:
    """
    Phase 1: accurate, natural first translation.
    Receives characters, terminology, and cultural_phrases only.
    Locations and story are not needed for translation accuracy.
    """
    system = build_system(
        novel_info, guidelines,
        characters=characters,
        terminology=terminology,
        cultural_phrases=cultural_phrases,
        cache_stable=True,
    )

    prompt = f"""Translate the following Korean chapter into English.

PHASE 1 GOALS:
- Accurate, natural first translation
- Preserve all meaning, nuance, and register
- Flag uncertain terms inline: [원래 한국어 / proposed translation?]
- Do not flatten emotional peaks or cultural nuance
- Preserve paragraph structure throughout

CHAPTER:
{korean_text}"""

    return await call_claude(
        SONNET_MODEL, system, prompt,
        agent_name="phase1_translator",
        label="Phase 1 translation (Sonnet)",
    )
