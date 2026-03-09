# ── Models ────────────────────────────────────────────────────────────────────
HAIKU_MODEL  = "claude-haiku-4-5-20251001"   # Mechanical: format, file naming
SONNET_MODEL = "claude-sonnet-4-6"            # Core: extraction, Phase 1, review
OPUS_MODEL   = "claude-opus-4-6"              # Quality-critical: Phase 2, voice review

# ── Project root ──────────────────────────────────────────────────────────────
PROJECT_ROOT = "/home/jenna/hawk-translations"

# ── Reference file map ───────────────────────────────────────────────────────
# Keys map to TranslationContext field names.
# Paths are relative to the novel root (novel_dir) or bible subdirectory.
# chapter_log.md is intentionally excluded — archive only, never sent to API.
NOVEL_FILES = {
    "novel_info":             ("novel_info.md",             "novel"),
    "translation_guidelines": ("translation_guidelines.md", "novel"),
    "voice_calibration":      ("voice_calibration.md",      "bible"),
    "characters":             ("characters.md",             "bible"),
    "cultural_phrases":       ("cultural_phrases.md",       "bible"),
    "locations":              ("locations.md",              "bible"),
    "story":                  ("story.md",                  "bible"),
    "terminology":            ("terminology.md",            "bible"),
}

# ── API settings ──────────────────────────────────────────────────────────────
MAX_TOKENS          = 16000
FORMAT_MAX_TOKENS   = 64000   # Formatting output is ~1:1 with input; needs headroom for large batches
