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

# Phase 4 — Upload Redesign ✅ Complete

Goal: replace the two-panel chapter upload form with a unified, adaptive upload experience
that catches problems before submission and detects file language from content.

| Milestone | Summary |
|-----------|---------|
| M22 — Unified Chapter Upload | Replace two-panel layout with a single unified upload experience; language detected from file content; per-file review table with chapter number pre-fill |

---

# Phase 5 — Translator Workflow 🔄 In Progress

Goal: reshape the novel show page into a tabbed workspace and build the primary
translator loop — upload → auto-preread → translate — as a first-class, in-app flow.
By the end of this phase, a translator should be able to work an entire novel without
leaving the novel show page or touching the jobs index.

| Milestone | Summary |
|-----------|---------|
| M23 — Novel Show: Tabbed Layout | Header block with genre badge + progress bar; four-tab strip (Chapters, Bible, Review disabled, Voice Calibration disabled); Turbo Frame lazy-load per tab; `tabs_controller.ts` |
| M24 — Chapters Tab + Download Cleanup | Wire Chapters tab panel; remove download columns from chapter table (move to chapter show); Upload + inert Translate Chapters buttons in tab action area |
| M25 — Bible Tab | Wire Bible tab panel; bible views work correctly inside Turbo Frame context; in-frame breadcrumb for deep navigation |
| M26 — Chapter Table: Display States + Inline Actions | Job-derived display badges (`uploaded`, `prereading`, `preread-failed`, `preread`); ▶ Translate primary action; ▶ Preread recovery action; `TranslationJob.preread_covering` scope |
| M27 — Bulk Translation Modal | "Translate Chapters" modal with chapter checklist, select/deselect all, live count; `bulk_create` action; `bulk_translate_controller.ts` |
| M28 — Auto-Preread on Upload | Enqueue preread job automatically on chapter upload (single and bulk); ▶ Preread becomes pure recovery path |

Full Phase 5 detail: inline below (to be archived to `docs/archive/ROADMAP_phase5.md` on completion)

---

## Workflow Model

Understanding this model is prerequisite to all M26–M28 work.

**Single chapter upload:**
upload → chapter saved → one preread `TranslationJob` created
(`chapter_start == chapter_end == N`) → `PipelineJob` enqueued automatically →
preread runs in background → on completion, chapter shows ▶ Translate

**Bulk upload (N chapters):**
upload → chapters saved → one preread `TranslationJob` created covering the full
range (e.g. `chapter_start: 1, chapter_end: 20`) → `PipelineJob` enqueued
automatically → preread runs in background → user reviews preread output (bible
entries, terminology) → ▶ Translate available per chapter or via bulk modal

**Manual ▶ Preread button — recovery path only:**
Shown exclusively on chapters where auto-preread is stranded:
- No preread job record exists (enqueue itself failed)
- Preread job is `failed`
Under normal operation this button is never visible. It is not a primary workflow
action and is not available as a re-run shortcut after a successful preread.

**Chapter state/button mapping (drives M26 display logic):**

| Condition | Visual badge | Action button |
|---|---|---|
| No preread job exists (enqueue failed) | `uploaded` | ▶ Preread (recovery) |
| Preread job `queued` or `running` | `prereading` | — (auto in progress) |
| Preread job `failed` | `preread failed` | ▶ Preread (recovery) |
| Preread job `completed`, chapter `untranslated` | `preread` | ▶ Translate |
| Chapter `translated` | `translated` | — |
| Chapter `reviewed` | `reviewed` | — |

Note: `uploaded`, `prereading`, `preread failed`, and `preread` are display-only
states derived at render time from job records. They are not stored on the `Chapter`
model. The `Chapter#status` enum remains `untranslated | translated | reviewed`.

---

## Milestone 23 — Novel Show: Tabbed Layout
**Status: 🔲 Not Started**

Restructure `novels/show` from a vertical stack of sections into a persistent header
block + four-tab strip. The header holds novel identity and progress at a glance. The
tabs hold Chapters, Bible, Review, and Voice Calibration as peer workspaces.

### Scope

**Header block**
- Cover art slot (existing Active Storage attachment — already wired at M21)
- Genre badge (e.g. "FANT") derived from `@novel.genre`
- Title (serif), Korean title, summary
- Progress bar with `X/Y · Z%` label — `reviewed / total` chapters
  (bar represents finished work; translated-but-unreviewed is still in flight)
