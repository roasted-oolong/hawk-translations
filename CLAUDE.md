# hawk-translations

Rails 8.1 web application that supports a Korean-to-English novel translation workflow.
Ruby 3.4.2 · PostgreSQL · Hotwire (Turbo + Stimulus) · Solid Queue · Active Storage · Kamal

## Routing table

| Task | Go to | Read |
|------|-------|------|
| Novel CRUD, discovery, cover art | `app/controllers/novels_controller.rb`, `app/views/novels/` | `docs/SCHEMA.md` |
| Chapter upload, status, file download | `app/controllers/chapters_controller.rb`, `app/views/chapters/` | `docs/SCHEMA.md` |
| Translation job trigger, status, output | `app/controllers/translation_jobs_controller.rb`, `app/views/translation_jobs/` | `docs/SCHEMA.md` |
| Bible entries (characters, locations, etc.) | `app/controllers/bible_*_controller.rb`, `app/views/bible*/` | `docs/SCHEMA.md` |
| Bible landing page + search | `app/controllers/bible_controller.rb`, `app/controllers/bible_search_controller.rb` | |
| Dashboard | `app/controllers/dashboard_controller.rb`, `app/views/dashboard/` | |
| Auth (currently disabled — solo dev) | `app/controllers/application_controller.rb#current_user` | `docs/DECISIONS.md` (2026-06-07) |
| Background job execution | `app/jobs/pipeline_job.rb` | `docs/CONVENTIONS.md` |
| Python pipeline dispatch | `app/services/pipeline_dispatcher.rb` | |
| `claude` CLI backend seam (R1) | `app/services/translation_config.rb`, `app/services/pipeline/claude_code.rb` | `docs/RAILS_REFACTOR_PLAN.md` |
| Agent skills (R2) — `bible_lookup` in-process | `app/services/pipeline/skill.rb`, `app/services/pipeline/skills/` | `docs/RAILS_REFACTOR_PLAN.md` |
| MCP skill bridge (R3) | `app/services/pipeline/mcp/`, `bin/mcp_skill_bridge` | `docs/RAILS_REFACTOR_PLAN.md` |
| translate_batch orchestration (R4) | `app/services/pipeline/ruby/translate_batch.rb`, `app/services/pipeline/ruby/translate_batch/{prompt_builder,bridge_config}.rb` | `docs/RAILS_REFACTOR_PLAN.md` |
| Translation quality pipeline eval (5-step: hybrid beat segmentation → analysis → localization → factcheck + editor, chained, offline/eval-only) | `app/services/pipeline/ruby/translation_eval.rb`, `app/services/pipeline/ruby/translate_batch/beat_segmenter.rb`, `bin/translation_eval`, `PromptBuilder.build_beat_classification_system_prompt`/`.build_analysis_system_prompt`/`.build_localization_system_prompt`/`.build_factcheck_system_prompt`/`.build_editor_system_prompt` | `docs/DECISIONS.md` (2026-07-30/2026-07-31/2026-08-01/2026-08-02 entries) |
| Preread / bible_build orchestration (R6) | `app/services/pipeline/ruby/preread_runner/`, `app/services/pipeline/{prompt_utils,bible_utils,bible_file_editor,preread_bible_writer}.rb` | `docs/RAILS_REFACTOR_PLAN.md` |
| Chapter formatter / OCR orchestration (R6.5) | `app/services/pipeline/ruby/{format_korean_chapter,ocr_chapter,formatter_prompt_builder,formatter_response_parser}.rb`, `app/services/pipeline/{local_llm_chat,claude_vision}.rb` | `docs/RAILS_REFACTOR_PLAN.md` |
| Post-translation review / voice calibration orchestration (R5) | `app/services/pipeline/ruby/post_translation_review*`, `app/services/pipeline/ruby/voice_calibration*`, `app/services/pipeline/translated_chapter_reader.rb` | `docs/RAILS_REFACTOR_PLAN.md` |
| Post-translation bible review, commit (R5) | `app/controllers/post_translation_review_controller.rb`, `app/services/pipeline/bible_review_writer.rb` | `docs/RAILS_REFACTOR_PLAN.md` |
| Bible semantic search | `app/services/bible_search_service.rb` | |
| Embedding generation | `app/jobs/generate_embedding_job.rb`, `app/services/voyage_client.rb` | |
| Voice calibration review, commit | `app/controllers/voice_calibration_review_controller.rb`, `app/services/voice_calibration_doc_writer.rb` | |
| Stimulus controllers | `app/javascript/controllers/` | `docs/UI.md` |
| Model validations, scopes, enums | `app/models/` | `docs/SCHEMA.md` |
| Request specs | `spec/requests/` | |
| System specs (Capybara) | `spec/system/` | |
| Model specs | `spec/models/` | |
| Routes | `config/routes.rb` | |
| Schema | `db/schema.rb` | `docs/SCHEMA.md` |
| Deployment config | `config/deploy.yml`, `.kamal/` | `docs/CONVENTIONS.md` |
| Architecture decisions | `docs/DECISIONS.md` | |
| Product context, personas | `docs/PRODUCT.md` | |
| Full-Rails refactor plan (Python pipeline → Ruby) | `docs/RAILS_REFACTOR_PLAN.md` | |

## Naming conventions

- Job model: `TranslationJob` (table: `translation_jobs`) — avoids collision with ActiveJob base class
- Bible tables: `bible_characters`, `bible_locations`, `bible_terminology`, `bible_cultural_phrases`, `bible_story_entries`
- Chapter status enum: `untranslated` | `translated` | `reviewed` (string-backed)
- Job type enum: `preread` | `bible_build` | `post_translation_review` (string-backed)
- Job status enum: `queued` | `running` | `completed` | `failed` (string-backed)
- Novel permission levels: `viewer` | `editor` | `translator` | `admin` (string enum on `NovelTeamAssignment`)
- Stimulus controllers: `*_controller.ts` in `app/javascript/controllers/`
- Reusable view partials: `app/views/components/`
- All DB operations through ActiveRecord — no raw SQL anywhere

## Coding Rules

- SOLID principles throughout
- Loosely coupled code — components should not know more about each other
  than they need to
- Favor composition over inheritance
- Write tests first.

## Commit Convention

Follow the Conventional Commits specification for all commit messages:

  <type>(<scope>): <description>

Types: feat, fix, test, refactor, style, chore, docs, db
Scopes (optional): novels, chapters, bible, jobs, auth, dashboard, uploads, sidebar, tabs, api

Each commit must be atomic — one logical change only. Signs it needs splitting:
- The description requires "and" to be accurate
- The diff touches unrelated files
- It would be hard to revert without affecting unrelated work

A migration and its model change belong in one commit. A refactor must not be
bundled with a behaviour change. Cosmetic CSS belongs in its own style: commit.

Use the commit body when the why is not obvious from the description alone.
Keep the description line to 72 characters or fewer.
