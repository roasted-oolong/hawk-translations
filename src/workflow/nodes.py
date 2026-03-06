"""
LangGraph node implementations.
Each node takes state, does work, returns state updates.
User checkpoints are blocking input() calls inside the relevant nodes.
"""

import asyncio
import re
import time
from pathlib import Path
from typing import Any

from ..state import TranslationState
from ..agents.prep import run_formatter, run_file_namer
from ..agents.bible import run_all_extractors
from ..agents.translation import run_phase1, run_phase2
from ..agents.review import run_all_reviewers
from ..agents.audit import run_dash_auditor
from config import SONNET_MODEL


# ── Helpers ───────────────────────────────────────────────────────────────────

def hr(char="─", width=70):
    print(char * width)

def section(title: str):
    print()
    hr("═")
    print(f"  {title}")
    hr("═")
    print()

def checkpoint(label: str) -> str | None:
    """
    Blocking user checkpoint. Returns None on CONFIRM, or the user's notes.
    """
    hr()
    print(f"  [CHECKPOINT] {label}")
    hr()
    while True:
        response = input("\n> Type CONFIRM to proceed, or enter corrections/notes:\n> ").strip()
        if response.upper() == "CONFIRM":
            return None
        elif response:
            return response
        else:
            print("  (Type CONFIRM or enter your notes.)")

def read_file(path: str | Path) -> str:
    try:
        return Path(path).read_text(encoding="utf-8")
    except FileNotFoundError:
        return ""

def write_file(path: str | Path, content: str):
    Path(path).write_text(content, encoding="utf-8")


# ── Node: init ────────────────────────────────────────────────────────────────

def init_node(state: TranslationState) -> dict[str, Any]:
    """Load all reference files into state."""
    section("INIT — Loading reference files")

    novel_dir = Path(state["novel_dir"])
    bible_dir = novel_dir / "bible"

    novel_info  = read_file(novel_dir / "novel_info.md")
    guidelines  = read_file(novel_dir / "translation_guidelines.md")
    characters  = read_file(bible_dir / "characters.md")
    terminology = read_file(bible_dir / "terminology.md")
    cultural    = read_file(bible_dir / "cultural_phrases.md")
    locations   = read_file(bible_dir / "locations.md")
    story       = read_file(bible_dir / "story.md")

    # Style references (_ANOTHER TRANSLATION files)
    chapters_dir = novel_dir / "chapters"
    style_refs = []
    seen = set()
    for pattern in ["*ANOTHER TRANSLATION*", "*another_translation*", "*another translation*"]:
        for f in chapters_dir.glob(pattern):
            if f not in seen:
                seen.add(f)
                content = read_file(f)
                if content:
                    style_refs.append(content)

    print(f"  ✓ novel_info.md, translation_guidelines.md")
    print(f"  ✓ bible: characters, terminology, cultural_phrases, locations, story")
    if style_refs:
        print(f"  ✓ {len(style_refs)} style reference file(s) loaded")
    else:
        print(f"  ℹ  No _ANOTHER TRANSLATION files found")

    return {
        "novel_info":       novel_info,
        "guidelines":       guidelines,
        "bible_characters": characters,
        "bible_terminology":terminology,
        "bible_cultural":   cultural,
        "bible_locations":  locations,
        "bible_story":      story,
        "style_refs":       style_refs,
        "current_stage":    "init_complete",
    }


# ── Node: prep ────────────────────────────────────────────────────────────────

def prep_node(state: TranslationState) -> dict[str, Any]:
    """Format Korean source + create output file. Sequential. Haiku."""
    section("STAGE 1 — PREP")

    # Format Korean
    print("  Step 2: Formatting Korean source (Haiku)...")
    fmt_result = run_formatter(state)
    if not fmt_result.success:
        return {"errors": [f"formatter: {fmt_result.error}"], "current_stage": "failed"}

    korean_text = fmt_result.output
    print(f"  ✓ Formatted ({fmt_result.execution_time_ms / 1000:.1f}s)")

    # Name output file
    print("  Step 7: Naming output file (Haiku)...")
    chapters_dir = Path(state["novel_dir"]) / "chapters"
    existing_titles = sorted([
        f.name for f in chapters_dir.iterdir()
        if f.suffix == ".txt"
        and "korean" not in f.name.lower()
        and "another translation" not in f.name.lower()
    ])
    name_result = run_file_namer(state, existing_titles, korean_text=korean_text)

    if not name_result.success:
        return {"errors": [f"file_namer: {name_result.error}"], "current_stage": "failed"}

    raw_filename = name_result.output.strip()

    # Sanity check: if the model returned an explanation instead of a filename, abort cleanly
    if len(raw_filename) > 200 or not raw_filename.endswith(".txt"):
        return {
            "errors": [
                f"file_namer returned an invalid filename (length {len(raw_filename)}). "
                f"Got: {raw_filename[:120]!r}..."
            ],
            "current_stage": "failed",
        }

    filename = re.sub(r'[<>:"/\\|?*]', "", raw_filename)
    output_path = str(chapters_dir / filename)
    Path(output_path).write_text("", encoding="utf-8")
    print(f"  ✓ Created: {filename}")

    # Overwrite the source file with formatted version
    write_file(state["korean_file"], korean_text)

    return {
        "korean_text": korean_text,
        "output_path": output_path,
        "current_stage": "prep_complete",
    }


