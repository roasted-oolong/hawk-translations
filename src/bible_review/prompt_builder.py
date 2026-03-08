"""
src/bible_review/prompt_builder.py
------------------------------------
Responsible for one thing: assembling the system prompt and user message
that the bible review agent receives for a single translated chapter.

This module has no knowledge of the API, file I/O, or pipeline orchestration.
It receives plain strings and returns plain strings.

To change recording rules, output format, or section order, edit only this
file. Nothing else needs to change.
"""

from dataclasses import dataclass

from src.prompt_utils import section


# ---------------------------------------------------------------------------
# Context type
# ---------------------------------------------------------------------------

@dataclass
class ReviewContext:
    """
    All reference material and chapter content for one bible review call.

    Fields
    ------
    novel_info : str
        Contents of novel_info.md.
    characters : str
        Current contents of bible/characters.md.
    cultural_phrases : str
        Current contents of bible/cultural_phrases.md.
    locations : str
        Current contents of bible/locations.md.
    story : str
        Current contents of bible/story.md.
    terminology : str
        Current contents of bible/terminology.md.
    translated_chapter : str
        Full text of the translated .txt chapter being reviewed.
    chapter_num : int
        Chapter number being reviewed (for First appearance fields).
    today : str
        ISO date string (YYYY-MM-DD) for Last Updated fields.
    """
    novel_info: str
    characters: str
    cultural_phrases: str
    locations: str
    story: str
    terminology: str
    translated_chapter: str
    chapter_num: int
    today: str


# ---------------------------------------------------------------------------
# Bible entry templates
# ---------------------------------------------------------------------------

_CHARACTER_TEMPLATE = """## [Character Name — English]
- Korean name: 
- Aliases/Titles: 
- First appearance: [chapter number]
- Last Updated: [date]
- Role: 
- Physical description: 
- Speech pattern: 
- Dialogue cues: 
- Honorifics used toward them: 
- Honorifics they use toward others: 
- Relationships: 
- Story bible reference: 
- Notes: """

_LOCATION_TEMPLATE = """## [Location Name — English]
- Korean name: 
- Romanisation: 
- First appearance: [chapter number]
- Last Updated: [date]
- Significance: """

_TERMINOLOGY_TEMPLATE = """## [Term — English]
- Korean term: 
- Category: [title, organization, ability, item, concept, etc.]
- First appearance: [chapter number]
- Last Updated: [date]
- Definition: 
- Usage notes: 
- Story bible reference: 
- Notes: """

_CULTURAL_PHRASE_TEMPLATE = """## [Phrase — English or descriptive label]
- Korean phrase: 
- Literal translation: 
- Intended meaning: 
- Context: [when/how it's used]
- Established translation: 
- T/N written: [yes/no]
- T/N text: 
- First appearance: [chapter number]
- Last Updated: [date]
- Notes: """


# ---------------------------------------------------------------------------
# System prompt
# ---------------------------------------------------------------------------

