# Hawk Translations — Roadmap

Status key: ✅ Done · 🔄 In Progress · 🔲 Not Started

---

## Milestone 1 — Rails App Generation
**Status: ✅ Done**

Generate the Rails 8 app at repo root with correct flags.
No feature code. Just a clean, booting app connected to PostgreSQL with RSpec configured.

Deliverables:
- `rails new` with correct flags (see CONVENTIONS.md)
- PostgreSQL database created and connected
- RSpec installed and passing `rspec` with zero errors on empty suite
- `rails server` boots without errors

---

## Milestone 2 — Rails MCP Server Verification
**Status: ✅ Done**

Confirm the Rails MCP server (maquina-app/rails-mcp-server) is working
so schema and route inspection is available throughout development.

Deliverables:
- MCP server connects to the Rails app
- Schema and route inspection confirmed working

---

## Milestone 3 — Fix config.py PROJECT_ROOT
**Status: ✅ Done**

`config.py` currently hardcodes `PROJECT_ROOT` as an absolute local path.
Must read from environment variable before any pipeline jobs can be invoked
from the Rails app.

Deliverables:
- `PROJECT_ROOT` reads from `ENV["HAWK_PROJECT_ROOT"]`
- `.env` updated with the variable
- Existing pipeline still runs correctly locally

---

## Milestone 4 — Authentication
**Status: ✅ Done**

Google OAuth via OmniAuth. Single admin user for MVP — no self-registration,
no invite flow. All routes require authentication.

Deliverables:
- Google OAuth sign-in works
- Session-based authentication
- All routes redirect to login when unauthenticated
- Sign-out works from any page
- Credentials stored in Rails encrypted credentials

> **Note:** User model created in full here (all columns from SCHEMA.md Milestone 5).
> Milestone 5 adds no `users` migration — only the multi-tenant models around it.

---

## Milestone 5 — Core Multi-Tenant Schema & Models
**Status: ✅ Done**

The foundational data model. Everything else builds on this.
pgvector extension enabled now so infrastructure is ready for Milestone 12.

Entities: Organization, Team, Membership, Novel, Series
(User model already created in full at Milestone 4 — no `users` migration needed here.)

Deliverables:
- ✅ Migrations written and run
- ✅ Models with associations and validations
- ✅ RSpec model specs passing
- ✅ Schema documented in SCHEMA.md

---

## Milestone 6 — Novel Team Assignments & Permission Scaffolding
**Status: ✅ Done**

NovelTeamAssignment join table with permission levels (viewer/editor/translator/admin).
Schema and models built now. Enforcement activated when first collaborator joins (post-MVP).

Deliverables:
- NovelTeamAssignment migration and model
- Permission level enum defined
- RSpec model specs passing
- No enforcement logic yet — scaffolding only

---

## Milestone 7 — Chapter Management & File Upload/Download
**Status: ✅ Done**

Chapter records tied to novels. Korean source upload and translated output download
via Active Storage (local disk). Status tracking (untranslated/translated/reviewed).

Deliverables:
- Chapter model with status enum
- Active Storage configured (local disk)
- Single and bulk file upload
- Translated output download
- Chapter list view with status
- RSpec model and feature specs passing

---

## Milestone 8 — Bible Entry Tables & Views
**Status: ✅ Done**

Five separate bible tables: characters, locations, terminology, cultural_phrases, story_entries.
CRUD for all categories. Markdown-style rendered views.

Deliverables:
- ✅ All five bible table migrations written
- ✅ All five models (validations, scopes, before_save callback for last_updated_at)
- ✅ Novel model updated with five has_many associations (dependent: :destroy)
- ✅ Routes — five nested resource blocks under :novels
- ✅ Five controllers (standard 7 actions, set_novel / set_entry pattern)
- ✅ All views — index, show, new, edit, _form for all five categories (25 files)
- ✅ novels/show updated with Bible section (entry counts + links per category)
- ✅ RSpec model specs written (5 files)
- ✅ RSpec request specs written (5 files)
- ✅ FactoryBot factories written (5 files)
- ✅ `rails db:migrate` — run locally to apply the five new migrations
- ✅ `rspec` — confirm all specs pass against the migrated schema

