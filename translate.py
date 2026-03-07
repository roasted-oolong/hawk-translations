#!/usr/bin/env python3
"""
Hawk Translations — Interactive Console
Run `python translate.py` to enter the REPL.
Each command runs a workflow stage against the current novel/chapter.
State persists across commands within a session.
"""

import os
import re
import sys
from pathlib import Path
from dotenv import load_dotenv

# ── Path setup ────────────────────────────────────────────────────────────────
sys.path.insert(0, str(Path(__file__).parent))

from config import PROJECT_ROOT
from src.state import TranslationState, create_initial_state

load_dotenv()
if not os.getenv("ANTHROPIC_API_KEY"):
    print("\n[ERROR] No ANTHROPIC_API_KEY found in .env file.")
    print("See README.md for setup instructions.\n")
    sys.exit(1)


# ── Novel & chapter discovery ─────────────────────────────────────────────────

def find_all_novels(project_root: str) -> list[Path]:
    root = Path(project_root)
    novels = []
    for entry in sorted(root.iterdir()):
        if not entry.is_dir() or entry.name.startswith((".", "_", "src")):
            continue
        if (entry / "novel_info.md").exists():
            novels.append(entry)
        else:
            for sub in sorted(entry.iterdir()):
                if sub.is_dir() and (sub / "novel_info.md").exists():
                    novels.append(sub)
    return novels


def extract_chapter_number(filename: str) -> int:
    match = re.search(r"(\d+)", filename)
    return int(match.group(1)) if match else 0


def find_next_chapter(novel_dir: Path) -> Path | None:
    chapters_dir = novel_dir / "chapters"
    if not chapters_dir.exists():
        return None

    korean_files = sorted(
        chapters_dir.glob("*korean*"),
        key=lambda f: extract_chapter_number(f.name)
    )

    translated_nums = set()
    for f in chapters_dir.iterdir():
        if "korean" in f.name.lower():
            continue
        if "another translation" in f.name.lower() or "another_translation" in f.name.lower():
            continue
        if f.suffix in (".txt", ".md"):
            num = extract_chapter_number(f.name)
            if num:
                translated_nums.add(num)

    for kf in korean_files:
        num = extract_chapter_number(kf.name)
        if num not in translated_nums:
            return kf
    return None


def select_novel(project_root: str) -> Path:
    novels = find_all_novels(project_root)
    if not novels:
        print(f"\n[ERROR] No novel directories found under: {project_root}\n")
        sys.exit(1)

    print("\nAvailable novels:")
    for i, novel in enumerate(novels, 1):
        print(f"  {i}. {novel.name}")
    print()

    while True:
        choice = input("> Which novel? (enter number or name):\n> ").strip()
        if not choice:
            continue
        if choice.isdigit():
            idx = int(choice) - 1
            if 0 <= idx < len(novels):
                return novels[idx]
            print(f"  (Enter a number between 1 and {len(novels)}.)")
        else:
            matches = [n for n in novels if choice.lower() in n.name.lower()]
            if len(matches) == 1:
                return matches[0]
            elif len(matches) > 1:
                print(f"  Ambiguous — matched: {', '.join(m.name for m in matches)}")
            else:
                print(f"  No match for '{choice}'. Try again.")


def select_chapter(novel_dir: Path) -> Path:
    next_chapter = find_next_chapter(novel_dir)

    print()
    if next_chapter:
        print(f"  Novel  : {novel_dir.name}")
        print(f"  Chapter: {next_chapter.name}  →  next untranslated")
    else:
        print(f"  Novel  : {novel_dir.name}")
        print(f"  (No untranslated chapters detected.)")

    print()
    print("─" * 70)
    print("  Press ENTER to confirm, or type a different chapter filename:")
    print("─" * 70)

    while True:
        response = input("\n> ").strip()
        if response == "":
            if next_chapter:
                return next_chapter
            print("  No chapter auto-detected. Please enter a filename.")
        else:
            alt = novel_dir / "chapters" / response
            if alt.exists():
                print(f"  ✓ Using: {alt.name}")
                return alt
            print(f"  [ERROR] File not found: {response}")


