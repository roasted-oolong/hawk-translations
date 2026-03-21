# Hawk Translations — Roadmap

Status key: ✅ Done · 🔄 In Progress · 🔲 Not Started

---

# Phase 1 — Backend

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
**Status: ✅ Complete**

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
- ✅ `rails db:migrate` — run to apply M10 migrations
- ✅ `rails runner db/import/idols_rewind_bible.rb` — backfill `directory_name` on existing novel
- ✅ `rspec` — confirm all specs pass

> **bible_build note:** No standalone non-interactive Python entry point exists yet.
> The Rails job infrastructure is fully built — triggering a bible_build job creates
> a TranslationJob record, enqueues PipelineJob, and PipelineDispatcher returns a
> stub message explaining the limitation. Implement by adding `run_bible_build.py`
> and updating `PipelineDispatcher#run_bible_build_stub`.

---

## Milestone 11 — Deployment
**Status: ✅ Done**

> **Architecture note:** Deployed to Oracle Cloud AMD E2 micro (x86_64, 1 OCPU, ~1GB RAM)
> rather than Ampere A1 (ARM64, 24GB) — A1 capacity unavailable at time of deployment.
> ARM64 migration path: change `builder.arch` in deploy.yml to `arm64` and re-deploy.
> No other changes required.
>
> **Stack:** Cloudflare (Full strict) → kamal-proxy:443 (Cloudflare Origin Cert) → Rails container.
> Nginx is not used in production — kamal-proxy handles SSL directly using the Cloudflare
> Origin Certificate passed via `.kamal/secrets`.

Deliverables:
- ✅ `Dockerfile` — Python 3 + venv layer; pipeline deps from `requirements.txt`; amd64 target
- ✅ `config/deploy.yml` — server IP, ghcr.io registry, amd64, WEB_CONCURRENCY=1, RAILS_MAX_THREADS=5, Cloudflare Origin Cert via ssl block, all secrets
- ✅ `.kamal/secrets` — RAILS_MASTER_KEY, HAWK_DATABASE_PASSWORD, DATABASE_URL (×3), ANTHROPIC_API_KEY, GITHUB_TOKEN, KAMAL_PROXY_TLS_CERTIFICATE_PEM, KAMAL_PROXY_TLS_PRIVATE_KEY_PEM
- ✅ `config/environments/production.rb` — `assume_ssl = true`; `force_ssl` off; `config.hosts` set
- ✅ `config/nginx/hawk.conf` — kept in repo for reference; not active in production
- ✅ `config/database.yml` — production uses `172.18.0.1` (kamal network gateway); pool: 10
- ✅ `.dockerignore` — venv, pycache, novel content dirs excluded
- ✅ 2GB swapfile on VM — persisted in `/etc/fstab`
- ✅ PostgreSQL 14 on VM — `hawk` user, 3 databases, pgvector v0.6.0 compiled from source, extensions pre-created as superuser
- ✅ Docker on VM — installed, `ubuntu` user in docker group
- ✅ Nginx installed on VM — not active in production; kept available for future use
- ✅ Cloudflare Origin Certificate — in `/etc/nginx/ssl/` on VM and passed to kamal-proxy via secrets
- ✅ Oracle Cloud security list — ports 80 and 443 open from `0.0.0.0/0`
- ✅ iptables — `172.16.0.0/12` ACCEPT rule; saved via `netfilter-persistent`
- ✅ Domain — `hawk-translations.com` via Cloudflare; A record → `161.153.85.216`; SSL/TLS Full (strict)
- ✅ Google OAuth — production callback URL added to Google Cloud Console
- ✅ Production credentials — `secret_key_base` + Google OAuth in `config/credentials/production.yml.enc`
- ✅ `kamal deploy` — succeeds; app live at https://hawk-translations.com
- ✅ Google sign-in smoke test — passes
- ✅ DECISIONS.md updated (9 new M11 entries)
- ✅ CONVENTIONS.md updated

---

## Milestone 12 — Search
**Status: ✅ Done (API layer)**
**Scope: Post-MVP. Built once as a complete feature — not incrementally.**

Hybrid PostgreSQL search: pgvector (semantic/embedding) + tsvector (keyword/Korean text).
Embedding model: Voyage AI voyage-3-lite (1024 dimensions). API-first — JSON endpoint
serves both human UI and Claude pipeline (Use Case 2). Search UI deferred to next milestone.

Deliverables:
- ✅ `db/migrate/20260320000002_create_bible_embeddings.rb` — `bible_embeddings` table
  with `vector(1024)`, `tsvector`, polymorphic association, denormalized `novel_id` /
  `organization_id`, `content_hash`. Indexes: ivfflat (cosine), GIN, unique embeddable.