---

## Milestone 9 — Bible Data Migration (idols-rewind)
**Status: ✅ Done**

One-time import of existing idols-rewind markdown bible files into the database.
Chapter file naming cleanup: not needed — files already in correct format.

Deliverables:
- ✅ `world_building` added to `BibleStoryEntry` category enum (migration + model + spec + view + form)
- ✅ Import script: `db/import/idols_rewind_bible.rb` — all five bible categories, idempotent
- ✅ Organization + Novel record created idempotently by the import script
- ✅ Chapter rename script: not needed — all 74 chapter files already use `Chapter N.txt` / `Chapter N (Korean).txt` format
- Run to execute: `rails db:migrate && rails runner db/import/idols_rewind_bible.rb`

---

## Milestone 10 — Translation Job Invocation & Status Tracking
**Status: 🔄 In Progress**

Rails invokes Python pipeline scripts as Solid Queue background jobs.
PREREAD, BIBLE BUILD, POST-TRANSLATION REVIEW jobs triggerable from the UI.
Job status visible in real time.

Deliverables:
- ✅ `novels.directory_name` column — migration, model validation, factory, form, controller
- ✅ `TranslationJob` model — enums, validations, scopes, `chapter_range_label`, `cancellable?`
- ✅ `spec/models/translation_job_spec.rb`
- ✅ `spec/factories/translation_jobs.rb`
- ✅ `spec/requests/translation_jobs_spec.rb`
- ✅ `PipelineJob` ActiveJob class — single class, dispatches by job_type
- ✅ `PipelineDispatcher` service — Open3.capture3 shell invocation, uses `novel.directory_name`
- ✅ `TranslationJobsController` — index, show, create, destroy (cancel)
- ✅ Routes — `resources :translation_jobs` nested under `:novels`
- ✅ Views — index (with trigger form), show (output/error), _form partial
- ✅ `run_preread.py` — non-interactive wrapper, calls `src.preread.runner.run_preread`
- ✅ `run_review.py` — non-interactive wrapper, auto-applies edits without prompting
- ✅ `db/import/idols_rewind_bible.rb` — updated to set `directory_name: "idols-rewind"`
- ✅ DECISIONS.md updated (3 new entries)
- ✅ SCHEMA.md updated
- 🔲 `rails db:migrate` — run to apply M10 migrations
- 🔲 `rails runner db/import/idols_rewind_bible.rb` — backfill `directory_name` on existing novel
- 🔲 `rspec` — confirm all specs pass

> **bible_build note:** No standalone non-interactive Python entry point exists yet.
> The Rails job infrastructure is fully built — triggering a bible_build job creates
> a TranslationJob record, enqueues PipelineJob, and PipelineDispatcher returns a
> stub message explaining the limitation. Implement by adding `run_bible_build.py`
> and updating `PipelineDispatcher#run_bible_build_stub`.

---

## Milestone 11 — Deployment
**Status: 🔲 Not Started**

Kamal deployment to Oracle Cloud Ampere ARM VM. Nginx reverse proxy. Cloudflare SSL.

Deliverables:
- Dockerfile suitable for ARM64 (Oracle Ampere)
- Kamal config (`config/deploy.yml`)
- Nginx config with Cloudflare Origin Certificate
- Environment variables in Rails encrypted credentials
- `kamal deploy` succeeds from local machine
- App accessible via custom domain over HTTPS
- Coexistence with forex bot verified (no resource contention)

---

## Milestone 12 — Search
**Status: 🔲 Not Started**
**Scope: Post-MVP. Built once as a complete feature — not incrementally.**

Hybrid PostgreSQL search: pgvector (semantic/embedding) + tsvector (keyword/Korean text).
No separate search service.

Design decisions deferred to this milestone:
- Which fields to embed
- Which embedding model to use
- How to handle Korean text
- How to weight semantic vs. keyword results

Deliverables:
- pgvector extension queries implemented (enabled from Milestone 5)
- tsvector keyword search implemented
- Cross-novel and series-scoped search across all bible categories
- Search UI integrated into bible views
- RSpec specs passing
