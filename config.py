# ── Models ────────────────────────────────────────────────────────────────────
HAIKU_MODEL  = "claude-haiku-4-5-20251001"   # Mechanical: format, file naming
SONNET_MODEL = "claude-sonnet-4-6"            # Core: extraction, Phase 1, review
OPUS_MODEL   = "claude-opus-4-6"              # Quality-critical: Phase 2, voice review

# ── Project root ──────────────────────────────────────────────────────────────
PROJECT_ROOT = "/home/jenna/hawk-translations"

# ── Bible file map ────────────────────────────────────────────────────────────
# chapter_log.md is intentionally excluded — archive only, never sent to API
BIBLE_FILES = {
    "characters":       "characters.md",
    "cultural_phrases": "cultural_phrases.md",
    "locations":        "locations.md",
    "story":            "story.md",
    "terminology":      "terminology.md",
}

# ── API settings ──────────────────────────────────────────────────────────────
MAX_TOKENS = 16000
CACHE_TYPE = "ephemeral"