- ✅ `app/models/concerns/embeddable.rb` — concern with `#embeddable_text` contract +
  `after_save` hook enqueuing `GenerateEmbeddingJob`
- ✅ All five bible models updated — `include Embeddable` + `#embeddable_text` implemented
- ✅ `app/models/bible_embedding.rb` — polymorphic model, scopes, `stale_for?` class method
- ✅ `app/services/voyage_client.rb` — thin HTTP wrapper, typed errors, reads `voyage_api_key`
  from Rails credentials
- ✅ `app/jobs/generate_embedding_job.rb` — content_hash staleness guard, upsert with
  `to_tsvector` SQL expression, re-raises `ApiError` for Solid Queue retry
- ✅ `app/services/bible_search_service.rb` — hybrid semantic + keyword search, novel or
  org scope, category filter, result merge and dedup
- ✅ `app/controllers/bible_search_controller.rb` — JSON only, 503 on API failure
- ✅ Route: `GET /novels/:novel_id/bible/search` → `bible_search#show`
- ✅ `lib/tasks/embeddings.rake` — `embeddings:backfill[novel_id]` and `embeddings:backfill_all`
- ✅ RSpec specs: concerns, 5 model specs updated, bible_embedding model + factory,
  voyage_client service, generate_embedding_job, bible_search_service, bible_search request
- ✅ `webmock` gem added to Gemfile (test group) for VoyageClient HTTP stubbing
- ✅ SCHEMA.md, DECISIONS.md, ROADMAP.md updated
- ✅ `config/application.rb` — Rails 8.1.2 + Ruby 3.4 `presence` visibility fix
- ✅ `config/initializers/active_record_transaction_fix.rb` — ActiveRecord::Transaction patch
- ✅ `config/active_record.schema_format = :sql` — switched to structure.sql for pgvector compatibility
- ✅ `db/structure.sql` — generated from development database
- ✅ `db/import/idols_rewind_bible.rb` — renamed local `presence` helper to `presence_str`
- ✅ `rake embeddings:backfill[1]` — 122 embedding jobs enqueued for idols-rewind
- ✅ `rspec` — 363 examples, 0 failures

Deferred to next milestone:
- Search UI — Turbo/Stimulus search bar in bible views
- Cross-novel org-scoped search endpoint
- Novel-level embeddings (Use Case 3 — reading platform discovery)
- Chapter content embeddings

Setup steps required:
1. `bundle install` — installs webmock
2. `rails credentials:edit` — add `voyage_api_key: <your_key>`
3. `rails db:migrate` — runs `20260320000002_create_bible_embeddings`
4. `rails runner db/import/idols_rewind_bible.rb` — import bible data
5. `rake embeddings:backfill[<novel_id>]` — enqueue embedding generation
6. `rspec` — confirm all specs pass

---

# Phase 2 — Frontend & Usability

Goal: make the application usable for a solo translator working daily.
See docs/UI.md for CSS approach, component inventory, and design token conventions.

---

## Milestone 13 — Frontend Infrastructure & Pipeline Completion
**Status: 🔲 Not Started**

All tooling and infrastructure that must exist before any UI code is written.
This milestone has no visible UI output — it is purely setup. Nothing in M14+ is
started until this is complete and verified.

### Part A — JavaScript Build Pipeline
- Remove `importmap-rails` gem; add `jsbundling-rails` gem
- Install esbuild: `yarn add esbuild`
- `package.json` with `build` script: `esbuild app/javascript/*.js --bundle --outdir=app/assets/builds`
- `tsconfig.json` at repo root — strict mode, target ESNext
- `app/javascript/application.ts` — replaces `application.js`
- `app/javascript/controllers/application.ts` + `index.ts` — typed Stimulus bootstrap
- `Procfile.dev` — `web: rails server` + `js: yarn build --watch`
- `foreman` gem added (development group) or `overmind` if preferred
- Verify: `yarn build` produces `app/assets/builds/application.js` without errors
- Verify: `rails server` + `yarn build --watch` run together without conflicts
- CONVENTIONS.md and UI.md confirmed accurate (already updated)

### Part B — System Spec Driver
- Choose and install JS-capable Capybara driver: Playwright (`capybara-playwright-driver`) or Cuprite
- `spec/support/system_spec_helper.rb` — driver config, screen size, headless mode
- `spec/system/.keep` — directory created
- Smoke test: one system spec that boots the app, visits login, and passes
- Decision recorded in DECISIONS.md: which driver and why