# ── Stage runners (thin wrappers that mutate session state) ───────────────────

def run_stage_init(session: dict) -> bool:
    """Load all reference files into state. Always runs first."""
    from src.workflow.nodes import init_node
    updates = init_node(session["state"])
    session["state"].update(updates)
    session["completed"].add("init")
    return True


def run_stage_format(session: dict) -> bool:
    """Step 2 + Step 7: format Korean + create output file."""
    if "init" not in session["completed"]:
        run_stage_init(session)

    from src.workflow.nodes import prep_node
    updates = prep_node(session["state"])
    session["state"].update(updates)

    if updates.get("current_stage") == "failed":
        print(f"\n  [FAILED] {updates.get('errors', ['unknown error'])}")
        return False

    session["completed"].add("format")
    return True


def _require_korean_text(session: dict, stage: str) -> bool:
    """Refuse to run if korean_text is not loaded into state yet."""
    if not session["state"].get("korean_text", "").strip():
        print(f"  [ERROR] No Korean text loaded. Run 'format' first before '{stage}'.")
        return False
    return True


def run_stage_extract(session: dict) -> bool:
    """Stage 2: bible extraction + user checkpoint + write."""
    if not _require_korean_text(session, "extract"):
        return False
    from src.workflow.nodes import bible_extract_node, bible_write_node
    from src.workflow.routing import after_bible_extract

    updates = bible_extract_node(session["state"])
    session["state"].update(updates)

    if updates.get("current_stage") == "failed":
        print(f"\n  [FAILED] {updates.get('errors', ['unknown error'])}")
        return False

    next_node = after_bible_extract(session["state"])
    if next_node == "failed":
        return False

    updates = bible_write_node(session["state"])
    session["state"].update(updates)

    session["completed"].add("extract")
    return True


def run_stage_translate(session: dict) -> bool:
    """Stage 3: Phase 1 + Phase 2 translation."""
    if not _require_korean_text(session, "translate"):
        return False
    from src.workflow.nodes import translate_node
    updates = translate_node(session["state"])
    session["state"].update(updates)

    if updates.get("current_stage") == "failed":
        print(f"\n  [FAILED] {updates.get('errors', ['unknown error'])}")
        return False

    session["completed"].add("translate")
    return True


def run_stage_review(session: dict) -> bool:
    """Stage 4: review + checkpoint + apply corrections."""
    from src.workflow.nodes import review_node
    from src.workflow.routing import after_review

    updates = review_node(session["state"])
    session["state"].update(updates)

    if updates.get("current_stage") == "failed":
        print(f"\n  [FAILED] {updates.get('errors', ['unknown error'])}")
        return False

    next_node = after_review(session["state"])
    if next_node == "failed":
        return False

    session["completed"].add("review")
    return True


def run_stage_step11(session: dict) -> bool:
    """Step 11: post-translation bible updates + checkpoint + write."""
    from src.workflow.nodes import step11_node
    from src.workflow.routing import after_step11

    updates = step11_node(session["state"])
    session["state"].update(updates)

    if updates.get("current_stage") == "failed":
        print(f"\n  [FAILED] {updates.get('errors', ['unknown error'])}")
        return False

    next_node = after_step11(session["state"])
    if next_node == "failed":
        return False

    session["completed"].add("step11")
    return True


def run_stage_audit(session: dict) -> bool:
    """Stage 5: Phase 3 dash audit."""
    from src.workflow.nodes import audit_node
    updates = audit_node(session["state"])
    session["state"].update(updates)

    if updates.get("current_stage") == "failed":
        print(f"\n  [FAILED] {updates.get('errors', ['unknown error'])}")
        return False

    session["completed"].add("audit")
    return True


# ── REPL ──────────────────────────────────────────────────────────────────────

