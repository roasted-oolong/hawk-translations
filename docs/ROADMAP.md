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
**Status: 🔲 Not Started**

Five separate bible tables: characters, locations, terminology, cultural_phrases, story_entries.
CRUD for all categories. Markdown-style rendered views.

Deliverables:
- All five bible table migrations and models
- Create/edit/delete for each category
- Markdown-style read view per entry
- first_appearance_chapter tracked
- RSpec model and feature specs passing

---

## Milestone 9 — Bible Data Migration (idols-rewind)
**Status: 🔲 Not Started**

One-time import of existing idols-rewind markdown bible files into the database.
Chapter file naming cleanup script also lives here.

Deliverables:
- Migration script for all five bible categories from idols-rewind markdown files
- Chapter file rename script (handles all three existing naming patterns)
- Idols-rewind novel record seeded in the database
- All bible entries verified in the app

---

## Milestone 10 — Translation Job Invocation & Status Tracking
**Status: 🔲 Not Started**

Rails invokes Python pipeline scripts as Solid Queue background jobs.
PREREAD, BIBLE BUILD, POST-TRANSLATION REVIEW jobs triggerable from the UI.
Job status visible in real time.

Deliverables:
- Job record model (novel, user, chapter range, function type, status, result payload)
- Solid Queue workers configured
- PREREAD job invocation working end-to-end
- BIBLE BUILD job invocation working end-to-end
- POST-TRANSLATION REVIEW job invocation working end-to-end
- Job list view with status (queued/running/completed/failed)
- Output/error surfaced from completed/failed jobs
- Cancel queued job
- RSpec job specs passing

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
