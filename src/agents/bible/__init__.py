"""Bible extraction agents — run in parallel, one per bible file."""

import asyncio
from ..base import call_claude, AgentResult
from ...context import build_context
from ...state import TranslationState
from config import SONNET_MODEL


def _extraction_prompt(domain: str, current_content: str, korean_text: str) -> str:
    return (
        f"Read this Korean chapter carefully and extract ALL updates needed "
        f"for the {domain} bible file.\n\n"
        f"For every entry — new OR existing — record any changes or additions.\n"
        f"Check your findings against the current file to avoid duplicating "
        f"what is already established.\n\n"
        f"Return your findings as a clearly structured list of proposed updates only.\n"
        f"Do NOT return the full file — only what is new or changed.\n\n"
        f"CURRENT {domain.upper()} FILE:\n{current_content}\n\n"
        f"KOREAN CHAPTER:\n{korean_text}"
    )


def run_characters_extractor(state: TranslationState) -> AgentResult:
    system = build_context("characters_extractor", state)
    prompt = (
        "Read this Korean chapter and extract ALL updates needed for characters.md.\n\n"
        "For EVERY character appearing (new or existing), explicitly check and record:\n"
        "- How other characters address them (titles, nicknames, honorifics)\n"
        "- How they address other characters\n"
        "- Any speech patterns, verbal tics, or recurring expressions established "
        "or reinforced in this chapter\n\n"
        "Check against the current file to avoid duplicating what is established.\n"
        "Return proposed updates only — not the full file.\n\n"
        f"CURRENT CHARACTERS FILE:\n{state['bible_characters']}\n\n"
        f"KOREAN CHAPTER:\n{state['korean_text']}"
    )
    return call_claude(
        agent_name="characters_extractor",
        model=SONNET_MODEL,
        system_parts=system,
        user_message=prompt,
        label="Extracting character updates",
    )


def run_terminology_extractor(state: TranslationState) -> AgentResult:
    system = build_context("terminology_extractor", state)
    prompt = _extraction_prompt("terminology", state["bible_terminology"], state["korean_text"])
    return call_claude(
        agent_name="terminology_extractor",
        model=SONNET_MODEL,
        system_parts=system,
        user_message=prompt,
        label="Extracting terminology updates",
    )


def run_cultural_extractor(state: TranslationState) -> AgentResult:
    system = build_context("cultural_extractor", state)
    prompt = _extraction_prompt("cultural phrases", state["bible_cultural"], state["korean_text"])
    return call_claude(
        agent_name="cultural_extractor",
        model=SONNET_MODEL,
        system_parts=system,
        user_message=prompt,
        label="Extracting cultural phrase updates",
    )


def run_locations_extractor(state: TranslationState) -> AgentResult:
    system = build_context("locations_extractor", state)
    prompt = _extraction_prompt("locations", state["bible_locations"], state["korean_text"])
    return call_claude(
        agent_name="locations_extractor",
        model=SONNET_MODEL,
        system_parts=system,
        user_message=prompt,
        label="Extracting location updates",
    )


def run_story_extractor(state: TranslationState) -> AgentResult:
    system = build_context("story_extractor", state)
    prompt = (
        "Read this Korean chapter and extract ALL updates needed for story.md.\n\n"
        "Focus on:\n"
        "- New plot developments and their impact on unresolved threads\n"
        "- Watch list items that advance, resolve, or newly appear\n"
        "- New themes or motifs introduced\n"
        "- World building details added\n\n"
        "Check against the current file. Return proposed updates only.\n\n"
        f"CURRENT STORY FILE:\n{state['bible_story']}\n\n"
        f"KOREAN CHAPTER:\n{state['korean_text']}"
    )
    return call_claude(
        agent_name="story_extractor",
        model=SONNET_MODEL,
        system_parts=system,
        user_message=prompt,
        label="Extracting story updates",
    )


async def run_all_extractors_async(state: TranslationState) -> list:
    loop = asyncio.get_event_loop()
    tasks = [
        loop.run_in_executor(None, run_characters_extractor, state),
        loop.run_in_executor(None, run_terminology_extractor, state),
        loop.run_in_executor(None, run_cultural_extractor, state),
        loop.run_in_executor(None, run_locations_extractor, state),
        loop.run_in_executor(None, run_story_extractor, state),
    ]
    names = ["characters", "terminology", "cultural_phrases", "locations", "story"]
    results = await asyncio.gather(*tasks, return_exceptions=True)

    outputs = []
    for i, result in enumerate(results):
        name = names[i]
        if isinstance(result, Exception):
            print(f"  FAILED: {name} — {result}")
            outputs.append({"domain": name, "output": None, "success": False, "error": str(result)})
        elif not result.success:
            print(f"  FAILED: {name} — {result.error}")
            outputs.append({"domain": name, "output": None, "success": False, "error": result.error})
        else:
            print(f"  DONE:   {name} ({result.execution_time_ms / 1000:.1f}s)")
            outputs.append({"domain": name, "output": result.output, "success": True})
    return outputs


def run_all_extractors(state: TranslationState) -> list:
    return asyncio.run(run_all_extractors_async(state))
