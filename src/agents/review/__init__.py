"""Review agents — four parallel reviewers."""

import asyncio
from ..base import call_claude, AgentResult
from ...context import build_context
from ...state import TranslationState
from config import SONNET_MODEL, OPUS_MODEL


def run_consistency_reviewer(state: TranslationState, translation: str) -> AgentResult:
    system = build_context("consistency_reviewer", state)
    prompt = (
        "Review this translation for consistency against the story bible.\n\n"
        "Check:\n"
        "- All character names, titles, and address forms match characters.md\n"
        "- All terminology matches established translations in terminology.md\n"
        "- Cultural phrases handled consistently with cultural_phrases.md\n\n"
        "List every inconsistency found with the correct form and line reference.\n"
        "If none, say so clearly.\n\n"
        f"TRANSLATION:\n{translation}"
    )
    return call_claude(
        agent_name="consistency_reviewer",
        model=SONNET_MODEL,
        system_parts=system,
        user_message=prompt,
        label="Consistency review (Sonnet)",
    )


def run_tone_reviewer(state: TranslationState, translation: str) -> AgentResult:
    system = build_context("tone_reviewer", state)
    prompt = (
        "Review this translation for tone and register accuracy.\n\n"
        "Check:\n"
        "- Narration voice matches the novel's established tone "
        "(dry, introspective, lightly self-deprecating)\n"
        "- Dialogue feels authentic to each character's established speech pattern\n"
        "- No section drifts toward melodrama, over-explanation, or unearned sentiment\n"
        "- Emotional peaks land — check chapter closes and key beats specifically\n\n"
        "List every issue with the passage and recommended fix. "
        "If none, say so clearly.\n\n"
        f"TRANSLATION:\n{translation}"
    )
    return call_claude(
        agent_name="tone_reviewer",
        model=SONNET_MODEL,
        system_parts=system,
        user_message=prompt,
        label="Tone review (Sonnet)",
    )


def run_formatting_reviewer(state: TranslationState, translation: str) -> AgentResult:
    system = build_context("formatting_reviewer", state)
    prompt = (
        "Review this translation for formatting rule adherence.\n\n"
        "Check:\n"
        "- No long dashes (—) anywhere\n"
        "- No colons (:) used as punctuation mid-sentence\n"
        "- All narration in past tense\n"
        "- Paragraph breaks and pacing match source structure\n"
        "- T/N notes formatted correctly: *(T/N: ...)* on its own line, "
        "first appearance only\n"
        "- Internal monologue italics applied consistently\n\n"
        "List every violation with the line and required fix. "
        "If none, say so clearly.\n\n"
        f"TRANSLATION:\n{translation}"
    )
    return call_claude(
        agent_name="formatting_reviewer",
        model=SONNET_MODEL,
        system_parts=system,
        user_message=prompt,
        label="Formatting review (Sonnet)",
    )


def run_voice_reviewer(state: TranslationState, translation: str) -> AgentResult:
    system = build_context("voice_reviewer", state)
    prompt = (
        "Review this translation specifically for narrative voice and interiority.\n\n"
        "Check:\n"
        "- Does the narrator's thinking-on-the-page quality survive? "
        "(rhetorical questions, self-corrections, reasoning chains that build out loud)\n"
        "- Have introspective passages been collapsed into clean declarative "
        "statements, losing the character's voice?\n"
        "- Do chapter-closing lines and emotional peaks land with the narrator's "
        "full interiority — not just the conclusion?\n"
        "- Are standalone beats given the space they need, or buried mid-sentence?\n\n"
        "For each issue: quote the passage, explain what was lost, suggest a rewrite.\n"
        "If none, say so clearly.\n\n"
        f"TRANSLATION:\n{translation}"
    )
    return call_claude(
        agent_name="voice_reviewer",
        model=OPUS_MODEL,
        system_parts=system,
        user_message=prompt,
        label="Voice review (Opus)",
    )


async def run_all_reviewers_async(state: TranslationState, translation: str) -> list:
    loop = asyncio.get_event_loop()
    tasks = [
        loop.run_in_executor(None, run_consistency_reviewer, state, translation),
        loop.run_in_executor(None, run_tone_reviewer, state, translation),
        loop.run_in_executor(None, run_formatting_reviewer, state, translation),
        loop.run_in_executor(None, run_voice_reviewer, state, translation),
    ]
    names = ["consistency", "tone", "formatting", "voice"]
    results = await asyncio.gather(*tasks, return_exceptions=True)

    outputs = []
    for i, result in enumerate(results):
        name = names[i]
        if isinstance(result, Exception):
            print(f"  FAILED: {name} — {result}")
            outputs.append({"reviewer": name, "output": None, "success": False, "error": str(result)})
        elif not result.success:
            print(f"  FAILED: {name} — {result.error}")
            outputs.append({"reviewer": name, "output": None, "success": False, "error": result.error})
        else:
            print(f"  DONE:   {name} ({result.execution_time_ms / 1000:.1f}s)")
            outputs.append({"reviewer": name, "output": result.output, "success": True})
    return outputs


def run_all_reviewers(state: TranslationState, translation: str) -> list:
    return asyncio.run(run_all_reviewers_async(state, translation))
