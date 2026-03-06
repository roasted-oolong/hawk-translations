"""Dash auditor — Phase 3. Sonnet, guidelines only."""

from ..base import call_claude, AgentResult
from ...config import SONNET_MODEL
from ...context.builder import build_system


async def run_dash_auditor(
    translation: str,
    novel_info: str,
    guidelines: str,
) -> AgentResult:
    """
    Phase 3 dash audit.
    Read line by line. Every long dash (—) must be found and rewritten.
    Returns the COMPLETE corrected translation.
    """
    system = build_system(
        novel_info, guidelines,
        cache_stable=True,
    )

    prompt = f"""Perform a Phase 3 dash audit on this translation.

Read line by line. Find every long dash (—) in the text.
For each one:
1. Copy the original line exactly
2. Rewrite the line without the dash — restructure the sentence, break it in two, or find the word that carries the weight the dash was doing
3. Never simply remove the dash and leave a broken sentence

There are no permitted uses. Every instance must be rewritten.

Return the COMPLETE corrected translation with all dashes resolved.
Do not summarize or truncate — return the full text.

TRANSLATION:
{translation}"""

    return await call_claude(
        SONNET_MODEL, system, prompt,
        agent_name="dash_auditor",
        label="Phase 3 dash audit",
    )