# ── Node: bible_extract ───────────────────────────────────────────────────────

def bible_extract_node(state: TranslationState) -> dict[str, Any]:
    """Run all 5 bible extractors in parallel. Sonnet."""
    section("STAGE 2 — BIBLE EXTRACTION (5 agents in parallel)")

    start = time.time()
    extractions = run_all_extractors(state)
    elapsed = time.time() - start

    success_count = sum(1 for e in extractions if e.get("success"))
    print(f"\n  Bible extraction: {success_count}/5 agents in {elapsed:.1f}s")

    # Present all results
    print()
    for entry in extractions:
        domain = entry["domain"]
        if entry["success"]:
            hr("·")
            print(f"  [{domain.upper()}]\n")
            print(entry["output"])
        else:
            print(f"  [{domain.upper()}] FAILED: {entry['error']}")

    errors = [
        f"extractor_{e['domain']}: {e['error']}"
        for e in extractions if not e.get("success")
    ]

    return {
        "bible_extractions": extractions,
        "errors": errors,
        "current_stage": "bible_extracted",
    }


# ── Node: bible_write ─────────────────────────────────────────────────────────

def bible_write_node(state: TranslationState) -> dict[str, Any]:
    """
    Write confirmed bible updates to disk.
    Called after the user checkpoint in routing.
    Each file updated independently (no Claude call needed —
    the extractor outputs are appended/merged by a lightweight writer call).
    """
    section("STAGE 2 — WRITING BIBLE FILES")
    from ..agents.base import call_claude, AgentResult
    from ..context import build_context

    bible_dir = Path(state["novel_dir"]) / "bible"
    corrections = state.get("bible_corrections") or ""
    correction_note = f"\n\nUser corrections: {corrections}" if corrections else ""

    domain_to_state_key = {
        "characters":       ("bible_characters",  "characters.md"),
        "terminology":      ("bible_terminology",  "terminology.md"),
        "cultural_phrases": ("bible_cultural",     "cultural_phrases.md"),
        "locations":        ("bible_locations",    "locations.md"),
        "story":            ("bible_story",        "story.md"),
    }

    updated_bible = {}
    for entry in state.get("bible_extractions", []):
        if not entry.get("success"):
            continue
        domain = entry["domain"]
        if domain not in domain_to_state_key:
            continue

        state_key, filename = domain_to_state_key[domain]
        current = state.get(state_key, "")
        updates = entry["output"]

        system = build_context(f"characters_extractor", state)  # minimal — novel_info + guidelines + that bible file
        prompt = (
            f"Update the {domain} bible file by integrating the new information below.\n"
            "Preserve all existing content. Add new entries cleanly.\n"
            "Return the COMPLETE updated file content only — no commentary.\n\n"
            f"CURRENT {domain.upper()} FILE:\n{current}\n\n"
            f"NEW UPDATES TO INTEGRATE:\n{updates}"
            f"{correction_note}"
        )

        result = call_claude(
            agent_name=f"bible_writer_{domain}",
            model=SONNET_MODEL,
            system_parts=system,
            user_message=prompt,
            label=f"Writing {domain}",
        )

        if result.success and result.output:
            # Safety: never overwrite a non-empty file if korean_text was empty
            existing = Path(bible_dir / filename).read_text(encoding="utf-8") if (bible_dir / filename).exists() else ""
            if existing.strip() and not state.get("korean_text", "").strip():
                print(f"  SKIPPED: {filename} — korean_text was empty, refusing to overwrite existing content")
                continue
            write_file(bible_dir / filename, result.output)
            updated_bible[state_key] = result.output
            print(f"  ✓ Updated: {filename}")
        else:
            print(f"  FAILED: {filename} — {result.error}")

    return {
        **updated_bible,
        "current_stage": "bible_written",
    }


# ── Node: translate ───────────────────────────────────────────────────────────

def translate_node(state: TranslationState) -> dict[str, Any]:
    """Phase 1 (Sonnet) → Phase 2 (Opus). Sequential."""
    section("STAGE 3 — TRANSLATION")

    # Phase 1
    p1 = run_phase1(state)
    if not p1.success:
        return {"errors": [f"phase1: {p1.error}"], "current_stage": "failed"}

    # Phase 2 reads from disk (handled inside run_phase2)
    p2 = run_phase2({**state, "phase1_output": p1.output})
    if not p2.success:
        return {"errors": [f"phase2: {p2.error}"], "current_stage": "failed"}

    return {
        "phase1_output": p1.output,
        "phase2_output": p2.output,
        "current_stage": "translation_complete",
    }