HELP_TEXT = """
  Commands:
  ─────────────────────────────────────────────────────
  format      Format Korean source + create output file
  extract     Bible extraction → checkpoint → write
  translate   Phase 1 + Phase 2 translation
  review      Review → checkpoint → apply corrections
  step11      Post-translation bible updates → checkpoint
  audit       Phase 3 dash audit
  run         Full pipeline (all stages in order)
  ─────────────────────────────────────────────────────
  chapter     Switch chapter (same novel)
  novel       Switch novel (resets session)
  status      Show completed stages this session
  help        Show this help
  exit/quit   Exit
"""

STAGE_ORDER = ["init", "format", "extract", "translate", "review", "step11", "audit"]

COMMAND_MAP = {
    "format":    run_stage_format,
    "extract":   run_stage_extract,
    "translate": run_stage_translate,
    "review":    run_stage_review,
    "step11":    run_stage_step11,
    "audit":     run_stage_audit,
}



def print_status(session: dict):
    state = session["state"]
    completed = session["completed"]
    print()
    print(f"  Novel  : {Path(state['novel_dir']).name}")
    print(f"  Chapter: {Path(state['korean_file']).name}")
    if state.get("output_path"):
        print(f"  Output : {Path(state['output_path']).name}")
    print()
    for stage in STAGE_ORDER[1:]:  # skip "init"
        tick = "✓" if stage in completed else "·"
        print(f"    {tick}  {stage}")
    print()


def make_session(novel_dir: Path, korean_file: Path) -> dict:
    return {
        "novel_dir":    novel_dir,
        "korean_file":  korean_file,
        "state":        create_initial_state(
                            novel_dir=str(novel_dir),
                            korean_file=str(korean_file),
                        ),
        "completed":    set(),
    }


def repl(novel_dir: Path, korean_file: Path):
    session = make_session(novel_dir, korean_file)

    print()
    print("═" * 70)
    print(f"  {novel_dir.name}  ·  {korean_file.name}")
    print(f"  Type 'help' for commands, 'run' for full pipeline.")
    print("═" * 70)

    while True:
        try:
            cmd = input("\n hawk> ").strip().lower()
        except (EOFError, KeyboardInterrupt):
            print("\n  Exiting.")
            break

        if not cmd:
            continue

        elif cmd in ("exit", "quit"):
            print("  Exiting.")
            break

        elif cmd == "help":
            print(HELP_TEXT)

        elif cmd == "status":
            print_status(session)

        elif cmd == "novel":
            novel_dir = select_novel(PROJECT_ROOT)
            korean_file = select_chapter(novel_dir)
            session = make_session(novel_dir, korean_file)
            print(f"\n  ✓ Switched to: {novel_dir.name} — {korean_file.name}")

        elif cmd == "chapter":
            korean_file = select_chapter(session["novel_dir"])
            session = make_session(session["novel_dir"], korean_file)
            print(f"\n  ✓ Switched to chapter: {korean_file.name}")

        elif cmd in COMMAND_MAP:
            runner = COMMAND_MAP[cmd]
            ok = runner(session)
            if ok:
                print(f"\n  ✓ {cmd} complete.")

        elif cmd == "run":
            print("\n  Running full pipeline...\n")
            stages = ["format", "extract", "translate", "review", "step11", "audit"]
            for stage in stages:
                if stage in session["completed"]:
                    print(f"  ↳ {stage} already done — skipping")
                    continue
                ok = COMMAND_MAP[stage](session)
                if not ok:
                    print(f"\n  [STOPPED] Pipeline halted at: {stage}")
                    break
            else:
                print("\n  ✓ Full pipeline complete.")
                from src.workflow.nodes import output_node
                output_node(session["state"])

        else:
            print(f"  Unknown command: '{cmd}'. Type 'help' for options.")


# ── Entry point ───────────────────────────────────────────────────────────────

def main():
    print()
    print("═" * 70)
    print("  HAWK TRANSLATIONS")
    print("═" * 70)

    novel_dir   = select_novel(PROJECT_ROOT)
    korean_file = select_chapter(novel_dir)

    repl(novel_dir, korean_file)


if __name__ == "__main__":
    main()
