"""
translate.py
------------
Entry point for the Hawk Translations pipeline.

Run with:
    python translate.py [novel-name]

If no novel name is provided, the script will list available novels and
prompt for a selection. The novel name must match a subdirectory of the
project root that contains a chapters/ and bible/ directory.

This script is responsible for orchestration only:
  1. Resolve the novel directory
  2. Locate the next untranslated chapter
  3. Load all reference files from disk (in parallel)
  4. Build the translation context and system prompt
  5. Call the translation agent
  6. Present the output for review and write it to disk on confirmation

Domain logic lives in src/prompt_builder.py.
API logic lives in src/agent.py.
Configuration lives in config.py.
This file does not make decisions about translation — it connects the pieces.
"""

import re
import sys
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path

from dotenv import load_dotenv

load_dotenv()

# Ensure src/ is importable regardless of where the script is run from.
sys.path.insert(0, str(Path(__file__).parent))

from config import PROJECT_ROOT, NOVEL_FILES
from src.agent import call
from src.prompt_builder import TranslationContext, build_translation_prompt


# ---------------------------------------------------------------------------
# Novel resolution
# ---------------------------------------------------------------------------

def list_novels(project_root: Path) -> list[Path]:
    """
    Return all valid novel directories under the project root.

    A valid novel directory contains both a chapters/ and bible/ subdirectory.
    Template directories (prefixed with _) are excluded.
    """
    return sorted(
        d for d in project_root.iterdir()
        if d.is_dir()
        and not d.name.startswith("_")
        and not d.name.startswith(".")
        and (d / "chapters").is_dir()
        and (d / "bible").is_dir()
    )


def resolve_novel(project_root: Path, name: str | None) -> Path:
    """
    Resolve the novel directory from an optional name argument.

    If name is provided, match it against available novels (case-insensitive,
    partial match allowed). If no name is provided and only one novel exists,
    select it automatically. Otherwise prompt the user to choose.

    Parameters
    ----------
    project_root : Path
        Root of the translations project.
    name : str | None
        Novel name from CLI argument, or None if not provided.

    Returns
    -------
    Path
        The resolved novel directory.

    Raises
    ------
    SystemExit
        If no novels are found, or if the provided name is ambiguous or
        unrecognised.
    """
    novels = list_novels(project_root)

    if not novels:
        print("\n  [error] No novel directories found in project root.")
        sys.exit(1)

    if name:
        matches = [n for n in novels if name.lower() in n.name.lower()]
        if len(matches) == 1:
            return matches[0]
        if len(matches) > 1:
            print(f"\n  [error] '{name}' matches multiple novels:")
            for m in matches:
                print(f"    - {m.name}")
            sys.exit(1)
        print(f"\n  [error] No novel matching '{name}' found.")
        sys.exit(1)

    if len(novels) == 1:
        return novels[0]

    print("\n  Available novels:")
    for i, novel in enumerate(novels, 1):
        print(f"    {i}. {novel.name}")

    choice = input("\n  Select a novel (number or name):\n  > ").strip()

    if choice.isdigit():
        index = int(choice) - 1
        if 0 <= index < len(novels):
            return novels[index]
        print("\n  [error] Invalid selection.")
        sys.exit(1)

    matches = [n for n in novels if choice.lower() in n.name.lower()]
    if len(matches) == 1:
        return matches[0]

    print(f"\n  [error] No novel matching '{choice}' found.")
    sys.exit(1)


# ---------------------------------------------------------------------------
# Chapter discovery
# ---------------------------------------------------------------------------

def extract_chapter_number(filename: str) -> int:
    """Return the first integer found in a filename, or 0 if none."""
    match = re.search(r"(\d+)", filename)
    return int(match.group(1)) if match else 0


def find_next_chapter(chapters_dir: Path) -> Path | None:
    """
    Find the lowest-numbered Korean source file that has no corresponding
    translated output file in the chapters directory.

    A file is considered translated if a non-Korean, non-reference .txt file
    with the same chapter number exists in the same directory.

    Parameters
    ----------
    chapters_dir : Path
        The chapters directory for the selected novel.

    Returns
    -------
    Path | None
        Path to the next untranslated Korean file, or None if all are done.
    """
    korean_files = sorted(
        chapters_dir.glob("*korean*"),
        key=lambda f: extract_chapter_number(f.name),
    )

    translated_numbers = set()
    for f in chapters_dir.iterdir():
        if "korean" in f.name.lower():
            continue
        if "another translation" in f.name.lower():
            continue
        if f.suffix == ".txt":
            num = extract_chapter_number(f.name)
            if num:
                translated_numbers.add(num)

    for korean_file in korean_files:
        num = extract_chapter_number(korean_file.name)
        if num not in translated_numbers:
            return korean_file

    return None