- Edit / Remove actions stay in the header

**Tab strip**
- Tabs: Chapters · Bible · Review · Voice Calibration
- Chapters and Bible are fully functional (wired in M24 and M25 respectively)
- Review and Voice Calibration rendered `aria-disabled` with a "Coming soon" tooltip —
  present in DOM, non-interactive, visually muted
- Active tab tracked by `tabs_controller.ts`; selection persisted to `sessionStorage`
  so navigating away and back restores the last active tab

**Tab panels**
- Each panel is a `<turbo-frame>` with a `src` that lazy-loads on first activation
- Frame src targets the existing nested resource routes:
  `novel_chapters_path`, `novel_bible_path`, etc.
- Controllers respond to frame requests by suppressing breadcrumb + page header
  (redundant inside the tab context)

**Removed from novel show**
- Current three-section layout (chapter summary tiles, Bible link, Jobs link) removed
- "View all N chapters →" and "Translation Jobs" buttons removed
- Jobs section deliberately dropped — jobs surface via status badges and a dedicated
  Jobs page (see Future section below)

### New files
- `app/javascript/controllers/tabs_controller.ts`
- CSS additions to `app/assets/stylesheets/_novels.css`:
  `.novel-tabs`, `.novel-tab`, `.novel-tab--active`, `.novel-tab--disabled`,
  `.novel-show__header-block`, `.novel-show__progress-label`

### Tests
- System spec: tab strip renders on novel show
- System spec: clicking Chapters tab loads the frame
- System spec: clicking Bible tab loads the frame
- System spec: disabled tabs are non-clickable (`aria-disabled`, no navigation)
- System spec: active tab is restored after navigation (sessionStorage)
- Existing `novels_forms_spec.rb` and `dashboard_novels_spec.rb` — verify no
  regressions on novel show structure

---

## Milestone 24 — Chapters Tab + Download Column Cleanup
**Status: 🔲 Not Started**

Wire the Chapters tab panel and remove download columns from the chapter table.

### Scope

**Download column removal**
- Remove "Korean Source" and "Translated Output" download columns from `chapters/index`
- Both download links move to `chapters/show` — already present there; needs a visual
  pass to make them prominent (clear download buttons, not just links)
- `download_korean_source` and `download_translated_output` routes and controller
  actions are unchanged

**Chapters tab panel**
- `chapters#index` responds to Turbo Frame requests: suppresses breadcrumb + page
  header, renders table only
- Breadcrumb and page-level "Upload Chapter(s)" button remain on the standalone
  `chapters/index` page for direct URL navigation
- "Upload Chapters" button in the tab action area on `novels/show` — links to
  `new_novel_chapter_path`
- "Translate Chapters" button in the tab action area — present but inert until M27;
  renders as a disabled button with tooltip "Available after chapters are pre-read"

**Progress bar denominator**
- `reviewed / total` as stated in M23; confirmed here as it depends on chapter data
  loaded in `novels#show`

### Tests
- System spec: chapter table renders inside the Chapters tab frame
- System spec: download columns absent from the chapter table
- System spec: chapter show page has prominent Korean source + translated output
  download buttons
- System spec: standalone `chapters/index` (direct URL) still renders correctly with
  its own breadcrumb and upload button
- Update `chapters_jobs_spec.rb`: remove expectations on download columns in table

---

## Milestone 25 — Bible Tab
**Status: 🔲 Not Started**

Wire the Bible tab panel. Bible views exist from M17; this milestone makes them work
correctly inside the tab frame context.

### Scope

**Bible tab panel**
- `bible#show` responds to Turbo Frame requests: suppresses breadcrumb + page header
- Bible landing page (search bar + category cards) renders inside the frame
- Navigation to a category index or entry show from inside the frame stays within the
  frame — standard `link_to` and Turbo handle this naturally
- A lightweight "← Bible" breadcrumb shown inside the frame for deep navigation
  (category index, entry show) since the outer novel header is not visible from
  within the frame

**Combobox search**
- No changes to `combobox_controller.ts` — search results are links; navigation
  works inside a frame

### Tests
- System spec: Bible tab loads the bible landing page inside the frame
- System spec: navigating to a category index from the Bible tab stays in the frame
- System spec: navigating back from a category index returns to the bible landing
- System spec: search bar works inside the tab (input → results → click result)
- Existing bible system specs — verify no regressions on standalone bible routes

