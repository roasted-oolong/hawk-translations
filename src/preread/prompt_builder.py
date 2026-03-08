"""
src/preread/prompt_builder.py
-----------------------------
Responsible for one thing: assembling the system prompt and user message
that the preread agent receives for a batch of chapters.

This module has no knowledge of the API, file I/O, or pipeline orchestration.
It receives plain strings and returns plain strings.

To change what the preread agent is told — recording depth rules, output
format, section order — edit only this file. Nothing else needs to change.
"""

from dataclasses import dataclass

from src.prompt_utils import section


# ---------------------------------------------------------------------------
# Context type
# ---------------------------------------------------------------------------

@dataclass
class PrereadContext:
    """
    All reference material and chapter content for one preread batch call.

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
    chapters : dict[int, str]
        Mapping of chapter number → full Korean text for this batch.
    today : str
        ISO date string (YYYY-MM-DD) for Last Updated fields.
    """
    novel_info: str
    characters: str
    cultural_phrases: str
    locations: str
    story: str
    terminology: str
    chapters: dict[int, str]
    today: str


# ---------------------------------------------------------------------------
# Template documentation (injected into system prompt)
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
Your role is PREREAD: read ahead through Korean source chapters to extract story intelligence
for a translation bible. You are NOT translating. You are reading for characters, locations,
terminology, cultural phrases, and story developments worth tracking.

This is orientation, not exhaustive documentation. Keep entries lean.

---

## Output Format

Respond with exactly five sections, each preceded by its exact header line.
If a section has nothing to add, write "NOTHING TO ADD" under it.
Do not include any text outside these five sections.

=== CHARACTERS ===
[entries here]

=== LOCATIONS ===
[entries here]

=== TERMINOLOGY ===
[entries here]

=== CULTURAL PHRASES ===
[entries here]

=== STORY ===
[updates here]

---

## Recording Rules

### CHARACTERS
- Named character with a meaningful role: full entry using the template below.
  Include every detail present — physical description, speech pattern, honorifics,
  relationships. Leave fields blank rather than guessing. Label [New] or [Edited].
- Unnamed but significant figure (meaningfully affects a named character's progression):
  minimal entry — role/description, first appearance chapter, one sentence on why they
  matter. Nothing more until they are named or have a more pivotal role.
- Background characters with no name and no significance: do not record.

Template:
{character_template}

### LOCATIONS
Record only what a translator needs to handle the location consistently:
- Korean name (if present)
- Romanisation decision — how the name should appear in English
- First appearance chapter
- One line on significance (why it matters to the story)

Do not record descriptions, atmosphere, or layout detail — that is not a translator's concern.
- Named location or unnamed location with translation complexity: record using the template.
- Unnamed location mentioned in passing with no translation complexity (e.g. "they went
  to a café"): do not record.
- Locations mentioned only as background with no bearing on events: do not record.

Template:
{location_template}

### TERMINOLOGY
- Any industry term, title, organization name, or concept specific to the Korean idol
  industry or to this story's world: record it. Include Korean term if present,
  definition, usage notes. Label [New] or [Edited].
- Common English words used in Korean context (e.g. "comeback", "debut"): record only
  if they carry a specific meaning in this story's world that differs from general usage.

Template:
{terminology_template}

### CULTURAL PHRASES
- Any idiom, proverb, honorific pattern, or culturally specific expression that cannot
  be directly translated without losing meaning: record it. Leave "Established translation"
  blank — that is set during translation. Label [New] or [Edited].

Template:
{cultural_phrase_template}

### STORY
Record only what a translator needs to not misread a scene:
- Open arcs: one sentence per arc describing what is currently in motion.
- Watch list: moments, details, or parallels that feel significant but whose importance
  is not yet clear. Flag anything that may affect how a future scene should be read.
- Translation-relevant context: note any place where knowing the story's actual stakes
  changes how a passage should be rendered (e.g. a speech that deliberately echoes an
  earlier scene, irony that only lands if the reader knows the prior timeline).

Do not write narrative summaries. The story section is a translator's reference, not
a plot recap. If it wouldn't change a translation decision, leave it out.
Do not draw conclusions about themes or motifs — flag them for watching only.

---

## Uncertainty

If you are unsure whether something meets the recording threshold, flag it:
[uncertain — included/excluded because ...]

---

## Date and Chapter Fields

- Set "Last Updated" to: {{today}}
- Set "First appearance" to the chapter number where the element first appears in THIS batch.
  If it was already in the bible, update "Last Updated" only if you are adding new information.
""".format(
    character_template=_CHARACTER_TEMPLATE,
    location_template=_LOCATION_TEMPLATE,
    terminology_template=_TERMINOLOGY_TEMPLATE,
    cultural_phrase_template=_CULTURAL_PHRASE_TEMPLATE,
)


# ---------------------------------------------------------------------------
# Public builder functions
# ---------------------------------------------------------------------------

def build_system_prompt(today: str) -> str:
    """
    Return the preread system prompt with the date filled in.

    Parameters
    ----------
    today : str
        ISO date string (YYYY-MM-DD).

    Returns
    -------
    str
        Complete system prompt for the preread agent.
    """
    return _SYSTEM_PROMPT.format(today=today)


def build_user_message(context: PrereadContext) -> str:
    """
    Assemble the user-turn message from novel context and batch chapters.

    The message includes:
    - Current state of all bible files (for deduplication and editing)
    - Novel info (genre, tone, setting)
    - Full text of each chapter in the batch

    Parameters
    ----------
    context : PrereadContext
        All reference material and chapter content for this batch.

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

    chapter_blocks = []
    for num in sorted(context.chapters.keys()):
        text = context.chapters[num]
        chapter_blocks.append(f"=== CHAPTER {num} ===\n\n{text.strip()}")
    chapters_text = "\n\n".join(chapter_blocks)

    return f"""\
# Reference Material (current bible state)

{references}

---

# Chapters to Read

{chapters_text}
"""
