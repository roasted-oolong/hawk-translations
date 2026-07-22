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
OPUS_MODEL   = os.environ.get("OPUS_MODEL",   "qwen2.5:72b")   # Quality-critical: Phase 2 (only reached by voice review when CALIBRATION_BACKEND=local)

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

# ── Rails app URL ─────────────────────────────────────────────────────────────
# Used by BibleLookupSkill to reach the bible search API.
HAWK_RAILS_URL = os.environ.get("HAWK_RAILS_URL", "http://localhost:3000")

# ── API settings ──────────────────────────────────────────────────────────────
MAX_TOKENS          = 16000
FORMAT_MAX_TOKENS   = 64000   # Formatting output is ~1:1 with input; needs headroom for large batches

# ── Translation backend ──────────────────────────────────────────────────────
# Used only by translate.py / translate_batch.py (src/translation_backend.py).
# Independent of LLM_BASE_URL/OPUS_MODEL/etc. above, which remain Ollama
# config for the other pipeline scripts (preread, review, formatting, ...).
#
# "claude_code": shells out to the Claude Code CLI, authenticated via the
#   user's Claude subscription (subscription-metered, not per-token API
#   billing). Set TRANSLATION_BACKEND=local to fall back to the Ollama path
#   with no code change.
# "local": the existing Ollama-backed path (src/agent.py), unchanged.
TRANSLATION_BACKEND = os.environ.get("TRANSLATION_BACKEND", "claude_code")
TRANSLATION_MODEL   = os.environ.get("TRANSLATION_MODEL", "opus")

# Dollar ceiling passed to `claude -p --max-budget-usd` — a real spend guard
# even under subscription auth (verified: the CLI enforces it and aborts
# with terminal_reason "budget_exhausted" if exceeded). $3.00 is a starting
# placeholder; tune after observing a real chapter's total_cost_usd.
TRANSLATION_MAX_BUDGET_USD = float(os.environ.get("TRANSLATION_MAX_BUDGET_USD", "3.00"))

# ── Calibration backend ───────────────────────────────────────────────────────
# Used only by calibrate-voice.py, selected independently of TRANSLATION_BACKEND
# via the same src/translation_backend.get_backend() seam (its two backend
# implementations are domain-agnostic — see that module's docstring). Reverses
# the 2026-07-20 "stays local" decision (docs/DECISIONS.md) after local-model
# review quality proved a recurring blocker, not a one-off. Set
# CALIBRATION_BACKEND=local to fall back to the Ollama path unchanged.
CALIBRATION_BACKEND = os.environ.get("CALIBRATION_BACKEND", "claude_code")
