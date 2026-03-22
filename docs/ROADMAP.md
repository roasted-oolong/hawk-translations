# Hawk Translations — Roadmap

Status key: ✅ Done · 🔄 In Progress · 🔲 Not Started

Full Phase 1 detail: `docs/archive/ROADMAP_phase1.md`

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

# Phase 2 — Frontend & Usability

Goal: make the application usable for a solo translator working daily.
See docs/UI.md for CSS approach, component inventory, and design token conventions.

---

## Milestone 13 — Frontend Infrastructure & Pipeline Completion
**Status: ✅ Complete**

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
**Status: ✅ Complete**

Foundation for every other view. Design tokens, CSS structure, and nav shell
established. uipro design system generator run against "internal SaaS tool
translation management dashboard" — Soft UI Evolution + blue-slate palette selected.

Deliverables:
- ✅ Design system generated via uipro — Soft UI Evolution, blue-slate palette, Inter variable font
- ✅ `app/assets/fonts/inter/` — `inter-variable.woff2` + `inter-variable-italic.woff2` (self-hosted)
- ✅ `app/assets/stylesheets/application.css` — CSS custom properties (all design tokens), `@font-face`, `@import` chain
- ✅ `app/assets/stylesheets/_reset.css` — thin reset on top of modern-normalize CDN
- ✅ `app/assets/stylesheets/_typography.css` — heading scale, body defaults, text utilities
- ✅ `app/assets/stylesheets/_layout.css` — app shell, content container, card, page-header
- ✅ `app/assets/stylesheets/_nav.css` — fixed top nav bar
- ✅ `app/assets/stylesheets/_flash.css` — flash message bar (notice + alert variants)
- ✅ `app/assets/stylesheets/_buttons.css` — btn base + variants (primary, secondary, ghost, danger)
- ✅ `app/assets/stylesheets/_login.css` — login page standalone layout
- ✅ `app/views/components/_icon.html.erb` — SVG icon component (x-mark, arrow-right-start-on-rectangle, google)
- ✅ `app/views/layouts/_nav.html.erb` — top nav bar with app name and sign-out button
- ✅ `app/views/layouts/_flash.html.erb` — flash partial wired to flash_controller
- ✅ `app/views/layouts/application.html.erb` — updated with nav, flash, modern-normalize CDN link
- ✅ `app/views/sessions/new.html.erb` — styled login page (logo glyph, app name, Google sign-in button)
- ✅ `app/javascript/controllers/flash_controller.ts` — auto-dismiss Stimulus controller
- ✅ `app/javascript/controllers/index.ts` — flash controller registered
- ✅ `spec/system/m14_layout_spec.rb` — login renders, nav renders, sign-out works
- ✅ UI.md — design token tables finalized, stylesheet structure documented, login page notes recorded
- ✅ DECISIONS.md — M14 entries (palette, font, icon component, flash behaviour, login flash)

---

## Milestone 15 — Dashboard, Novel Index & Novel Show
**Status: ✅ Complete**

The core daily entry points. The app is navigable as a real product after this milestone.

Deliverables:
- ✅ `app/controllers/dashboard_controller.rb` — queries novels via NovelTeamAssignment; no bypass for any user
- ✅ `app/controllers/novels_controller.rb` — `index` eager-loads chapters + jobs for card; `show` adds `@bible_counts`
- ✅ `app/models/user.rb` — `has_many :memberships`, `has_many :teams through: :memberships`, `has_many :translation_jobs` added (missing from M5)
- ✅ `app/views/dashboard/index.html.erb` — assigned novels grid, empty state
- ✅ `app/views/novels/index.html.erb` — novel cards grid, empty state
- ✅ `app/views/novels/show.html.erb` — novel header, chapter status summary, bible category grid, jobs link
- ✅ `app/views/novels/_card.html.erb` — novel card component (title, Korean title, series, chapter progress, pending jobs)
- ✅ `app/views/layouts/_breadcrumb.html.erb` — breadcrumb partial, `[label, path]` array interface
- ✅ `app/assets/stylesheets/_breadcrumb.css` — breadcrumb trail styles
- ✅ `app/assets/stylesheets/_dashboard.css` — dashboard section, empty state
- ✅ `app/assets/stylesheets/_novels.css` — novel grid, novel card, novel show layout
- ✅ `app/assets/stylesheets/_layout.css` — `.page-header__row` added (title + action button layout)
- ✅ `app/assets/stylesheets/application.css` — `_breadcrumb`, `_dashboard`, `_novels` added to import chain
- ✅ `spec/system/m15_dashboard_novels_spec.rb` — 22 examples, all passing
- ✅ `rspec` — full suite passing
- ✅ UI.md updated — breadcrumb and novel card patterns documented
- ✅ DECISIONS.md updated — M15 entries

---

## Milestone 16 — Chapter List & Translation Jobs
**Status: ✅ Complete**

The most-used views during active translation work. After this milestone the daily
workflow (upload → trigger job → monitor → download) is fully usable.

Deliverables:
- ✅ `app/views/chapters/index.html.erb` — chapter table with status badges, upload button, download links
- ✅ `app/views/chapters/new.html.erb` — file upload form (single + bulk panels)
- ✅ `app/views/chapters/show.html.erb` — status badge, file download card
- ✅ `app/views/translation_jobs/index.html.erb` — job list with status badges + trigger form
- ✅ `app/views/translation_jobs/show.html.erb` — job detail, result payload, Turbo Frame polling
- ✅ `app/views/translation_jobs/_form.html.erb` — styled trigger form
- ✅ `app/views/components/_status_badge.html.erb` — status badge component (chapter + job statuses)
- ✅ `app/javascript/controllers/poll_controller.ts` — Stimulus controller; calls `frame.reload()` every 3s; only mounted when job is active
- ✅ `app/assets/stylesheets/_chapters.css` — data table base, chapter show, upload panels, shared form primitives
- ✅ `app/assets/stylesheets/_jobs.css` — status badge variants, jobs trigger card, job detail page
- ✅ `app/assets/stylesheets/application.css` — `_chapters`, `_jobs` added to import chain
- ✅ `spec/system/m16_chapters_jobs_spec.rb` — 40 examples, all passing
- ✅ `rspec` — full suite passing, no regressions
- ✅ UI.md updated — chapter/jobs page notes, badge component, polling pattern documented
- ✅ DECISIONS.md updated — M16 polling decision recorded

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
