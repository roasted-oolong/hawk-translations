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
Novel and chapter resolution lives in src/novel_resolver.py.
Configuration lives in config.py.
This file does not make decisions about translation — it connects the pieces.
"""

import re
import sys
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path

from dotenv import load_dotenv

load_dotenv()

sys.path.insert(0, str(Path(__file__).parent))

from config import PROJECT_ROOT, NOVEL_FILES
from src.agent import call, make_client
from src.novel_resolver import resolve_novel, find_next_chapter, extract_chapter_number
from src.prompt_builder import TranslationContext, build_translation_prompt


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


def resolve_reference_paths(novel_dir: Path) -> dict[str, Path]:
    """
    Build the mapping of TranslationContext field name → absolute file path.

    Path construction is driven entirely by config.NOVEL_FILES so there is
    a single source of truth for which files exist and where they live.

    Parameters
    ----------
    novel_dir : Path
        The root directory of the selected novel.

    Returns
    -------
    dict[str, Path]
        Keys match TranslationContext field names. Values are absolute paths.
    """
    bible_dir = novel_dir / "bible"
    return {
        key: (novel_dir if location == "novel" else bible_dir) / filename
        for key, (filename, location) in NOVEL_FILES.items()
    }


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
    reference_paths = resolve_reference_paths(novel_dir)

    results = {}
    with ThreadPoolExecutor() as executor:
        futures = {
            executor.submit(_read_file, path): key
            for key, path in reference_paths.items()
        }
        for future in as_completed(futures):
            key = futures[future]
            results[key] = future.result()

    return results


# ---------------------------------------------------------------------------
# Output file handling
# ---------------------------------------------------------------------------

def derive_output_filename(korean_file: Path) -> str:
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
    client = make_client()
    translated_text = call(
        system_prompt=system_prompt,
        user_message=korean_text,
        client=client,
    )
    print("  ✓ Translation complete.")

    # ── Step 6: Review and write ──────────────────────────────────
    print("\n" + "─" * 60)
    print(translated_text)
    print("─" * 60)

    output_filename = derive_output_filename(korean_file)
    output_path = chapters_dir / output_filename
    write_output(output_path, translated_text)


if __name__ == "__main__":
    run()
