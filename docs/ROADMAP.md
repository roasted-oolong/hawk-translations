# Hawk Translations — Roadmap

Status key: ✅ Done · 🔄 In Progress · 🔲 Not Started

Full Phase 1 detail: `docs/archive/ROADMAP_phase1.md`
Full Phase 2 detail: `docs/archive/ROADMAP_phase2.md`

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

# Phase 3 — Dashboard Redesign

Goal: sidebar navigation, gallery-style novel cards with cover art, and a refined dashboard layout.

---

# M18.5 — Design System Reconciliation
**Status: ✅ Done**

Editorial slate-blue palette replaces the M14 blue-slate SaaS palette. Newsreader
variable font added as `--font-family-serif`. `--color-surface` split into ambient
(`#f9f9f8`) and manuscript (`#ffffff`) tokens; six component files updated.
`--nav-height` retained; `--sidebar-width` and `--topbar-height` tokens added ahead
of M19. No structural view changes — all existing specs pass.

---

## Milestone 19 — Sidebar Navigation
**Status: ✅ Done**

Replace the fixed top nav bar with a two-element app shell: a fixed left sidebar
for primary navigation and a slim fixed topbar for page-contextual items
(breadcrumb, user, sign-out). No data changes. No design detail. Pure structural
layout — every page must look right and all existing specs must pass before M20 begins.

### CSS & tokens
- `application.css` `:root` — remove `--nav-height` (tokens `--sidebar-width` and `--topbar-height` already present from M18.5)
- `_nav.css` → rename to `_sidebar.css`; `.app-nav` → `.app-sidebar`; fixed left, full height, `--sidebar-width` wide; tonal background separation (no right border — no-line rule); brand mark at top; vertical nav link list with active state via `current_page?`
- New `_topbar.css` — `.app-topbar`: fixed top, `left: var(--sidebar-width)`, `right: 0`, `height: var(--topbar-height)`; left slot: breadcrumb; right slot: user name + sign-out + `yield :topbar_actions`
- `_layout.css` — `.app-main`: replace `padding-top: var(--nav-height)` with `padding-left: var(--sidebar-width)` and `padding-top: var(--topbar-height)`; update any other `--nav-height` references
- `application.css` import chain — replace `@import "_nav"` with `@import "_sidebar"`, add `@import "_topbar"`

### Views & layout
- `app/views/layouts/_nav.html.erb` → `_sidebar.html.erb` — brand mark + vertical nav links (Dashboard, Novels)
- New `app/views/layouts/_topbar.html.erb` — slim bar; breadcrumb yield left, user/sign-out right, `yield :topbar_actions` right slot
- `app/views/layouts/application.html.erb` — render `_sidebar` + `_topbar` instead of `_nav`; authenticated check applies to both

### JavaScript
- New `app/javascript/controllers/sidebar_controller.ts` — mobile toggle: open/close off-canvas sidebar, outside-click dismissal; no other responsibilities
- `app/javascript/controllers/index.ts` — register `sidebar_controller`

### Responsive
- ≤768px: sidebar off-canvas by default; hamburger button in topbar triggers `sidebar_controller`
- ≥769px: sidebar always visible; hamburger hidden

### Specs (written first)
System specs — `spec/system/m19_sidebar_spec.rb`:
- Sidebar renders on every authenticated page
- Topbar renders on every authenticated page
- Sidebar and topbar absent on login page
- Sign-out reachable from topbar
- Dashboard link navigates correctly
- Novels link navigates correctly
- Mobile: hamburger present at narrow viewport; sidebar toggles open/closed

Update existing specs:
- `spec/system/m14_layout_spec.rb` — `data-testid="app-nav"` → `data-testid="app-sidebar"`

### Docs
- `docs/DECISIONS.md` — two-bar layout change, rationale
- `docs/UI.md` — update Layout section; replace Nav Bar component entry with Sidebar + Topbar

---

## Milestone 20 — Novel Card Layout Shell
**Status: ✅ Done**

Rewrite `novels/_card.html.erb` in place with the gallery card structure: cover image
slot, serif title, metadata row, progress bar. All placeholder — no real data wired,
no cover image upload, no active storage. Layout correct and responsive on dashboard
and novel index. Tests pass before M21 begins.

### Views
- `app/views/novels/_card.html.erb` — full rewrite; cover image block (`aspect-ratio: 2/3`, full card width, `--color-surface-low` placeholder background); body section: serif title, Korean title, series/genre metadata row, progress bar (static `width: 0%`), chapter count stat, pending jobs badge when > 0; card remains an `<article>` linking to the novel

