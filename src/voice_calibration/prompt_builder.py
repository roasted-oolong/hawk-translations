"""
src/voice_calibration/prompt_builder.py
----------------------------
Responsible for one thing: assembling the system prompt and user message
for the voice review agent.

This module has no knowledge of the API, file I/O, or pipeline orchestration.
It receives plain strings and returns plain strings.

To change what the review agent looks for or how it formats its output,
edit only this file. Nothing else needs to change.
"""

from dataclasses import dataclass

from src.prompt_utils import section


# ---------------------------------------------------------------------------
# Context type
# ---------------------------------------------------------------------------

@dataclass
class ReviewContext:
    """
    All content the voice review agent needs for one review call.

    Fields
    ------
    voice_calibration : str
        Current contents of voice_calibration.md.
    translated_chapter : str
        Full text of the edited, translated chapter to review.
    chapter_num : int
        Chapter number (for display and attribution in output).
    """
    voice_calibration: str
    translated_chapter: str
    chapter_num: int


# ---------------------------------------------------------------------------
# System prompt
# ---------------------------------------------------------------------------

_SYSTEM_PROMPT = """\
You are a voice calibration reviewer for a Korean-to-English novel translation project.

Your job is to read a completed, edited translation and compare it against the Voice
Calibration document. You are looking for two things:

1. NEW PATTERNS — failure modes visible in this translation that are NOT yet covered
   by any passage or rule in the Voice Calibration document. These are candidates to be
   added as new calibration entries.

2. RETIREMENTS — existing passages in the Voice Calibration document that have become
   redundant and should be removed. A passage is a retirement candidate if:
   - A new pattern you are proposing covers the same rule more clearly or completely
   - The passage describes a failure mode that no longer appears in translations,
     suggesting the rule has been fully absorbed
   - Two existing passages cover the same rule and one is strictly weaker
   Do not propose retirements unless the case is clear. When in doubt, leave it.

---

## What you are NOT doing

- You are not rewriting the translation.
- You are not grading the translation.
- You are not flagging or commenting on drift in this specific chapter.
- You are not commenting on word choice, phrasing accuracy, or cultural decisions.
- You are not adding passages that duplicate existing calibration rules — even partially.
  If the Voice Calibration document already covers the failure mode, do not include it
  as a New Pattern.

---

## Output Format

Respond with exactly two sections, each preceded by its exact header line.
If a section has nothing to report, write "NOTHING TO REPORT" under it.
Do not include any text outside these two sections.

=== NEW PATTERNS ===
[entries here]

=== RETIREMENTS ===
[entries here]

---

## New Patterns Format

Only include a pattern if it represents a failure mode that:
- Appears in this translation
- Is NOT already covered by any existing passage or Non-Negotiable in the
  Voice Calibration document
- Would genuinely help a future model avoid the same mistake

For each new pattern, provide a complete, ready-to-insert passage entry
in the exact format used in the Voice Calibration document:

## Passage [N] — [descriptive title]
*Chapter [number]*

> [the passage from the translation that illustrates the pattern]

**What it demonstrates:** [what this passage shows about the narrator's voice]

**What the wrong version looks like:** [what a model without calibration would write]

**The rule it demonstrates:** [one sentence, stated as a principle]

---

Limit to 2 new patterns maximum. If there are no new patterns, write "NOTHING TO REPORT".

---

## Retirements Format

For each retirement candidate, provide:

**Retirement candidate — [exact passage heading from Voice Calibration]**

Reason: [one sentence explaining why this passage is now redundant]
Superseded by: ["New Pattern N above" or "already covered by [existing passage heading]"]

---

Limit to 2 retirement candidates maximum. If there are none, write "NOTHING TO REPORT".
"""


# ---------------------------------------------------------------------------
# Public builder functions
# ---------------------------------------------------------------------------

def build_system_prompt() -> str:
    """Return the voice review system prompt."""
    return _SYSTEM_PROMPT


def build_user_message(context: ReviewContext) -> str:
    """
    Assemble the user-turn message from the voice calibration document
    and the translated chapter to review.

    Parameters
    ----------
    context : ReviewContext
        Voice calibration content and translated chapter text.

    Returns
    -------
    str
        The user message to send to the API.
    """
    calibration_section = section("Voice Calibration", context.voice_calibration)

    return f"""\
# Reference Material

{calibration_section}

---

# Chapter {context.chapter_num} — Translated Text

{context.translated_chapter.strip()}
"""