### Part C — `app/views/components/` Setup
- Create `app/views/components/` directory
- `prepend_view_path Rails.root.join("app/views/components")` added to `ApplicationController`
- Verify render lookup works with a trivial `_smoke_test.html.erb` partial (delete after)

### Part D — `run_bible_build.py` (Pipeline Completion)
- Write `run_bible_build.py` — non-interactive wrapper matching the pattern of `run_preread.py`
  and `run_review.py`; accepts CLI arguments, calls the underlying bible build runner
- Update `PipelineDispatcher#run_bible_build_stub` to call the real script
- Verify bible_build job triggers and completes without the stub message
- DECISIONS.md updated

### Part E — Dockerfile + Deploy Verification
- Add Node.js install layer to Dockerfile (needed for esbuild / yarn)
- Add `yarn build` step to Dockerfile asset compilation stage
- Verify `kamal deploy` succeeds with the updated Dockerfile
- Confirm production app boots and serves JS correctly after deploy

---

## Milestone 14 — Application Layout, Navigation & Login Page
**Status: 🔲 Not Started**

Foundation for every other view. Establishes the design tokens, CSS structure,
and nav shell that all subsequent milestones build on. Run UI UX Pro Max design
system generator before starting to seed color palette and typography decisions.

Deliverables:
- `app/assets/stylesheets/application.css` — CSS custom properties (design tokens), reset import, base typography
- `app/assets/stylesheets/` component files — layout, nav, buttons, tables, forms, flash, badges
- `app/views/layouts/application.html.erb` — updated with nav partial, flash, modern-normalize CDN link
- `app/views/layouts/_nav.html.erb` — top navigation bar with app name and sign-out link
- `app/views/sessions/new.html.erb` — styled login page (logo, sign-in button, clean centered layout)
- System specs: login flow, nav renders, sign-out (M13 driver setup required first)
- UI.md updated — design tokens finalized, layout decisions recorded
- DECISIONS.md updated — color palette and typography choices recorded

---

## Milestone 15 — Dashboard, Novel Index & Novel Show
**Status: 🔲 Not Started**

The core daily entry points. After this milestone the app is navigable as a real product.

Deliverables:
- `app/views/dashboard/index.html.erb` — assigned novels with chapter progress summary, pending jobs count
- `app/views/novels/index.html.erb` — novel cards (title, Korean title, series, chapter count, status)
- `app/views/novels/show.html.erb` — novel header, chapter summary table, bible category counts, jobs link
- Breadcrumb partial introduced (`app/views/layouts/_breadcrumb.html.erb`)
- System specs: dashboard loads, novel index renders, novel show renders
- UI.md updated — card and breadcrumb patterns documented

---

## Milestone 16 — Chapter List & Translation Jobs
**Status: 🔲 Not Started**

The most-used views during active translation work. After this milestone the daily
workflow (upload → trigger job → monitor → download) is fully usable.

Deliverables:
- `app/views/chapters/index.html.erb` — chapter table with status badges, upload button, download links
- `app/views/chapters/new.html.erb` — file upload form (single + bulk)
- `app/views/translation_jobs/index.html.erb` — job list with status badges + trigger form
- `app/views/translation_jobs/show.html.erb` — job output / error display
- `app/views/components/_status_badge.html.erb` — status badge component
- Job status polling via Turbo Streams or meta-refresh (decision at this milestone)
- System specs: chapter list, file upload form, job trigger form, job status display
- UI.md updated — badge component, polling pattern documented

---

## Milestone 17 — Bible Views
**Status: 🔲 Not Started**

The most structurally complex views. Five categories, each with index, show, new, edit.

Deliverables:
- All five bible index views — entry list with key fields visible at a glance
- All five bible show views — markdown-style rendered entry layout
- All five bible new/edit forms — clean, field-labelled forms per category
- Search UI — Turbo/Stimulus combobox wired to the existing `/bible/search` JSON endpoint (deferred from M12)
- System specs: bible index/show per category, search bar interaction
- UI.md updated — bible entry card layout, search bar component documented

---

## Milestone 18 — Forms & Polish
**Status: 🔲 Not Started**

Remaining forms and overall UI consistency pass. The app should feel finished after this.

Deliverables:
- `app/views/novels/new.html.erb` + `edit.html.erb` — styled novel creation/edit form
- `app/views/novels/_form.html.erb` — clean field layout, inline validation errors
- Empty state components — consistent across all index views
- Destructive action confirmation styling — modal controller replaces turbo_confirm where appropriate
- Mobile layout pass — readable on a phone (not a native app, just not broken)
- System specs: novel create/edit form, empty state rendering
- Final UI.md pass — all components and patterns documented
- Final DECISIONS.md pass — any deferred frontend decisions resolved