### CSS
- `_novels.css` — `.novel-card`: `padding: 0` (cover goes edge-to-edge); `.novel-card__cover`: aspect-ratio block, `overflow: hidden`, placeholder background; `.novel-card__body`: inner padding, flex column, gap; `.novel-card__progress-track` + `.novel-card__progress-fill` (static width for now); `.novel-card__title` switches to serif stack (`var(--font-family-serif)`); review `novel-grid` column floor — `minmax(14rem, 1fr)` likely needed given taller cards; all existing modifier classes carry forward unchanged

### No changes needed
- `app/views/dashboard/index.html.erb` — already renders `novels/card`
- `app/views/novels/index.html.erb` — already renders `novels/card`
- No controllers, models, or migrations

### Specs (written first)
System specs — `spec/system/novel_card_spec.rb`:
- Dashboard: novel card renders with cover placeholder
- Dashboard: novel card title links to novel
- Novel index: novel card renders with cover placeholder
- Novel card: progress bar element is present in the DOM
- Novel card: Korean title renders when present; absent when nil

### Docs
- `docs/DECISIONS.md` — novel card rewritten in place, no variant parameter

---

## Milestone 21 — Wire Data + Cover Art Upload
**Status: ✅ Done**

Replace all card placeholders with real data. Add `cover_art` Active Storage attachment
to `Novel`. Progress bar reflects real chapter completion ratio. Cover image renders when
attached; placeholder remains when not. Cover art upload added to novel new/edit forms.

### Model
- `app/models/novel.rb` — `has_one_attached :cover_art`; validation: `content_type: %w[image/jpeg image/png image/webp]`, `size: { less_than: 5.megabytes }`
- No migration needed — Active Storage tables already exist

### Controllers
- `app/controllers/novels_controller.rb` — add `:cover_art` to `novel_create_params` and `novel_update_params`; add `.with_attached_cover_art` to `index` query; new `destroy_cover_art` action for purge
- `app/controllers/dashboard_controller.rb` — add `.with_attached_cover_art` to novels query to prevent N+1
- `config/routes.rb` — add `delete "cover_art", on: :member, action: :destroy_cover_art` inside novels resources block

### Views
- `app/views/novels/_card.html.erb` — cover block: `if novel.cover_art.attached?` render `image_tag` else placeholder div; progress bar fill: `(translated_count.to_f / total_chapters * 100).round` wired to `style="width: X%"`
- `app/views/novels/new.html.erb` / `edit.html.erb` — add `cover_art` file input using `file_upload_controller.ts` drop zone
- `app/views/novels/_form.html.erb` — cover art input field; edit form: current cover thumbnail when attached + remove button wired to `destroy_cover_art`

### CSS
- `_novels.css` — `.novel-card__cover img`: `width: 100%; height: 100%; object-fit: cover`; no other changes needed

### Specs (written first)
Model specs — `spec/models/novel_spec.rb`:
- Valid without cover art
- Rejects cover art with invalid content type
- Rejects cover art over 5MB

Request specs — `spec/requests/novels_spec.rb`:
- `PATCH /novels/:id` with valid image attaches cover art
- `PATCH /novels/:id` with invalid content type rejected

System specs — `spec/system/m21_cover_art_spec.rb`:
- Dashboard: cover image renders when attached
- Dashboard: placeholder renders when no cover art attached
- Dashboard: progress bar width reflects chapter completion
- Novel form: cover art file input present
- Novel form (edit): current cover thumbnail shown when attached
- Novel form (edit): remove cover art removes the image

### Docs
- `docs/DECISIONS.md` — cover art optional with placeholder; purge via dedicated route; `.with_attached_cover_art` on both queries
- `docs/UI.md` — update novel card component entry: cover image slot, progress bar, N+1 note on query

---

## Future — Multi-team novel assignment

`AutoAssignNovel` currently assigns every new novel to `current_user.teams.first`.
This is correct for a solo translator with one team. When a user belongs to
multiple teams (e.g. a translator who is a member of two orgs, or an org with
multiple specialist teams), the assignment target must be explicit.

Options to evaluate at that milestone:
- A team selector added to the novel creation form
- Assignment derived from the org selected during novel creation
- A post-creation assignment UI on the novel show page

Prerequisite: invite flow and multi-team membership are in scope first.
