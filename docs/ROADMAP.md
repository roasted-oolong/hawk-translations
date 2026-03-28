# Hawk Translations — Roadmap

Status key: ✅ Done · 🔄 In Progress · 🔲 Not Started

Full Phase 1 detail: `docs/archive/ROADMAP_phase1.md`
Full Phase 2 detail: `docs/archive/ROADMAP_phase2.md`
Full Phase 3 detail: `docs/archive/ROADMAP_phase3.md`

---

# Phase 1 — Backend ✅ Complete

| Milestone | Summary |
|-----------|---------|
| M1 — Rails App Generation | `rails new` at repo root; PostgreSQL connected; RSpec passing |
| M2 — Rails MCP Server | MCP server verified; schema + route inspection confirmed |
| M3 — Fix config.py PROJECT_ROOT | `PROJECT_ROOT` reads from `HAWK_PROJECT_ROOT` env var |
| M4 — Authentication | Google OAuth via OmniAuth; session auth; all routes protected |
| M5 — Core Multi-Tenant Schema | Organization, Team, Membership, Novel, Series; pgvector enabled |
| M6 — Novel Team Assignments | `NovelTeamAssignment` join table; permission level enum; no enforcement yet |
| M7 — Chapter Management | Chapter model; Active Storage upload/download; status tracking |
| M8 — Bible Entry Tables & Views | Five bible tables (characters, locations, terminology, cultural_phrases, story_entries); full CRUD |
| M9 — Bible Data Migration | `world_building` enum added; idols-rewind bible imported via `db/import/` |
| M10 — Translation Job Invocation | `TranslationJob` model; `PipelineJob`; `PipelineDispatcher`; Solid Queue; job UI |
| M11 — Deployment | Kamal to Oracle Cloud AMD E2; Cloudflare Full Strict; `hawk-translations.com` live |
| M12 — Search (API layer) | pgvector + tsvector hybrid search; Voyage AI embeddings; `/bible/search` JSON endpoint |

---

# Phase 2 — Frontend & Usability ✅ Complete

Goal: make the application usable for a solo translator working daily.

| Milestone | Summary |
|-----------|---------|
| M13 — Frontend Infrastructure | TypeScript + esbuild replaces importmaps; Cuprite system spec driver; `app/views/components/` registered; `run_bible_build.py` written; Node.js layer added to Dockerfile |
| M14 — Layout, Navigation & Login | Design tokens + full CSS stylesheet structure; Inter self-hosted; nav bar; flash messages; styled login page |
| M15 — Dashboard, Novel Index & Show | Dashboard queries via `NovelTeamAssignment`; novel cards grid; novel show with chapter summary + bible link |
| M16 — Chapter List & Translation Jobs | Chapter table with status badges + download links; upload forms (single + bulk); jobs index with trigger form; job show with Turbo Frame polling |
| M17 — Bible Views | Bible landing page with search bar + category cards; all five category index/show/new/edit views; `combobox_controller.ts` wired to search endpoint |
| M18 — Forms & Polish | Novel new/edit forms; modal confirmation system replacing all `turbo_confirm` call sites; toast infrastructure; mobile stacking; accessibility pass |

---

# Phase 3 — Dashboard Redesign ✅ Complete

Goal: sidebar navigation, gallery-style novel cards with cover art, and a refined dashboard layout.

| Milestone | Summary |
|-----------|---------|
| M18.5 — Design System Reconciliation | Editorial palette; Newsreader serif; `--color-surface-manuscript` token; token-only changes |
| M19 — Sidebar Navigation | Two-bar app shell (fixed sidebar + slim topbar); fixed bottom nav on mobile; `sidebar_controller` removed |
| M20 — Novel Card Layout Shell | Gallery card rewrite; serif title; progress bar placeholder; cover placeholder |
| M21 — Wire Data + Cover Art Upload | Real progress bar; `cover_art` Active Storage attachment; cover upload on novel forms |

---

# Phase 4 — Upload Redesign 🔄 In Progress

Goal: replace the two-panel chapter upload form with a unified, adaptive upload experience
that catches problems before submission and detects file language from content.

---

## Milestone 22 — Unified Chapter Upload
**Status: ✅ Complete**

Replace the two-panel layout (`new.html.erb`: bulk panel + single panel) with a single
unified upload experience. The user selects or drops any number of files. The interface
immediately shows a per-file review table. Language (Korean vs English) is detected from
**file content** on both client and server — filename is never used to infer language.
Chapter number is extracted from the **filename** as a convenience; if unparseable, the
user fills in the number manually before submitting. No status select anywhere on the form.

# Future Features

---

## Future — Novel Upload (Bulk Chapter Detection)

When a user uploads a single file that contains an entire novel (e.g. a combined `.txt`
file), the app should split it into chapters automatically. Chapter boundaries would be
detected from heading patterns in the file content.

This is deferred because it requires a different upload path and a non-trivial parsing
heuristic. It should be designed as an extension to the upload form introduced at M22,
not as a separate entry point.

Prerequisites:
- M22 unified upload complete
- Agreed chapter boundary detection format (headings, delimiters, etc.)

Roadmap entry to be created when prerequisites are met.

---

## Future — Multi-team Novel Assignment

`AutoAssignNovel` currently assigns every new novel to `current_user.teams.first`.
This is correct for a solo translator with one team. When a user belongs to
multiple teams (e.g. a translator who is a member of two orgs, or an org with
multiple specialist teams), the assignment target must be explicit.

Options to evaluate at that milestone:
- A team selector added to the novel creation form
- Assignment derived from the org selected during novel creation
- A post-creation assignment UI on the novel show page

Prerequisite: invite flow and multi-team membership are in scope first.

---

## Future — Data Cleanup: poc_user_id

`novels.poc_user_id` is currently `nil` for all seeded/imported novels.
Add a one-time task or admin UI to assign the POC user on existing records.
For new novels, `poc_user_id` should default to `current_user` at creation time.