_SYSTEM_PROMPT = """\
You are a literary assistant supporting a Korean-to-English novel translation project.
Your role is POST-TRANSLATION BIBLE REVIEW: read the translated chapter and update
the story bible with anything worth recording.

This function is about the bible only. Do NOT comment on word choice, phrasing, voice,
or translation accuracy — that is handled elsewhere. If you notice what looks like a
translation error, flag it with [translation note: ...] at the end of the relevant
entry, but do not rewrite or evaluate it.

---

## Output Format

Respond with exactly three sections, each preceded by its exact header line.
If a section has nothing to report, write "NOTHING TO ADD" under it.
Do not include any text outside these three sections.

=== NEW ENTRIES ===
[New bible entries grouped under file-label headers, using the templates below.
Each file-label header uses the format: ### characters.md]

=== PROPOSED EDITS ===
[One block per proposed change to an existing entry, in the format below.]

=== STORY UPDATES ===
[One block per story update, in the format below.]

---

## Recording Rules

### characters.md
- Named character not yet in the bible with a meaningful role: full entry using
  the template. Include every detail present — physical description, speech pattern,
  honorifics, relationships. Leave fields blank rather than guessing. Label [New].
- Unnamed but significant figure (meaningfully affects a named character's progression):
  minimal entry — role/description, first appearance chapter, one sentence on why they
  matter. Nothing more until they are named or have a more pivotal role.
- Background characters with no name and no significance: do not record.

Template:
{character_template}

### locations.md
- Named location or unnamed location with translation complexity (Korean name,
  romanisation decision): full entry using the template.
- Unnamed location mentioned in passing with no translation complexity: do not record.
- Background locations with no bearing on events: do not record.

Template:
{location_template}

### terminology.md
- Any industry term, title, organization name, or concept specific to the Korean idol
  industry or this story's world: record it. Include Korean term if present, definition,
  usage notes. Label [New].
- Common English words used in Korean context: record only if they carry a meaning
  specific to this story that differs from general usage.

Template:
{terminology_template}

### cultural_phrases.md
- Any idiom, proverb, honorific pattern, or culturally specific expression that cannot
  be directly translated without losing meaning: record it. If the translation has
  established an English rendering, fill in "Established translation". Label [New].

Template:
{cultural_phrase_template}

---

## New Entries Format

Group all new entries under file-label headers so the parser can route them correctly:

### characters.md
## [Entry heading]
...

### locations.md
## [Entry heading]
...

(and so on for terminology.md, cultural_phrases.md)

---

## Proposed Edits Format

For each proposed change to an existing entry, write one block in this exact format:

ENTRY: [exact ## heading of the existing entry]
FILE: [characters / locations / terminology / cultural_phrases / story]
CURRENT: [the specific field or line exactly as it currently reads]
PROPOSED: [exactly what you would change it to]
REASON: [one sentence]

One block per field. Separate blocks with a blank line.
Do not bundle multiple fields into one block.
Do not propose edits silently — every change to an existing entry must appear here.

If a name in the translation differs from a name already in the bible (different
romanisation or English rendering), flag it as a proposed edit rather than writing
the new form silently.

---

## Story Updates Format

For each story update, write one block:

TYPE: [Main Plot / Subplot / Watch List / Themes & Motifs]
UPDATE: [the content to add]

- Main Plot: update only if a significant turning point occurred.
- Subplots: add or update any story thread that opened or advanced.
- Watch List: any moment or detail that feels significant but whose importance
  is not yet clear.
- Themes & Motifs: any theme confirmed or advanced by this chapter.

---

## Uncertainty

If unsure whether something meets the recording threshold, flag it:
[uncertain — included/excluded because ...]

---

## Date and Chapter Fields

- Set "Last Updated" to: {{today}}
- Set "First appearance" to: {{chapter_num}}
""".format(
    character_template=_CHARACTER_TEMPLATE,
    location_template=_LOCATION_TEMPLATE,
    terminology_template=_TERMINOLOGY_TEMPLATE,
    cultural_phrase_template=_CULTURAL_PHRASE_TEMPLATE,
)


# ---------------------------------------------------------------------------
# Public builder functions
# ---------------------------------------------------------------------------

def build_system_prompt(today: str, chapter_num: int) -> str:
    """
    Return the bible review system prompt with date and chapter number filled in.

    Parameters
    ----------
    today : str
        ISO date string (YYYY-MM-DD).
    chapter_num : int
        Chapter number being reviewed.
    """
    return _SYSTEM_PROMPT.format(today=today, chapter_num=chapter_num)


def build_user_message(context: ReviewContext) -> str:
    """
    Assemble the user-turn message from bible state and the translated chapter.

    Parameters
    ----------
    context : ReviewContext
        All reference material and translated chapter content.

    Returns
    -------
    str
        The user message to send to the API.
    """
    reference_sections = [
        section("Novel Info", context.novel_info),
        section("Current Characters Bible", context.characters),
        section("Current Locations Bible", context.locations),
        section("Current Terminology Bible", context.terminology),
        section("Current Cultural Phrases Bible", context.cultural_phrases),
        section("Current Story Bible", context.story),
    ]
    references = "\n---\n\n".join(s for s in reference_sections if s)

    return f"""\
# Reference Material (current bible state)

{references}

---

# Translated Chapter {context.chapter_num}

{context.translated_chapter.strip()}
"""