# ── Node: review ──────────────────────────────────────────────────────────────

def review_node(state: TranslationState) -> dict[str, Any]:
    """Run 4 reviewers in parallel against Phase 2 output. Step 10."""
    section("STAGE 4 — REVIEW (4 agents in parallel)")

    # Read from disk — always work from the file, not memory
    translation = ""
    if state.get("output_path") and Path(state["output_path"]).exists():
        translation = Path(state["output_path"]).read_text(encoding="utf-8")
    else:
        translation = state.get("phase2_output", "")

    start = time.time()
    review_outputs = run_all_reviewers(state, translation)
    elapsed = time.time() - start

    success_count = sum(1 for r in review_outputs if r.get("success"))
    print(f"\n  Review: {success_count}/4 agents in {elapsed:.1f}s")

    print()
    for entry in review_outputs:
        reviewer = entry["reviewer"]
        if entry["success"]:
            hr("·")
            print(f"  [{reviewer.upper()} REVIEW]\n")
            print(entry["output"])
        else:
            print(f"  [{reviewer.upper()}] FAILED: {entry['error']}")

    errors = [
        f"reviewer_{r['reviewer']}: {r['error']}"
        for r in review_outputs if not r.get("success")
    ]

    return {
        "review_outputs": review_outputs,
        "errors": errors,
        "current_stage": "review_complete",
    }


# ── Node: step11 ──────────────────────────────────────────────────────────────

def step11_node(state: TranslationState) -> dict[str, Any]:
    """
    Step 11: Post-translation bible updates.
    Runs same 5 extractors but against the final translation, not the Korean.
    Surfaces English handling decisions, new plot confirmations, watch list items.
    """
    section("STAGE 4 — STEP 11: POST-TRANSLATION BIBLE UPDATES")

    # Use the final post-review text
    translation = state.get("post_review_text") or state.get("phase2_output", "")

    from ..agents.bible import (
        run_characters_extractor, run_terminology_extractor,
        run_cultural_extractor, run_locations_extractor, run_story_extractor
    )
    import asyncio

    # Temporarily swap korean_text for the translation for extraction prompts
    step11_state = {**state, "korean_text": translation}

    async def run_step11_async():
        loop = asyncio.get_event_loop()
        tasks = [
            loop.run_in_executor(None, run_characters_extractor, step11_state),
            loop.run_in_executor(None, run_terminology_extractor, step11_state),
            loop.run_in_executor(None, run_cultural_extractor, step11_state),
            loop.run_in_executor(None, run_locations_extractor, step11_state),
            loop.run_in_executor(None, run_story_extractor, step11_state),
        ]
        names = ["characters", "terminology", "cultural_phrases", "locations", "story"]
        results = await asyncio.gather(*tasks, return_exceptions=True)
        outputs = []
        for i, result in enumerate(results):
            name = names[i]
            if isinstance(result, Exception):
                outputs.append({"domain": name, "output": None, "success": False, "error": str(result)})
            elif not result.success:
                outputs.append({"domain": name, "output": None, "success": False, "error": result.error})
            else:
                outputs.append({"domain": name, "output": result.output, "success": True})
        return outputs

    extractions = asyncio.run(run_step11_async())

    print()
    for entry in extractions:
        domain = entry["domain"]
        if entry["success"]:
            hr("·")
            print(f"  [STEP 11 — {domain.upper()}]\n")
            print(entry["output"])
        else:
            print(f"  [STEP 11 — {domain.upper()}] FAILED: {entry['error']}")

    return {
        "step11_extractions": extractions,
        "current_stage": "step11_complete",
    }


# ── Node: audit ───────────────────────────────────────────────────────────────

def audit_node(state: TranslationState) -> dict[str, Any]:
    """Phase 3 dash audit. Sonnet. Reads and overwrites output file."""
    section("STAGE 5 — PHASE 3: DASH AUDIT")

    result = run_dash_auditor(state)
    if not result.success:
        return {"errors": [f"dash_auditor: {result.error}"], "current_stage": "failed"}

    return {
        "final_text": result.output,
        "current_stage": "audit_complete",
    }


# ── Node: output ──────────────────────────────────────────────────────────────

def output_node(state: TranslationState) -> dict[str, Any]:
    """Final status report."""
    section("SESSION COMPLETE")

    errors = state.get("errors", [])
    output_path = state.get("output_path", "")

    print("  End-of-Session Checklist:")
    print("  ✓ Phase 3 dash audit — complete")
    print("  ✓ Step 11 additional bible updates — complete")
    print()
    if output_path:
        print(f"  Output: {output_path}")
    if errors:
        print(f"\n  Errors encountered ({len(errors)}):")
        for e in errors:
            print(f"    · {e}")
    print()
    hr("═")

    return {"current_stage": "complete"}