---

## Milestone 26 — Chapter Table: Display States + Inline Actions
**Status: 🔲 Not Started**

Add job-derived display states to the chapter table and the two inline action buttons
(▶ Translate as primary path; ▶ Preread as recovery only). See Workflow Model above
for the full state/button mapping.

### Scope

**Display-only status badges (new variants)**
The existing `status_badge` component gets four new visual variants. These are never
stored on `Chapter` — they are derived at render time from job records:

| Variant | Colour | Meaning |
|---|---|---|
| `uploaded` | neutral grey | No preread job record exists (enqueue failed) |
| `prereading` | amber, muted | Preread job queued or running |
| `preread-failed` | red | Preread job failed |
| `preread` | amber | Preread completed; ready to translate |

The existing `untranslated / translated / reviewed` stored statuses continue to drive
badge rendering for `translated` and `reviewed` chapters as before.

**Query — no N+1**
`chapters#index` preloads preread jobs for all chapters in one query. A dedicated
scope on `TranslationJob` encapsulates the lookup:
`TranslationJob.preread_covering(chapter_numbers)` — returns a hash keyed by chapter
number for O(1) lookup in the template. The controller passes this as
`@preread_jobs_by_chapter`.

**Inline action column**
New rightmost column in the chapter table. Renders one of:
- ▶ Preread — when display state is `uploaded` or `preread-failed` (recovery path)
- ▶ Translate — when display state is `preread` (primary path)
- empty — for `prereading`, `translated`, `reviewed`

Each button POSTs to `translation_jobs#create` with the chapter's number as both
`chapter_start` and `chapter_end`. No new route needed.

**Single-chapter translate confirmation**
Clicking ▶ Translate opens a lightweight confirmation modal before submitting.
Reuses existing `dialog_controller.ts` / `modal_controller.ts` pattern.
Message: "Translate Chapter N? This will queue a translation job."

### Tests
- System spec: `uploaded` badge shown when no preread job exists for chapter
- System spec: `prereading` badge shown when preread job is queued or running
- System spec: `preread-failed` badge + ▶ Preread recovery button when job failed
- System spec: `preread` badge + ▶ Translate button when preread completed
- System spec: `translated` badge, no action button
- System spec: `reviewed` badge, no action button
- System spec: clicking ▶ Preread (recovery) submits a preread job
- System spec: clicking ▶ Translate opens confirm modal; confirming submits a
  translate job
- Request spec: `translation_jobs#create` with `chapter_start == chapter_end`
- Model spec: `TranslationJob.preread_covering` returns correct hash and handles
  chapters with no job record
- No N+1: verify `chapters#index` query count does not grow with chapter count

---

## Milestone 27 — Bulk Translation Modal
**Status: 🔲 Not Started**

Build the "Translate Chapters" modal. Replaces the inert button added in M24.

### Scope

**Modal content**
- Title: "Bulk Translation"
- Subtitle: "Run translation on pre-read chapters of [Novel Title]."
- Chapter checklist: lists only chapters in `preread` display state (i.e.
  `untranslated` with a completed preread job) — same set as chapters showing
  ▶ Translate in the table
- Each row: checkbox + chapter icon + "Chapter N" label
- "Select all / Deselect all" toggle link
- Running count: "N selected" (right-aligned, updates live)
- Submit button: "▶ Translate N Chapters" — disabled when N = 0, label updates live

**Submission**
- New `translation_jobs#bulk_create` action: accepts an array of chapter numbers,
  creates one `TranslationJob` per chapter, enqueues each with `PipelineJob.perform_later`
- Responds with redirect + flash notice: "N translation jobs queued."
- Route: `POST /novels/:novel_id/translation_jobs/bulk`
- `bulk_create` validates that each submitted chapter number has a completed preread
  job; silently skips any that do not (guards against stale modal state)

**Stimulus controller**
- `bulk_translate_controller.ts` — manages checkbox state, running count, button
  label, select/deselect all. No server round-trips until submit.

**Bible warning state (Image 2) — explicitly deferred**
Not in scope for M27. Tracked in Future section. Modal goes straight to chapter
checklist (Image 1 behaviour only).

