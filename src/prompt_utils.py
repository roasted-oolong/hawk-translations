"""
src/prompt_utils.py
-------------------
Shared utilities for assembling prompts from bible file content.

Used by both src/prompt_builder.py (translation) and
src/preread/prompt_builder.py (preread). Centralised here so changes to
empty-detection or section formatting only need to be made once.
"""

# Strings that indicate a bible file contains only its blank template.
# Sections matching any of these are omitted from prompts.
_EMPTY_MARKERS = [
    "[Character Name",
    "[Term —",
    "[Phrase —",
    "[Location Name",
    "Current summary: \n- Key turning points:",
]


def is_empty(content: str) -> bool:
    """
    Return True if bible file content is blank or contains only template text.

    An empty string is also treated as empty.
    """
    if not content or not content.strip():
        return True
    return any(marker in content for marker in _EMPTY_MARKERS)


def section(heading: str, content: str) -> str:
    """
    Format a single prompt section with a heading and its content.

    Returns an empty string if the content is empty or unpopulated, so the
    caller can safely join all sections without worrying about blank entries.
    """
    if is_empty(content):
        return ""
    return f"## {heading}\n\n{content.strip()}\n"
