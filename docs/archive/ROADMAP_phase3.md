# Hawk Translations — Roadmap Phase 3 Archive

Full milestone detail for Phase 3 (M18.5–M21). Archived after Milestone 21.
Current roadmap: see `docs/ROADMAP.md`.

---

# Phase 3 — Dashboard Redesign

Goal: sidebar navigation, gallery-style novel cards with cover art, and a refined dashboard layout.

---

## Milestone 18.5 — Design System Reconciliation
**Status: ✅ Done**

Editorial slate-blue palette replaces the M14 blue-slate SaaS palette. Newsreader
variable font added as `--font-family-serif`. `--color-surface` split into ambient
(`#f9f9f8`) and manuscript (`#ffffff`) tokens; six component files updated.
`--nav-height` retained; `--sidebar-width` and `--topbar-height` tokens added ahead
of M19. No structural view changes — all existing specs pass.

### Changes
- `application.css` `:root` — replaced `--color-primary: #2563EB` with `#4e6078`;
  `--color-bg` + `--color-surface` both → `#f9f9f8`; added `--color-surface-manuscript: #ffffff`
- `_typography.css` — added `.text-serif`, `.text-serif-display`, `.text-serif-body` utility classes
- Six component stylesheets updated from `--color-surface` → `--color-surface-manuscript` where appropriate
- `application.css` `@font-face` — added Newsreader variable font declarations
  (files in `app/assets/fonts/newsreader/`)

### Docs
- `docs/DECISIONS.md` — editorial palette + Newsreader serif adopted at M18.5

---

## Milestone 19 — Sidebar Navigation
**Status: ✅ Done**

Replace the fixed top nav bar with a two-element app shell: a fixed left sidebar
for primary navigation and a slim fixed topbar for page-contextual items
(breadcrumb, user, sign-out). No data changes. Pure structural layout — every page
must look right and all existing specs must pass before M20 begins.

### CSS & tokens
- `application.css` `:root` — removed `--nav-height`; `--sidebar-width` and `--topbar-height` already present from M18.5
- `_nav.css` → renamed to `_sidebar.css`; `.app-nav` → `.app-sidebar`; fixed left, full height, `--sidebar-width` wide
- New `_topbar.css` — `.app-topbar`: fixed top, `left: var(--sidebar-width)`, `right: 0`, `height: var(--topbar-height)`
- `_layout.css` — `.app-main`: replaced `padding-top: var(--nav-height)` with `padding-left: var(--sidebar-width)` + `padding-top: var(--topbar-height)`
- `application.css` import chain — replaced `@import "_nav"` with `@import "_sidebar"`, added `@import "_topbar"`

### Views & layout
- `app/views/layouts/_nav.html.erb` → `_sidebar.html.erb` — brand mark + vertical nav links (Dashboard, Novels)
- New `app/views/layouts/_topbar.html.erb` — slim bar; breadcrumb yield left, user/sign-out right, `yield :topbar_actions` right slot
- `app/views/layouts/application.html.erb` — renders `_sidebar` + `_topbar` instead of `_nav`

### JavaScript
- `sidebar_controller.ts` — planned as mobile hamburger toggle; removed after mobile nav pattern
  changed to fixed bottom bar (see DECISIONS.md M19 entry)
- New mobile pattern: `_bottom_nav.html.erb` — fixed bottom nav bar at ≤768px; no JavaScript

### Specs
- `spec/system/m19_sidebar_spec.rb` — sidebar renders on every authenticated page; topbar renders;
  both absent on login; sign-out reachable; nav links correct; mobile bottom nav present at narrow viewport

### Docs
- `docs/DECISIONS.md` — two-bar layout rationale; mobile bottom nav pattern change rationale

---

## Milestone 20 — Novel Card Layout Shell
**Status: ✅ Done**

Rewrite `novels/_card.html.erb` in place with the gallery card structure: cover image
slot, serif title, metadata row, progress bar. All placeholder — no real data wired,
no cover image upload, no Active Storage. Layout correct and responsive on dashboard
and novel index.

### Views
- `app/views/novels/_card.html.erb` — full rewrite; cover image block (`aspect-ratio: 2/3`);
  body section: serif title, Korean title, metadata row, progress bar (static `width: 0%`),
  chapter count stat, pending jobs badge when > 0

### CSS
- `_novels.css` — `.novel-card`: `padding: 0`; `.novel-card__cover`: aspect-ratio block,
  `overflow: hidden`, placeholder background; `.novel-card__body`: inner padding, flex column;
  `novel-grid` column floor reduced from `20rem` to `14rem`; serif title stack

### Specs
- `spec/system/novel_card_spec.rb` — cover placeholder renders; title links to novel;
  progress bar element present; Korean title conditional

### Docs
- `docs/DECISIONS.md` — novel card rewritten in place; no variant parameter

---

## Milestone 21 — Wire Data + Cover Art Upload
**Status: ✅ Done**

Replace all card placeholders with real data. Add `cover_art` Active Storage attachment
to `Novel`. Progress bar reflects real chapter completion ratio. Cover image renders when
attached; placeholder remains when not. Cover art upload added to novel new/edit forms.

### Model
- `app/models/novel.rb` — `has_one_attached :cover_art`; content type + size validation
  via two custom `validate` methods (no gem); no migration needed

### Controllers
- `app/controllers/novels_controller.rb` — `:cover_art` in create/update params;
  `.with_attached_cover_art` on index query; new `destroy_cover_art` action
- `app/controllers/dashboard_controller.rb` — `.with_attached_cover_art` on novels query
- `config/routes.rb` — `delete "cover_art", on: :member, action: :destroy_cover_art`

### Views
- `app/views/novels/_card.html.erb` — cover: `cover_art.attached? && cover_art.blob.persisted?`
  guard; progress fill wired to `floor(translated / total * 100)%`
- `app/views/novels/new.html.erb` + `edit.html.erb` — cover art file input; edit form:
  thumbnail + remove button wired to `destroy_cover_art`

### Specs
- `spec/models/novel_spec.rb` — cover art optional; rejects invalid content type; rejects > 5MB
- `spec/requests/novels_spec.rb` — PATCH with valid image attaches; invalid type rejected
- `spec/system/m21_cover_art_spec.rb` — cover image renders when attached; placeholder when not;
  progress bar width reflects ratio; file input present on form; remove cover art works

### Docs
- `docs/DECISIONS.md` — cover art optional with placeholder; purge via dedicated route;
  `.with_attached_cover_art` on both queries; `.floor` vs `.round` rationale;
  `cover_art.blob.persisted?` guard rationale
