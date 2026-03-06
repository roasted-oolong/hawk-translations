"""Context builder — assembles targeted system prompts per step."""

from pathlib import Path
from typing import Optional
from ...config import CACHE_TYPE


def read_file(path) -> str:
    try:
        return Path(path).read_text(encoding="utf-8")
    except FileNotFoundError:
        return ""


def build_system(
    novel_info: str,
    guidelines: str,
    *,
    characters: Optional[str] = None,
    terminology: Optional[str] = None,
    cultural_phrases: Optional[str] = None,
    locations: Optional[str] = None,
    story: Optional[str] = None,
    extra: Optional[str] = None,
    cache_stable: bool = True,
) -> list:
    """
    Build a scoped system prompt. Only include what the step actually needs.

    novel_info + guidelines are always included and cached if cache_stable=True.
    Bible sections are included only when explicitly passed.
    """

    stable = (
        "You are a professional Korean-to-English literary translator "
        "working on novels intended for potential publishing. "
        "Quality is the top priority — never rush.\n\n"
        f"## NOVEL INFO\n{novel_info}\n\n"
        f"## TRANSLATION GUIDELINES\n{guidelines}"
    )

    parts = []

    if cache_stable:
        parts.append({
            "type": "text",
            "text": stable,
            "cache_control": {"type": CACHE_TYPE},
        })
    else:
        parts.append({"type": "text", "text": stable})

    # Bible sections — only what was passed
    bible_sections = []
    if characters:
        bible_sections.append(f"=== CHARACTERS ===\n{characters}")
    if terminology:
        bible_sections.append(f"=== TERMINOLOGY ===\n{terminology}")
    if cultural_phrases:
        bible_sections.append(f"=== CULTURAL PHRASES ===\n{cultural_phrases}")
    if locations:
        bible_sections.append(f"=== LOCATIONS ===\n{locations}")
    if story:
        bible_sections.append(f"=== STORY (current state + watch list) ===\n{story}")

    if bible_sections:
        parts.append({
            "type": "text",
            "text": "## STORY BIBLE\n\n" + "\n\n".join(bible_sections),
        })

    if extra:
        parts.append({"type": "text", "text": extra})

    return parts


def load_bible(novel_dir: str) -> dict:
    """Load all bible files from novel directory. Returns dict of {key: content}."""
    base = Path(novel_dir) / "bible"
    return {
        "characters":       read_file(base / "characters.md"),
        "terminology":      read_file(base / "terminology.md"),
        "cultural_phrases": read_file(base / "cultural_phrases.md"),
        "locations":        read_file(base / "locations.md"),
        "story":            read_file(base / "story.md"),
    }


def write_bible(novel_dir: str, key: str, content: str):
    """Write a single bible file."""
    path = Path(novel_dir) / "bible" / {
        "characters":       "characters.md",
        "terminology":      "terminology.md",
        "cultural_phrases": "cultural_phrases.md",
        "locations":        "locations.md",
        "story":            "story.md",
    }[key]
    path.write_text(content, encoding="utf-8")
