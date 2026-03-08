"""
src/prompt_builder.py
---------------------
Responsible for one thing: assembling the system prompt that the translation
agent receives.

This module has no knowledge of the Anthropic API, file paths, or pipeline
orchestration. It receives a TranslationContext dataclass and returns a
formatted string. All API knowledge lives in agent.py. All file I/O lives
in translate.py.

To change what the translation agent is told — instructions, section order,
how bible files are presented — edit only this file. Nothing else needs to
change.

To add a new reference file to the prompt:
  1. Add a field to TranslationContext.
  2. Add a section for it in build_translation_prompt().
  3. Populate the field in translate.py when building the context.
"""

from dataclasses import dataclass


# ---------------------------------------------------------------------------
# Context type
# ---------------------------------------------------------------------------

@dataclass
class TranslationContext:
    """
    All reference material the translation agent needs to do its job.

    Each field is a string containing the full contents of a reference file.
    Fields may be empty strings if the file has not been populated yet —
    build_translation_prompt() handles empty fields gracefully by omitting
    those sections from the prompt rather than sending blank template text.

    Fields
    ------
    novel_info : str
        Contents of novel_info.md. Genre, tone, POV, narrative style.
    translation_guidelines : str
        Contents of translation_guidelines.md. Phase 1, 2, and 3 rules.
    characters : str
        Contents of characters.md. Character profiles and speech patterns.
    cultural_phrases : str
        Contents of cultural_phrases.md. Established cultural translations.
    locations : str
        Contents of locations.md. Established location references.
    story : str
        Contents of story.md. Narrative context and watch list.
    narrator_note : str
        Narrator-specific instruction for the model, drawn from the
        ## Narrator Note section of novel_info.md. Injected into the prompt
        only if populated. Empty string if the novel has no named narrator
        or no voice calibration file.
    terminology : str
        Contents of terminology.md. Established term translations.
    voice_calibration : str
        Contents of voice_calibration.md. Annotated passages for narrator
        voice calibration.
    """

    novel_info: str
    translation_guidelines: str
    narrator_note: str
    characters: str
    cultural_phrases: str
    locations: str
    story: str
    terminology: str
    voice_calibration: str


# ---------------------------------------------------------------------------
# Prompt assembly
# ---------------------------------------------------------------------------

# Strings that indicate a bible file contains only its blank template.
# Sections matching any of these are omitted from the prompt.
_EMPTY_MARKERS = [
    "[Character Name",
    "[Term —",
    "[Phrase —",
    "[Location Name",
    "Current summary: \n- Key turning points:",
]


def _is_empty(content: str) -> bool:
    """
    Return True if a bible file contains only blank template content.

    Checks for known placeholder strings that indicate the file has not been
    populated yet. An empty string is also treated as empty.
    """
    if not content or not content.strip():
        return True
    return any(marker in content for marker in _EMPTY_MARKERS)


def _section(heading: str, content: str) -> str:
    """
    Format a single prompt section with a heading and its content.

    Returns an empty string if the content is empty or unpopulated, so the
    caller can safely join all sections without worrying about blank entries.
    """
    if _is_empty(content):
        return ""
    return f"## {heading}\n\n{content.strip()}\n"


def build_translation_prompt(context: TranslationContext) -> str:
    """
    Assemble the full system prompt from a TranslationContext.

    Sections are included only if their content is non-empty and not a blank
    template. The prompt is structured so the model receives:
      1. Its role and the task description
      2. Novel-level context (info, guidelines, voice calibration)
      3. Bible reference files (characters, phrases, locations, story, terms)
      4. Explicit instructions for what to produce

    Parameters
    ----------
    context : TranslationContext
        All reference material for this novel and chapter.

    Returns
    -------
    str
        The complete system prompt, ready to pass to agent.call().
    """

    # Build each reference section, skipping unpopulated files.
    reference_sections = [
        _section("Novel Info", context.novel_info),
        _section("Translation Guidelines", context.translation_guidelines),
        _section("Voice Calibration", context.voice_calibration),
        _section("Narrator Note", context.narrator_note),
        _section("Character Bible", context.characters),
        _section("Cultural Phrases", context.cultural_phrases),
        _section("Locations", context.locations),
        _section("Story Bible", context.story),
        _section("Terminology", context.terminology),
    ]

    # Join non-empty sections with a divider between them.
    references = "\n---\n\n".join(s for s in reference_sections if s)

    return f"""You are a professional Korean-to-English literary translator \
working on a novel intended for potential publishing. Quality is the top \
priority — take your time and never rush.

Your sole task in this call is to translate the Korean chapter provided in \
the user message into English. Follow the Translation Guidelines exactly. \
Use the reference material below to ensure consistency with established \
character names, speech patterns, terminology, cultural phrases, and \
narrative voice.

Produce the complete translated chapter. Do not summarize, skip sections, or \
add commentary outside the translation itself. Flag any term you cannot \
resolve with: [원래 한국어 / proposed translation?]

---

# Reference Material

{references}"""
