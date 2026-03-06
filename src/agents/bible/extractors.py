"""
Bible extraction agents — one per file, run in parallel.
Each agent reads only its own bible file and reports updates for that domain.
All run on Sonnet.
"""

from ..base import call_claude, AgentResult
from ...config import SONNET_MODEL
from ...context.builder import build_system


# ── Shared extraction instructions ──────────────────────────────────────────

_BASE_INSTRUCTIONS = """
Return ONLY the updates for your assigned domain.
Be specific. Quote Korean terms alongside proposed English handling.
If nothing new was found for your domain, say: NO UPDATES.
"""


# ── Characters ───────────────────────────────────────────────────────────────

async def run_characters_extractor(
    korean_text: str,
    novel_info: str,
    guidelines: str,
    current_characters: str,
) -> AgentResult:
    system = build_system(
        novel_info, guidelines,
        characters=current_characters,
        cache_stable=True,
    )
    prompt = f"""Extract all CHARACTER updates needed from this chapter.

For every character appearing (new OR existing), record:
- How other characters address them (titles, nicknames, honorifics)
- How they address other characters
- Speech patterns, verbal tics, or recurring expressions established or reinforced
- Any new physical description, personality notes, or relationship developments

Current characters.md is in your system prompt for reference.
{_BASE_INSTRUCTIONS}

CHAPTER:
{korean_text}"""

    return await call_claude(
        SONNET_MODEL, system, prompt,
        agent_name="characters_extractor",
        label="Extracting character updates",
    )


# ── Terminology ───────────────────────────────────────────────────────────────

async def run_terminology_extractor(
    korean_text: str,
    novel_info: str,
    guidelines: str,
    current_terminology: str,
) -> AgentResult:
    system = build_system(
        novel_info, guidelines,
        terminology=current_terminology,
        cache_stable=True,
    )
    prompt = f"""Extract all TERMINOLOGY updates needed from this chapter.

Look for:
- New titles, roles, or industry terms
- New proper nouns (group names, show titles, song titles, companies)
- New gaming, streaming, or fan culture terms
- New technical or production terms
- Any existing terms used in a new way

Current terminology.md is in your system prompt for reference.
{_BASE_INSTRUCTIONS}

CHAPTER:
{korean_text}"""

    return await call_claude(
        SONNET_MODEL, system, prompt,
        agent_name="terminology_extractor",
        label="Extracting terminology updates",
    )


# ── Cultural Phrases ──────────────────────────────────────────────────────────

async def run_cultural_extractor(
    korean_text: str,
    novel_info: str,
    guidelines: str,
    current_cultural: str,
) -> AgentResult:
    system = build_system(
        novel_info, guidelines,
        cultural_phrases=current_cultural,
        cache_stable=True,
    )
    prompt = f"""Extract all CULTURAL PHRASE updates needed from this chapter.

Look for:
- Korean idioms, proverbs, or set expressions
- Untranslatable cultural concepts
- Internet slang or colloquial expressions
- Any phrase that will require a T/N or careful localization decision
- Check against existing cultural_phrases.md — do not duplicate entries

Current cultural_phrases.md is in your system prompt for reference.
{_BASE_INSTRUCTIONS}

CHAPTER:
{korean_text}"""

    return await call_claude(
        SONNET_MODEL, system, prompt,
        agent_name="cultural_extractor",
        label="Extracting cultural phrase updates",
    )


# ── Locations ─────────────────────────────────────────────────────────────────

async def run_locations_extractor(
    korean_text: str,
    novel_info: str,
    guidelines: str,
    current_locations: str,
) -> AgentResult:
    system = build_system(
        novel_info, guidelines,
        locations=current_locations,
        cache_stable=True,
    )
    prompt = f"""Extract all LOCATION updates needed from this chapter.

Look for:
- New locations introduced (with descriptions and significance)
- Existing locations appearing in a new context
- Any setting detail worth recording for consistency

Current locations.md is in your system prompt for reference.
{_BASE_INSTRUCTIONS}

CHAPTER:
{korean_text}"""

    return await call_claude(
        SONNET_MODEL, system, prompt,
        agent_name="locations_extractor",
        label="Extracting location updates",
    )


# ── Story ─────────────────────────────────────────────────────────────────────

async def run_story_extractor(
    korean_text: str,
    novel_info: str,
    guidelines: str,
    current_story: str,
) -> AgentResult:
    system = build_system(
        novel_info, guidelines,
        story=current_story,
        cache_stable=True,
    )
    prompt = f"""Extract all STORY updates needed from this chapter.

Look for:
- New plot points and narrative developments
- Subplot progressions or resolutions
- New or evolving themes and motifs
- New watch list items worth flagging
- Updates to existing watch list items (resolved, advanced, or changed)
- Any narrative callback or setup that should be tracked

Current story.md is in your system prompt for reference.
{_BASE_INSTRUCTIONS}

CHAPTER:
{korean_text}"""

    return await call_claude(
        SONNET_MODEL, system, prompt,
        agent_name="story_extractor",
        label="Extracting story updates",
    )
