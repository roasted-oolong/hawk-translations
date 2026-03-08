"""
src/voice_collaboration/calibration_writer.py
---------------------------------
Responsible for one thing: appending confirmed new pattern entries to
voice_calibration.md.

This module has no knowledge of the API, prompts, or response parsing.
It receives a content string and writes it to the correct file.
Nothing more.
"""

import re
from pathlib import Path

VOICE_CALIBRATION_PATH = "bible/voice_calibration.md"


def append_pattern(novel_dir: Path, content: str) -> None:
    """
    Append a new pattern entry to voice_calibration.md.

    Parameters
    ----------
    novel_dir : Path
        Root directory of the novel.
    content : str
        The fully formatted passage entry to append, as produced by the
        review agent and confirmed by the user.
    """
    file_path = novel_dir / VOICE_CALIBRATION_PATH

    if not file_path.exists():
        print(f"  [error] voice_calibration.md not found at {file_path}")
        return

    existing = file_path.read_text(encoding="utf-8")
    updated = existing.rstrip() + "\n\n---\n\n" + content.strip() + "\n"
    file_path.write_text(updated, encoding="utf-8")
    print(f"  ✓ Pattern appended to voice_calibration.md")


def remove_passage(novel_dir: Path, heading: str) -> bool:
    """
    Remove a passage entry from voice_calibration.md by its heading.

    Removes from the ## heading line through the next --- separator
    (or end of file). The preceding separator is also removed to avoid
    leaving orphaned dividers.

    Parameters
    ----------
    novel_dir : Path
        Root directory of the novel.
    heading : str
        The exact ## heading of the passage to remove (e.g.
        "Passage 3 — The reveal played completely flat").

    Returns
    -------
    bool
        True if the passage was found and removed, False if not found.
    """
    file_path = novel_dir / VOICE_CALIBRATION_PATH

    if not file_path.exists():
        print(f"  [error] voice_calibration.md not found at {file_path}")
        return False

    content = file_path.read_text(encoding="utf-8")

    # Match from the ## heading through the next --- divider (or end of file),
    # including the preceding --- divider if present.
    pattern = re.compile(
        r"(?:\n---\n\n)?## "
        + re.escape(heading.lstrip("# ").strip())
        + r".*?(?=\n---\n|\Z)",
        re.DOTALL,
    )

    updated, count = pattern.subn("", content)
    if count == 0:
        print(f"  [warning] Passage not found in file: '{heading}'")
        return False

    # Clean up any double blank lines left behind.
    updated = re.sub(r"\n{3,}", "\n\n", updated).rstrip() + "\n"
    file_path.write_text(updated, encoding="utf-8")
    print(f"  ✓ Passage removed from voice_calibration.md: '{heading}'")
    return True
