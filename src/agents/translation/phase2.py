"""Phase 2 rewrite — Opus with full context and style references."""

from pathlib import Path
from ..base import call_claude, AgentResult
from ...config import OPUS_MODEL
from ...context.builder import build_system


def _load_style_refs(chapters_dir: str) -> str:
    """Find and load all _ANOTHER TRANSLATION files."""
    seen = set()
    content_parts = []
    for pattern in ["*ANOTHER TRANSLATION*", "*another_translation*", "*another translation*"]:
        for f in Path(chapters_dir).glob(pattern):
            if f not in seen:
                seen.add(f)
                text = f.read_text(encoding="utf-8")
                if text:
                    content_parts.append(
                        f"=== STYLE REFERENCE: {f.name} ===\n{text}"
                    )
    return "\n\n".join(content_parts)


async def run_phase2(
    phase1_text: str,
    korean_text: str,
    novel_info: str,
    guidelines: str,
    characters: str,
    terminology: str,
    cultural_phrases: str,
    chapters_dir: str,
) -> AgentResult:
    """
    Phase 2: full localization and rewrite pass.
    Uses Opus. Loads style references from _ANOTHER TRANSLATION files.
    """
    style_content = _load_style_refs(chapters_dir)

    style_note = ""
    if style_content:
        print(f"  ✓ Style references loaded.")
        style_note = (
            "## STYLE REFERENCES FOR VOICE CALIBRATION\n"
            "Use these to calibrate dialogue register, laughter and disrupted speech, "
            "colloquial naturalness, and emotional pacing.\n\n"
            + style_content
        )
    else:
        print("  ℹ  No _ANOTHER TRANSLATION files found — proceeding without.")

    system = build_system(
        novel_info, guidelines,
        characters=characters,
        terminology=terminology,
        cultural_phrases=cultural_phrases,
        extra=style_note if style_note else None,
        cache_stable=True,
    )

    prompt = f"""You are performing Phase 2: full localization and rewrite pass.

PHASE 2 GOALS:
- Full localization — make this feel like it was written in English
- Calibrate voice from the style references in your system prompt
- Sentence Integration: merge in narration and internal monologue; preserve separation at emotional peaks, tonal pivots, and standalone observations
- Before writing any chapter-closing line or emotional peak moment: re-read the POV & Narrative Style section of novel_info.md and hear Kang's voice in it before writing — do not flatten interiority for a clean landing
- Preserve all inline flags: [원래 한국어 / proposed translation?]
- Rolling consistency with the story bible

PHASE 1 TRANSLATION (rewrite this):
{phase1_text}

ORIGINAL KOREAN (reference):
{korean_text}"""

    return await call_claude(
        OPUS_MODEL, system, prompt,
        agent_name="phase2_rewriter",
        label="Phase 2 rewrite (Opus)",
    )
