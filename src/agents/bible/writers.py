"""
Bible writers — update each bible file with extracted content.
Run in parallel after user confirmation. One agent per file.
"""

from ..base import call_claude, AgentResult
from ...config import SONNET_MODEL
from ...context.builder import build_system


async def run_bible_writer(
    bible_key: str,
    current_content: str,
    updates: str,
    corrections: str,
    novel_info: str,
    guidelines: str,
) -> AgentResult:
    """
    Generic bible writer — takes a key and writes that file's updated content.
    bible_key: one of characters / terminology / cultural_phrases / locations / story
    """
    correction_note = f"\nUser corrections: {corrections}" if corrections else ""

    system = build_system(novel_info, guidelines, cache_stable=True)

    prompt = f"""Update the {bible_key} bible file by integrating the new information below.
Preserve ALL existing content. Add new entries cleanly without duplicating.
Return the COMPLETE updated file content only — no commentary, no preamble.

CURRENT {bible_key.upper()} FILE:
{current_content}

NEW UPDATES TO INTEGRATE:
{updates}
{correction_note}"""

    return await call_claude(
        SONNET_MODEL, system, prompt,
        agent_name=f"{bible_key}_writer",
        label=f"Writing {bible_key}",
    )
