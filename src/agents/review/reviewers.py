"""
Review agents — four run in parallel after Phase 2.
consistency, tone, formatting → Sonnet
voice → Opus (narrative voice only)
"""

from ..base import call_claude, AgentResult
from ...config import SONNET_MODEL, OPUS_MODEL
from ...context.builder import build_system


# ── Consistency ───────────────────────────────────────────────────────────────

async def run_consistency_reviewer(
    translation: str,
    novel_info: str,
    guidelines: str,
    characters: str,
    terminology: str,
    cultural_phrases: str,
) -> AgentResult:
    system = build_system(
        novel_info, guidelines,
        characters=characters,
        terminology=terminology,
        cultural_phrases=cultural_phrases,
        cache_stable=True,
    )
    prompt = f"""Review this translation for CONSISTENCY only.

Check:
- All character names, titles, and address forms match characters.md
- All terminology matches established translations in terminology.md
- Cultural phrases handled consistently with cultural_phrases.md
- No character speaks in a register inconsistent with their established pattern

List every issue found with the specific line and the correction needed.
If none found, say: NO CONSISTENCY ISSUES.

TRANSLATION:
{translation}"""

    return await call_claude(
        SONNET_MODEL, system, prompt,
        agent_name="consistency_reviewer",
        label="Consistency review",
    )


# ── Tone ─────────────────────────────────────────────────────────────────────

async def run_tone_reviewer(
    translation: str,
    novel_info: str,
    guidelines: str,
    characters: str,
) -> AgentResult:
    system = build_system(
        novel_info, guidelines,
        characters=characters,
        cache_stable=True,
    )
    prompt = f"""Review this translation for TONE AND REGISTER only.

Check:
- Narration voice matches the novel's tone (dry, introspective, lightly self-deprecating)
- Dialogue feels authentic to each character's speech pattern
- No section drifts toward melodrama, over-explanation, or unearned sentiment
- Internal monologue retains Kang's characteristic reasoning-out-loud voice
- Emotional peaks land — neither flattened nor overstated

List every issue found with the specific line and what's wrong.
If none found, say: NO TONE ISSUES.

TRANSLATION:
{translation}"""

    return await call_claude(
        SONNET_MODEL, system, prompt,
        agent_name="tone_reviewer",
        label="Tone review",
    )


# ── Formatting ────────────────────────────────────────────────────────────────

async def run_formatting_reviewer(
    translation: str,
    novel_info: str,
    guidelines: str,
) -> AgentResult:
    system = build_system(
        novel_info, guidelines,
        cache_stable=True,
    )
    prompt = f"""Review this translation for FORMATTING RULE ADHERENCE only.

Check strictly against translation guidelines:
- No long dashes (—) anywhere — not mid-sentence, not for pauses, not for interruptions
- No colons used as structural punctuation
- All narration in past tense
- Paragraph breaks and pacing match source structure
- Internal monologue formatting applied consistently
- Any remaining inline flags [원래 한국어 / ...] listed for resolution

List every violation with the exact line.
If none found, say: NO FORMATTING ISSUES.

TRANSLATION:
{translation}"""

    return await call_claude(
        SONNET_MODEL, system, prompt,
        agent_name="formatting_reviewer",
        label="Formatting review",
    )


# ── Voice (Opus) ──────────────────────────────────────────────────────────────

async def run_voice_reviewer(
    translation: str,
    novel_info: str,
    guidelines: str,
) -> AgentResult:
    """
    Opus handles narrative voice specifically.
    Focused on the chapter-closing lines and emotional peak moments
    where interiority is most at risk of being flattened.
    """
    system = build_system(
        novel_info, guidelines,
        cache_stable=True,
    )
    prompt = f"""Review this translation for NARRATOR VOICE AND INTERIORITY only.

Focus on:
- Chapter-opening and chapter-closing lines — do they carry Kang's voice, not just his conclusion?
- Emotional peak moments — is the reader watching him think, or just receiving his conclusions?
- Rhetorical questions, self-corrections, reasoning chains that build out loud — are these preserved or collapsed?
- Any line that functions as a standalone observation or chapter-level callback — does it have room to land?
- Descriptive passages — do they flow and build, or fragment into staccato?

For each issue: quote the line, explain what's wrong, suggest a rewrite direction.
If none found, say: NO VOICE ISSUES.

TRANSLATION:
{translation}"""

    return await call_claude(
        OPUS_MODEL, system, prompt,
        agent_name="voice_reviewer",
        label="Voice review (Opus)",
    )