### Tests
- System spec: "Translate Chapters" button opens the modal (no longer inert)
- System spec: modal shows only chapters in `preread` display state
- System spec: selecting / deselecting updates count and button label
- System spec: "Deselect all" unchecks all; "Select all" re-checks all
- System spec: submitting queues jobs and redirects with flash notice
- System spec: submit button disabled when no chapters selected
- Request spec: `bulk_create` creates correct number of `TranslationJob` records
- Request spec: `bulk_create` skips chapter numbers without a completed preread job
- Request spec: `bulk_create` enqueues one `PipelineJob` per created job

---

## Milestone 28 — Auto-Preread on Upload
**Status: 🔲 Not Started**

Enqueue a preread job automatically when a chapter with a Korean source is uploaded.
This makes the ▶ Preread button (M26) a pure recovery path — under normal operation
it is never shown.

### Scope

**Single chapter upload**
After successful save of a chapter with Korean source attached, create one
`TranslationJob` (`job_type: preread`, `chapter_start == chapter_end == N`) and
enqueue `PipelineJob.perform_later`. Chapter immediately shows `prereading` badge.

**Bulk upload**
After all chapters are saved, create one `TranslationJob` covering the full range
(`chapter_start: min_number, chapter_end: max_number`) and enqueue one `PipelineJob`.
Job is created after the loop — not inside it — to avoid partial-enqueue
inconsistency if some files fail to save.

The range format `"#{chapter_start}-#{chapter_end}"` is what `PipelineDispatcher`
already passes to `run_preread.py --chapters`. No dispatcher changes needed.

**Flash notice update**
- Single: "Chapter uploaded. Preread queued."
- Bulk: "N chapter(s) uploaded. Preread queued for all."

**Enqueue failure handling**
If a chapter saves but job enqueue fails, the chapter is still created. The chapter
shows the `uploaded` badge (no job record) and the ▶ Preread recovery button from
M26 is the manual fallback. No rollback of the chapter save on enqueue failure.

**No model or migration changes** — `Chapter#status` enum is unchanged.

### Tests
- Request spec: POST to `chapters#create` with Korean file creates a preread
  `TranslationJob` and enqueues a `PipelineJob`
- Request spec: bulk upload of N Korean files creates one `TranslationJob` with
  `chapter_start` = lowest number, `chapter_end` = highest number
- Request spec: upload of an English file does not create a preread job
  (English = translated output; preread is for Korean source only)
- Request spec: if `PipelineJob.perform_later` raises, chapter record is still
  persisted and no unhandled exception reaches the user
- System spec: flash notice after single upload mentions "Preread queued"
- System spec: flash notice after bulk upload mentions "Preread queued for all"
- System spec: after upload, chapter shows `prereading` badge (job is queued)
- System spec: ▶ Preread recovery button is NOT shown when a preread job exists
  in any state (queued, running, completed, or failed is handled separately)

---

# Future Features

---

## Future — Bible Warning in Bulk Translation Modal

When the bulk translation modal opens, if any selected chapters have unreviewed bible
entries generated by their preread, the user should be prompted to review them first.

Requires:
1. A `reviewed` flag (or equivalent) on bible entries — not currently in schema
2. A relationship between a preread `TranslationJob` and the bible entries it generated
3. A query answering "do any selected chapters have unreviewed preread bible entries?"

Once those exist the modal flow becomes:
- No unreviewed entries → straight to chapter checklist (Image 1 — already built M27)
- Unreviewed entries → warning state first (Image 2):
  - "N unreviewed Bible entries" warning block
  - "Review Bible Entries First" → navigates to Bible tab filtered to unreviewed entries
  - "Skip review and translate anyway" → proceeds to chapter checklist

---

## Future — Re-run Preread

Explicit re-run of preread on a chapter that already has a completed preread job.
Use cases not yet defined — deliberately out of scope until the use case is understood.

---

## Future — Jobs Page

A dedicated page showing all translation jobs across all novels, with status badges,
filtering by novel / status / type, and cancellation for queued jobs.

The existing `translation_jobs` routes and views are the foundation. The novel show
page deliberately drops the jobs section in M23 — this is the replacement.

---

## Future — Review Tab

Connected to the post-translation review pipeline step (`run_review.py` /
`post_translation_review` job type). Exact feature scope TBD.

**Tab present but disabled from M23 onward.**

---

## Future — Voice Calibration Tab

Connected to voice/style calibration for the translation pipeline. Exact scope TBD.

**Tab present but disabled from M23 onward.**

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