# ---------------------------------------------------------------------------
# Reference file loading
# ---------------------------------------------------------------------------

def _extract_narrator_note(novel_info: str) -> str:
    """
    Extract the content of the ## Narrator Note section from novel_info.md.

    Returns an empty string if the section is absent or blank, so the prompt
    builder skips it cleanly for novels without a named narrator.
    """
    match = re.search(
        r"^## Narrator Note\s*\n(.*?)(?=^##|\Z)",
        novel_info,
        re.MULTILINE | re.DOTALL,
    )
    if not match:
        return ""
    return match.group(1).strip()


def _read_file(path: Path) -> str:
    """
    Read a single file and return its contents as a string.
    Returns an empty string if the file does not exist.
    """
    if not path.exists():
        print(f"  [warning] reference file not found: {path.name}")
        return ""
    return path.read_text(encoding="utf-8")


def load_reference_files(novel_dir: Path) -> dict[str, str]:
    """
    Load all reference files for a novel from disk in parallel.

    Parameters
    ----------
    novel_dir : Path
        The root directory of the selected novel.

    Returns
    -------
    dict[str, str]
        Keys match TranslationContext field names. Values are file contents.
    """
    bible_dir = novel_dir / "bible"

    reference_files = {
        key: (novel_dir if location == "novel" else bible_dir) / filename
        for key, (filename, location) in NOVEL_FILES.items()
    }

    results = {}
    with ThreadPoolExecutor() as executor:
        futures = {
            executor.submit(_read_file, path): key
            for key, path in reference_files.items()
        }
        for future in as_completed(futures):
            key = futures[future]
            results[key] = future.result()

    return results


# ---------------------------------------------------------------------------
# Output file handling
# ---------------------------------------------------------------------------

def derive_output_filename(korean_file: Path, translated_text: str) -> str:
    """
    Derive the output filename from the chapter number.

    Format: "Chapter {N}.txt"
    """
    chapter_num = extract_chapter_number(korean_file.name)
    return f"Chapter {chapter_num}.txt"


def write_output(output_path: Path, content: str) -> None:
    """Write the translated chapter to disk."""
    output_path.write_text(content, encoding="utf-8")
    print(f"\n  ✓ Written to: {output_path.name}")


# ---------------------------------------------------------------------------
# Main pipeline
# ---------------------------------------------------------------------------

def run() -> None:
    """
    Execute the translation pipeline for the next untranslated chapter.

    Steps:
      1. Resolve the novel directory.
      2. Locate the next untranslated chapter.
      3. Load all reference files in parallel.
      4. Build the TranslationContext and system prompt.
      5. Call the translation agent.
      6. Present the output, confirm, and write to disk.
    """

    print("\n" + "═" * 60)
    print("  HAWK TRANSLATIONS")
    print("═" * 60)

    # ── Step 1: Resolve novel ─────────────────────────────────────
    project_root = Path(PROJECT_ROOT)
    novel_name = sys.argv[1] if len(sys.argv) > 1 else None
    novel_dir = resolve_novel(project_root, novel_name)
    chapters_dir = novel_dir / "chapters"

    print(f"\n  Novel   : {novel_dir.name}")

    # ── Step 2: Find chapter ──────────────────────────────────────
    korean_file = find_next_chapter(chapters_dir)
    if not korean_file:
        print("\n  No untranslated chapters found. All done.\n")
        return

    print(f"  Chapter : {korean_file.name}")

    confirm = input("\n  Press ENTER to translate, or type a different "
                    "filename:\n  > ").strip()

    if confirm:
        alt = chapters_dir / confirm
        if not alt.exists():
            print(f"\n  [error] File not found: {confirm}")
            return
        korean_file = alt
        print(f"  Using: {korean_file.name}")

    korean_text = korean_file.read_text(encoding="utf-8")

    # ── Step 3: Load reference files ──────────────────────────────
    print("\n  Loading reference files...")
    reference_data = load_reference_files(novel_dir)
    print("  ✓ Reference files loaded.")

    # ── Step 4: Build prompt ──────────────────────────────────────
    narrator_note = _extract_narrator_note(reference_data["novel_info"])
    context = TranslationContext(**reference_data, narrator_note=narrator_note)
    system_prompt = build_translation_prompt(context)

    # ── Step 5: Translate ─────────────────────────────────────────
    print("\n  Translating — this will take a few minutes...")
    translated_text = call(
        system_prompt=system_prompt,
        user_message=korean_text,
    )
    print("  ✓ Translation complete.")

    # ── Step 6: Review and write ──────────────────────────────────
    print("\n" + "─" * 60)
    print(translated_text)
    print("─" * 60)

    output_filename = derive_output_filename(korean_file, translated_text)
    output_path = chapters_dir / output_filename
    write_output(output_path, translated_text)


if __name__ == "__main__":
    run()
