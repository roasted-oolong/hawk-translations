import os

# ── LLM endpoint ──────────────────────────────────────────────────────────────
# Defaults to Ollama's OpenAI-compatible API. Override with LM Studio, vllm,
# or any other local OpenAI-compatible server by setting these env vars.
LLM_BASE_URL = os.environ.get("LLM_BASE_URL", "http://localhost:11434/v1")
LLM_API_KEY  = os.environ.get("LLM_API_KEY", "local")

# ── Models ────────────────────────────────────────────────────────────────────
# Set these to whatever model names your local server exposes.
HAIKU_MODEL  = os.environ.get("HAIKU_MODEL",  "qwen2.5:7b")    # Mechanical: format, file naming
SONNET_MODEL = os.environ.get("SONNET_MODEL", "qwen2.5:32b")   # Core: extraction, Phase 1, review
OPUS_MODEL   = os.environ.get("OPUS_MODEL",   "qwen2.5:72b")   # Quality-critical: Phase 2, voice review

# ── Project root ──────────────────────────────────────────────────────────────
PROJECT_ROOT = os.environ["HAWK_PROJECT_ROOT"]

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
