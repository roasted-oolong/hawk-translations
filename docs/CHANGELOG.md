# Hawk Translations — Changelog

---
## 2026-07-21
Added:
- `src/translation_backend.py` — selects the active translation backend (`TRANSLATION_BACKEND`, default `"claude_code"`); `"local"` wraps the existing `src/agent.py`/Ollama path unchanged, `"claude_code"` is new
- `src/claude_code_agent.py` — translation backend that shells out to the Claude Code CLI (`claude -p`), authenticated via the user's Claude subscription rather than a metered API key
- `src/mcp_servers/skill_bridge.py` — generic MCP stdio server that dynamically exposes any `Skill` instance as an MCP tool, via a new `Skill.bridge_spec()` method (`src/skills/base.py`) — lets both translation backends share the same `BibleLookupSkill`/`WebSearchSkill` instances with no per-skill server code
- `tests/test_translation_backend.py`, `tests/test_claude_code_agent.py`, `tests/test_skill_bridge.py`, `tests/test_batch_runner.py`
- `mcp` added to `requirements.txt`

Changed:
- `translate.py`, `translate_batch.py`, `src/translator/batch_runner.py` — now call through `src.translation_backend.get_backend()` instead of `src.agent` directly; `src/agent.py` itself is untouched (still used by the other 8 pipeline scripts against the local model)
- `config.py` — added `TRANSLATION_BACKEND`, `TRANSLATION_MODEL`, `TRANSLATION_MAX_BUDGET_USD`
- `translate_batch.py`'s per-chapter request no longer hardcodes `model`/`max_tokens` — the active backend supplies its own default

Note: Committed. See `docs/DECISIONS.md` (2026-07-21) for why, including an
undocumented-but-required `MCP_CONNECTION_NONBLOCKING=false` env var fix.

## 2026-03-31
Added:
- `app/javascript/controllers/tabs_controller.ts` — tab strip controller; manages active tab class, lazy-loads Turbo Frame panels on first activation, persists selection to `sessionStorage` keyed by novel id
- `spec/system/novel_show_tabs_spec.rb` — 36 system spec examples for M23

Changed:
- `app/views/novels/show.html.erb` — fully rewritten: header block (cover slot, genre badge, title, Korean title, summary, progress bar) + four-tab strip (Chapters, Bible active; Review, Voice Calibration aria-disabled) + two lazy `<turbo-frame>` panels
- `app/assets/stylesheets/_novels.css` — added `.novel-show__header-block`, `.novel-show__genre-badge`, `.novel-show__progress-*`, `.novel-tabs`, `.novel-tab`, `.novel-tab--active`, `.novel-tab--disabled`; mobile rules for cover slot hide and tab strip scroll
- `app/javascript/controllers/index.ts` — registered `tabs` controller
- `spec/system/dashboard_novels_spec.rb` — updated stale novel show assertions (old section testids → tab strip testids)

Note: Committed

## 2026-03-25
Added:
- Sidebar user identity widget (bottom of sidebar): initials avatar, name, and highest-privilege role label
- `User#display_role` — returns Platform Admin > Team Admin > Team Member > No role assigned
- `app/views/components/_user_widget.html.erb` component partial
- Auto-provision workspace and novel assignment for new users
- `app/services/provision_workspace.rb` — idempotent, wrapped in a transaction, guards on `memberships.exists?`
- `app/services/auto_assign_novel.rb` — idempotent via `find_or_create_by!`, no-op if user has no teams

Changed:
- `SessionsController#create` — calls `ProvisionWorkspace` only when `user.previously_new_record?`
- `NovelsController#create` — calls `AutoAssignNovel` after successful save

Note: Committed

## 2026-03-22
Fixed:
- Drag-and-drop, filename preview, drag-over feature in `file_upload_controller.ts`

Changed: N/A
Note: Committed
