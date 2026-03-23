# Hawk Translations — UI & Frontend

Frontend conventions, design decisions, and component patterns.
Companion to CONVENTIONS.md (backend) and DECISIONS.md (all architectural decisions).

---

## JavaScript Approach

TypeScript via `jsbundling-rails` + esbuild. Replaces importmaps.

- All Stimulus controllers written in TypeScript (`.ts`)
- esbuild compiles to `app/assets/builds/` — Propshaft serves from there
- `yarn build --watch` runs alongside `rails server` in development (Foreman / Procfile.dev)
- `tsconfig.json` at repo root — strict mode enabled
- No React, no Vue. Hotwire (Turbo + Stimulus) is the component model.

Rationale: long-term product, open to future collaborators, TypeScript's safety net
earns its setup cost over a multi-year horizon. esbuild is fast enough that the build
step is not felt in daily development. See DECISIONS.md for full rationale.

---

## CSS Approach

Hand-rolled CSS. No framework.

- `app/assets/stylesheets/application.css` — imports all component files via `@import`
- CSS custom properties on `:root` for all design tokens — components reference variables, never raw values
- `modern-normalize` from cdnjs — one `<link>` tag in the layout, no install required
- No Tailwind, no Bootstrap, no external CSS framework

Rationale: view count is small and well-defined. Hand-rolled CSS produces more
intentional, faster output than fighting a framework's opinions for a focused internal
tool. See DECISIONS.md for full rationale.

---

## Layout

Two-bar app shell introduced at M19:

- Fixed left sidebar for primary navigation — `--sidebar-width: 15rem`
- Fixed slim topbar for page-contextual items (breadcrumb, user, sign-out) — `--topbar-height: 3rem`
- Sidebar and topbar absent on the login page
- Main content area offset: `padding-left: var(--sidebar-width)`, `padding-top: var(--topbar-height)`
- On mobile (≤768px): sidebar is off-canvas by default; hamburger in topbar toggles it via `sidebar_controller.ts`

---

## Design Tokens

Defined as CSS custom properties on `:root` in `app/assets/stylesheets/application.css`.
All components reference variables, never raw values. Finalized at M14.

### Colour: Base

| Token | Value | Usage |
|-------|-------|-------|
| `--color-bg` | `#f9f9f8` | Page background |
| `--color-surface` | `#f9f9f8` | Ambient chrome — sidebar, utility panels |
| `--color-surface-manuscript` | `#ffffff` | Document surfaces — cards, panels, dialogs |
| `--color-surface-low` | `#f2f4f3` | Side panels, secondary containers |
| `--color-surface-container` | `#ebeeed` | Utility panels |
| `--color-surface-dim` | `#d4dcda` | Tonal boundary element |
| `--color-border` | `rgba(173,179,178,0.15)` | Ghost border — felt, not seen |
| `--color-border-strong` | `#adb3b2` | Focus rings, explicit dividers |

### Colour: Text

| Token | Value | Usage |
|-------|-------|-------|
| `--color-text` | `#2d3433` | Primary body text — never pure black |
| `--color-text-secondary` | `#5a6672` | Labels, metadata, captions |
| `--color-text-muted` | `#adb3b2` | Placeholder, disabled |
| `--color-text-inverse` | `#f5f7ff` | Text on dark/accent backgrounds |

### Colour: Brand

| Token | Value | Usage |
|-------|-------|-------|
| `--color-primary` | `#4e6078` | Actions, links — editorial slate-blue |
| `--color-primary-hover` | `#42546c` | Hover state |
| `--color-primary-subtle` | `#f2f4f3` | Hover backgrounds |
| `--color-secondary` | `#adb3b2` | Secondary actions |
| `--color-accent` | `#7C3AED` | Bible / literary identity (violet-600) |
| `--color-accent-subtle` | `#F5F3FF` | Accent hover backgrounds (violet-50) |

### Colour: Status

| Token | Text | Background | Usage |
|-------|------|------------|-------|
| `untranslated` | `#5a6672` | `#F1F5F9` | Chapter not yet started |
| `translated` | `#4e6078` | `#e8ecf0` | Chapter translated, not reviewed |
| `reviewed` | `#059669` | `#ECFDF5` | Chapter reviewed and approved |
| `queued` | `#5a6672` | `#F1F5F9` | Job waiting to run |
| `running` | `#D97706` | `#FFFBEB` | Job actively running |
| `completed` | `#059669` | `#ECFDF5` | Job finished successfully |
| `failed` | `#DC2626` | `#FEF2F2` | Job failed |

### Colour: Flash Messages

| Token | Value | Usage |
|-------|-------|-------|
| `--color-flash-notice-text` | `#065F46` | Notice text (emerald-800) |
| `--color-flash-notice-bg` | `#D1FAE5` | Notice background (emerald-100) |
| `--color-flash-notice-border` | `#6EE7B7` | Notice border (emerald-300) |
| `--color-flash-alert-text` | `#991B1B` | Alert text (red-800) |
| `--color-flash-alert-bg` | `#FEE2E2` | Alert background (red-100) |
| `--color-flash-alert-border` | `#FCA5A5` | Alert border (red-300) |

### Typography

| Token | Value |
|-------|-------|
| `--font-family` | `"Inter", ui-sans-serif, system-ui, sans-serif` |
| `--font-family-serif` | `"Newsreader", Georgia, "Times New Roman", serif` |
| `--font-family-korean` | `"Apple SD Gothic Neo", "Malgun Gothic", "Nanum Gothic", sans-serif` |
| `--font-family-mono` | `ui-monospace, "SFMono-Regular", Menlo, monospace` |
| `--font-weight-normal` | `400` |
| `--font-weight-medium` | `500` |
| `--font-weight-semibold` | `600` |
| `--font-weight-bold` | `700` |

Newsreader is self-hosted as a variable font (`Newsreader-VariableFont_opsz,wght.woff2`,
`Newsreader-Italic-VariableFont_opsz,wght.woff2`) in `app/assets/fonts/newsreader/`.
Inter is self-hosted as a variable font (`inter-variable.woff2`, `inter-variable-italic.woff2`)
in `app/assets/fonts/inter/`. Neither font is committed to the repo — drop in before running
the app. Korean display text uses the system font stack — no web font loaded for Korean.

### Type Scale

| Token | Value | px equiv |
|-------|-------|---------|
| `--text-xs` | `0.75rem` | 12px |
| `--text-sm` | `0.875rem` | 14px |
| `--text-base` | `1rem` | 16px |
| `--text-lg` | `1.125rem` | 18px |
| `--text-xl` | `1.25rem` | 20px |
| `--text-2xl` | `1.5rem` | 24px |
| `--text-3xl` | `1.875rem` | 30px |

### Spacing (4px base unit)

| Token | Value |
|-------|-------|
| `--space-1` | `0.25rem` (4px) |
| `--space-2` | `0.5rem` (8px) |
| `--space-3` | `0.75rem` (12px) |
| `--space-4` | `1rem` (16px) |
| `--space-5` | `1.25rem` (20px) |
| `--space-6` | `1.5rem` (24px) |
| `--space-8` | `2rem` (32px) |
| `--space-10` | `2.5rem` (40px) |
| `--space-12` | `3rem` (48px) |
| `--space-16` | `4rem` (64px) |

### Border Radius

| Token | Value | Usage |
|-------|-------|-------|
| `--radius-sm` | `0.25rem` | Badges, tags |
| `--radius-md` | `0.5rem` | Inputs, buttons |
| `--radius-lg` | `0.75rem` | Cards, panels |
| `--radius-xl` | `1rem` | Modals |
| `--radius-full` | `9999px` | Pills |

### Shadows

| Token | Value |
|-------|-------|
| `--shadow-xs` | `0 1px 2px rgba(45,52,51,0.04)` |
| `--shadow-sm` | `0 1px 3px rgba(45,52,51,0.06), 0 1px 2px rgba(45,52,51,0.03)` |
| `--shadow-md` | `0 12px 32px -4px rgba(45,52,51,0.06)` |
| `--shadow-lg` | `0 12px 32px -4px rgba(45,52,51,0.08), 0 4px 8px rgba(45,52,51,0.04)` |

### Transitions

| Token | Value | Usage |
|-------|-------|-------|
| `--transition-fast` | `150ms ease` | State changes, focus rings |
| `--transition-base` | `200ms ease` | Hover effects, flash dismiss |
| `--transition-slow` | `300ms ease` | Modals, complex reveals |

### Layout Constants

| Token | Value | Usage |
|-------|-------|-------|
| `--sidebar-width` | `15rem` (240px) | Fixed left sidebar width |
| `--topbar-height` | `3rem` (48px) | Slim contextual topbar height |
| `--content-max-width` | `72rem` (1152px) | Content container |
| `--content-padding-x` | `1.5rem` | Horizontal page padding |

### Z-index Scale

| Token | Value |
|-------|-------|
| `--z-base` | `10` |
| `--z-dropdown` | `20` |
| `--z-nav` | `30` |
| `--z-modal` | `50` |

---

## Stylesheet Structure

```
app/assets/stylesheets/
  application.css      ← tokens + @font-face (Newsreader + Inter) + @import chain
  _reset.css           ← thin reset on top of modern-normalize
  _typography.css      ← heading scale, body defaults, text utilities, serif utilities
  _layout.css          ← app shell, content container, card, page-header
  _sidebar.css         ← fixed left sidebar (replaces _nav.css at M19)
  _topbar.css          ← slim fixed topbar (new at M19)
  _flash.css           ← flash message bar (notice + alert variants)
  _buttons.css         ← btn base + variants (primary, secondary, ghost, danger)
  _login.css           ← login page standalone layout
  _breadcrumb.css      ← breadcrumb trail
  _dashboard.css       ← dashboard section layout, empty state
  _novels.css          ← novel grid, novel card, novel show layout
  _chapters.css        ← data table base, chapter show, upload panels, form primitives
  _jobs.css            ← status badge, jobs trigger card, job detail page
  _bible.css           ← bible landing, category cards, search bar, entry detail
  _modal.css           ← confirmation dialog, toast notifications
```

Import order is intentional: tokens must load before any component that references them.
`_nav.css` is superseded by `_sidebar.css` + `_topbar.css` and is no longer imported.

---

## Icon Component

All icons rendered via `app/views/components/_icon.html.erb`. No inline SVGs in views or
partials. Icons are sourced from Heroicons 2.x (outline style, MIT licence).

Usage:
```erb
<%= render "components/icon", name: "x-mark", size: 16 %>
<%= render "components/icon", name: "arrow-right-start-on-rectangle", size: 16, css_class: "icon--muted" %>
```

Supported names (add to the component as needed per milestone):
- `x-mark` — close / dismiss
- `arrow-right-start-on-rectangle` — sign out
- `google` — Google G logo (sign-in button only)

---

## Component Inventory

Every reusable UI pattern identified before M13 begins. Built once, reused everywhere.
Each component entry records: what it is, what inputs/states it has, whether it needs
a Stimulus controller, and where the partial lives once built.

All component partials live in `app/views/components/`. This directory is registered
as an additional view path via `prepend_view_path Rails.root.join("app/views/components")`
in `ApplicationController`, allowing partials to be rendered as `render "status_badge"`
rather than the full path. Set up at M13.

> **Caveat:** `prepend_view_path` applies to controller-rendered views. Partials rendered
> from *within other partials* use the calling template's view path, not the controller's.
> When rendering a component from inside another partial, use the explicit path:
> `render "components/status_badge"`. This is consistent and safe everywhere; prefer
> the explicit form in all partials to avoid lookup ambiguity.

### Icon
**Type:** Display only — no behavior
**Stimulus controller:** None
**Inputs:** name (string), size (integer, default 16), css_class (string, optional)
**Partial:** `app/views/components/_icon.html.erb`
**Notes:** Single component for all SVG icons. Add new icons here as needed. Never
inline SVGs in views or partials.

### Status Badge
**Type:** Display only — no behavior  
**Stimulus controller:** None  
**Inputs:** status string  
**States (chapter):** `untranslated` · `translated` · `reviewed`  
**States (job):** `queued` · `running` · `completed` · `failed`  
**Partial:** `app/views/components/_status_badge.html.erb`  
**Notes:** Single partial, CSS class driven by status value. Used in chapter table,
job list, and novel show summary.

### Flash Message
**Type:** Display + auto-dismiss behavior  
**Stimulus controller:** `flash_controller.ts`  
**Inputs:** type (notice/alert), message string  
**States:** visible, dismissing, dismissed  
**Partial:** `app/views/layouts/_flash.html.erb`  
**Notes:** Rendered in the application layout above main content. Auto-dismisses
after 4s (notice only — alerts require manual dismissal). Manual close button on
both variants.

### Sidebar
**Type:** Layout — no behavior at desktop; toggle behavior at mobile
**Stimulus controller:** `sidebar_controller.ts` (mobile toggle only)
**Partial:** `app/views/layouts/_sidebar.html.erb`
**Notes:** Fixed left, full height. Tonal background separation — no right border.
Active link state via `current_page?`. Collapses off-canvas at ≤768px.

### Topbar
**Type:** Layout — no behavior
**Stimulus controller:** None
**Partial:** `app/views/layouts/_topbar.html.erb`
**Notes:** Slim fixed bar, `left: var(--sidebar-width)`. Left slot: breadcrumb
(`yield :breadcrumb`). Right slot: user name, sign-out, and optional page action
(`yield :topbar_actions`).

### Breadcrumb
**Type:** Layout — no behavior  
**Stimulus controller:** None  
**Partial:** `app/views/layouts/_breadcrumb.html.erb`  
**Interface:** `crumbs:` — array of `[label, path]` pairs. Last item is the current
page and renders as plain text (no link) regardless of whether a path is supplied.  
**Usage:**
```erb
<%= render "layouts/breadcrumb", crumbs: [
      ["Novels", novels_path],
      [@novel.title, nil]
    ] %>
```
**Notes:** Rendered at the top of every nested resource view, above the page header.
`data-testid="breadcrumb"` present for system specs.

### Novel Card
**Type:** Display — no behavior
**Stimulus controller:** None
**Inputs:** `novel:` record — must have chapters and translation_jobs preloaded;
`with_attached_cover_art` must be called on the query (enforced at M21) to avoid N+1
**Partial:** `app/views/novels/_card.html.erb`
**Notes:** Gallery-style card. Cover image area (`aspect-ratio: 2/3`) at top, full card
width, `overflow: hidden` clips to card border-radius. At M20: `--color-surface-low`
placeholder div. At M21: renders `image_tag` when `cover_art.attached?`, placeholder
otherwise. Cover area is wrapped in a link to the novel (`aria-hidden="true"
tabindex="-1"`) — decorative only; screen readers navigate via the title link.
Title uses serif font stack (`--font-family-serif`). Progress bar fill is static
`width: 0%` at M20; wired to chapter completion ratio at M21. Pending jobs badge
renders only when queued + running count > 0. Card has no root padding — cover goes
edge-to-edge; body section carries its own inner padding. Used on both dashboard and
novel index; grid context controls rendered width.

**data-testid attributes (M20):**
- `novel-card` — card root
- `novel-card-cover-link` — cover `<a>` (href assertions in specs)
- `novel-card-cover` — cover block (presence check)
- `novel-card-korean-title` — Korean title span (conditional)
- `novel-card-progress` — progress bar track (presence check)
- `novel-card-jobs-badge` — pending jobs badge (conditional)

### Data Table
**Type:** Layout — no behavior  
**Stimulus controller:** None  
**Notes:** Not a partial — a CSS class pattern applied to `<table>` elements.
Consistent styling for chapter list and job list tables.

### Modal / Dialog
**Type:** Interactive  
**Stimulus controller:** `modal_controller.ts`  
**Inputs:** trigger element, dialog content (via Turbo Frame or inline slot)  
**States:** closed, open  
**Behavior:** Open on trigger click. Close on backdrop click, Escape key, or
explicit close button. Focus trapped inside while open.  
**Implementation:** Native HTML `<dialog>` element. No external library.  
**Notes:** Used for delete confirmations (replacing `turbo_confirm` where richer
UI is needed) and potentially bible entry quick-view.

### Toast Notification
**Type:** Display + behavior  
**Stimulus controller:** `toast_controller.ts`  
**Inputs:** message, type (success/error/info)  
**States:** entering, visible, leaving  
**Behavior:** Appears from bottom-right, auto-dismisses after 4s, stacks if
multiple fire simultaneously.  
**Notes:** For job completion feedback via Turbo Streams — "Job completed" / "Job failed"
without a full page reload. Separate from flash messages (which are page-load only).

### Combobox / Search Input
**Type:** Interactive  
**Stimulus controller:** `combobox_controller.ts`  
**Inputs:** search endpoint URL, placeholder  
**States:** idle, focused, loading, results-visible, empty  
**Behavior:** Debounced input → fetch suggestions from `/novels/:id/bible/search`
JSON endpoint → render results list → keyboard navigation (up/down/enter/escape).  
**Notes:** Used in bible views wired to the existing search API endpoint (built at M12).
This is the most complex controller in the app — deserves its own milestone step.

### File Upload
**Type:** Interactive  
**Stimulus controller:** `file_upload_controller.ts`  
**Inputs:** accept types, multiple flag  
**States:** idle, dragging-over, files-selected, uploading  
**Behavior:** Drag-and-drop target + click-to-browse. Shows selected filenames
before submit. Multi-file support for bulk chapter upload.  
**Notes:** Wraps the existing chapter upload form — no backend changes needed.

---

## Stimulus Controller Conventions

- All controllers in `app/javascript/controllers/`, named `*_controller.ts`
- Targets and values typed explicitly — no `any`
- Controllers do one thing — split if a controller is doing two unrelated things
- No direct DOM queries outside of Stimulus targets — `this.targets` only
- Side effects (fetch, timers) cleaned up in `disconnect()`

---

## Turbo Usage Patterns

- Full-page navigation for primary transitions (dashboard → novel → chapter → jobs)
- Turbo Frames for inline edits where surrounding context should stay stable
- Turbo Streams for job status updates — patch status badge in place without full reload
- `data-turbo="false"` on OAuth buttons (already in place)

---

## View Conventions

- Breadcrumb partial at top of every nested resource view
- Flash messages rendered in the layout above main content
- Empty states: every index view has an explicit empty state, not a blank page
- Tables: chapter list, job list
- Cards: novel index, dashboard novel summary
- Destructive actions: `data: { turbo_confirm: "..." }` already in place; upgrade to
  modal controller where richer confirmation UI is warranted

---

## Accessibility Baseline

Applied consistently across all views. Verified during M18 polish pass.

- **Contrast:** All text meets WCAG AA (4.5:1 minimum). Token values verified against
  their backgrounds at M14.
- **Focus states:** All interactive elements have a visible focus ring (`2px solid
  var(--color-primary)` with `2px offset`). Do not use `outline: none` without a
  custom replacement.
- **Cursor:** `cursor: pointer` on all clickable non-link elements (buttons, cards).
- **Reduced motion:** `@media (prefers-reduced-motion: reduce)` in `_reset.css` disables
  all transitions and animations globally. Individual components do not need to repeat this.
- **Semantic HTML:** Use `<button>` for actions, `<a>` for navigation, `<nav>`,
  `<main>`, `<header>` landmarks in the layout. No `<div>` click handlers.
- **Form labels:** Every `<input>` and `<select>` has an associated `<label>`.
  No placeholder-only labelling.
- **ARIA:** Use sparingly and only when semantic HTML is insufficient.
  The modal controller must manage `aria-modal`, `aria-labelledby`, and focus trap.
- **Responsive:** Readable at 375px (mobile), 768px (tablet), 1024px+ (desktop).
  Not a native app — just not broken on small screens. Full mobile polish pass at M18.

---

## Page-by-Page Notes

Decisions and notes specific to individual views, recorded as they are built.

### Login (`sessions/new`)

Standalone page — no nav bar, no `app-main` padding offset. The application layout
suppresses the nav entirely when `authenticated?` is false.

Structure: full-viewport flex container → centered card (max-width 384px) → logo
glyph (鷹, rendered in Korean system font stack, violet accent) → app name → tagline
→ Google sign-in button.

The login page renders its own inline flash alert for OAuth failures (e.g.
`/auth/failure`). The layout flash is also rendered but sits above the nav offset
region, so the inline version is the visible one on this page.

Sign-in button uses `btn--google` variant — full-width, outline style, Google G logo
icon from the `_icon` component.

### Dashboard (`dashboard/index`)

Entry point after sign-in. Single section: "My Novels" — a grid of novel cards for
novels assigned to the current user's teams via `NovelTeamAssignment`. No bypass for
any user. Empty state shown when no assignments exist, with a hint to contact an Org
Admin. "Browse all novels →" link to `novels_path` always present.

Novel cards are preloaded with chapters and translation_jobs in the controller — no
N+1 queries. Pending jobs count covers queued + running statuses.

`data-testid="dashboard-heading"` on the `<h1>`, `data-testid="dashboard-empty"` on
the empty state, `data-testid="novel-card"` on each card.

### Novel Index (`novels/index`)

Browsing/management view. Shows all novels in the system (not filtered by assignment —
this is distinct from the dashboard). Novel grid using `_card` partial. Empty state
with a "Create the first novel" CTA. "New Novel" button in the page header row.

`data-testid="novels-index"` on the wrapper div, `data-testid="novels-empty"` on the
empty state, `data-testid="novel-card"` on each card.

### Novel Show (`novels/show`)

Three sections below the page header: chapter summary, bible category grid, jobs link.

**Page header:** title (`data-testid="novel-title"`), Korean title (system font stack),
meta row (series, genre, visibility), summary paragraph. Edit + Remove buttons in the
header row. Breadcrumb: Novels → novel title.

**Chapter summary** (`data-testid="novel-chapters-summary"`): three status count
tiles (untranslated / translated / reviewed) computed from preloaded chapters in Ruby.
"View all N chapters →" link to `novel_chapters_path`. Upload button in section header.
Empty state message when no chapters exist.

**Bible summary** (`data-testid="novel-bible-summary"`): five cards in an `auto-fill`
grid, one per category. Each card shows the category name (linked to the category index)
and the entry count. Accent color (`--color-accent-subtle` background, `--color-accent`
link color) gives the bible section a distinct visual identity.

**Jobs section:** heading + "Translation Jobs" button linking to
`novel_translation_jobs_path`. No inline job list — that lives at M16.

Mobile note: `.novel-show__section-header` (flex space-between), `.chapter-status-summary`
(horizontal flex), and `.bible-summary-grid` need stacking rules at narrow widths.
Deferred to M18 mobile polish pass.

### Chapter List (`chapters/index`)

Table view of all chapters for a novel, ordered by chapter number.

Structure: breadcrumb → page header (title + "Upload Chapter(s)" button) → data table or empty state.

Table columns: `#` (linked to chapter show), `Title`, `Status` (badge), `Korean Source` (download link or —), `Translated Output` (download link or —), Actions (Edit + Remove).

Empty state has a CTA link to `new_novel_chapter_path`.

`data-testid="chapters-table"` on the table, `data-testid="chapters-empty"` on the empty state.

**Chapter show** (`chapters/show`): breadcrumb → page header (chapter number + optional title, Edit + Remove buttons, status badge) → files card with Korean Source and Translated Output download buttons.

**Chapter new** (`chapters/new`): breadcrumb → page header → two-panel upload grid. Left panel: bulk upload (multiple files, numbers parsed from filenames). Right panel: single upload (explicit number, optional title, file, status select). `data-testid="bulk-upload-fieldset"` and `data-testid="single-upload-fieldset"`.

Form primitives (`.form-group`, `.form-label`, `.form-input`, `.form-select`, `.form-hint`, `.form-actions`, `.form-errors`) defined in `_chapters.css` — shared with the jobs trigger form.

### Translation Jobs (`translation_jobs/index` + `translation_jobs/show`)

**Index** (`translation_jobs/index`): breadcrumb → page header → trigger form card → divider → job table or empty state.

Trigger form in a `.card.jobs-trigger` wrapper. Fields: job type select, chapter start, chapter end. `data-testid="job-trigger-form"` on the card wrapper.

Table columns: Type, Chapters, Status (badge), Triggered by, Started, Actions (View link + Cancel button for queued jobs only). `data-testid="jobs-table"` on the table, `data-testid="jobs-empty"` on the empty state.

**Show** (`translation_jobs/show`): breadcrumb → page header (job type title + Cancel button if queued) → polled status frame → output block or pending message.

Polling: the `<turbo-frame id="job-status">` is wrapped in `data-controller="poll" data-poll-interval-value="3000"` **only when the job is active** (queued or running). `poll_controller.ts` calls `frame.reload()` every 3s. When the job reaches a terminal state, the wrapper div is absent — the controller never connects and polling stops automatically. No cleanup logic needed.

Output block (`data-testid="job-output"`): monospace `<pre>` with `result_payload`. Pending message (`data-testid="job-pending-message"`): shown when active with no output yet.

`data-testid="job-detail"` on the page header div.

### Status Badge (`components/_status_badge.html.erb`)

Single component for all status values across chapters and jobs.

Usage:
```erb
<%= render "components/status_badge", status: chapter.status %>
<%= render "components/status_badge", status: job.status %>
```

Outputs `<span class="status-badge status-badge--{status}" data-testid="status-badge">`. CSS modifier class is derived directly from the status string. Token values per status defined in `application.css` (all `--color-status-*` variables). Styles in `_jobs.css`.

### Bible Views

#### Bible Landing Page (`bible/show`)

Entry point for the translation bible. Breadcrumb: Novels → Novel Title → Bible.

Structure: page header (title "Translation Bible", novel subtitle) → search bar →
five category cards in an `auto-fill` grid.

**Search bar** (`.bible-search`): positioned above the category grid, max-width 36rem.
The `combobox` Stimulus controller mounts on the wrapper div and receives the search
endpoint URL via `data-combobox-url-value`. The input (`data-combobox-target="input"`,
`data-action="input->combobox#search"`) triggers a debounced fetch. Results render
in a positioned dropdown (`.bible-search__dropdown`) containing a `<ul role="listbox">`
(`data-testid="bible-search-results"`). Each result shows the entry label and a
category pill. An empty state (`data-testid="bible-search-empty"`) is shown when
the query returns no results. Both dropdown and empty state use the `hidden` attribute
— the controller toggles them via the `results` and `empty` targets.

**Category cards** (`.bible-category-grid` / `.bible-category-card`): five cards,
one per category. Each carries `data-testid="bible-category-card"` and
`data-category="{slug}"` for system spec targeting. Card structure: title link →
description text → footer with entry count and "entry/entries" label.
Accent color identity: card title uses `--color-accent`, hover border uses
`--color-accent`, count uses `--color-text`.

`data-testid="bible-landing"` on the `.bible-landing` wrapper.

#### Category Index Views

All five follow the same pattern: breadcrumb → page header (title + "Add X" button) →
data table or empty state.

Table `data-testid` attributes: `characters-table`, `locations-table`,
`terminology-table`, `cultural-phrases-table`, `story-entries-table`.
Empty state `data-testid` attributes: `characters-empty`, `locations-empty`,
`terminology-empty`, `cultural-phrases-empty`, `story-entries-empty`.

Korean name/term/phrase columns use `.bible-td--korean` for the system font stack.

Story entries index groups entries by category using `@entries_by_category`. Each
populated category renders its own `.bible-story__category-section` with a heading
and a `data-table-wrapper` / `data-table` beneath it. All section tables share
`data-testid="story-entries-table"`.

#### Entry Show Views

All five follow the same pattern: breadcrumb → page header (entry title as
`data-testid="entry-title"`, Korean subtitle if present, Edit + Remove buttons) →
`.card.bible-entry` content card.

The content card structure:
- `.bible-entry__meta` — flex row of quick-reference label/value pairs (role,
  type, established translation, first appearance chapter, etc.)
- `.bible-entry__section` blocks — one per long-form field (description, speech
  pattern, definition, etc.), each with a `.bible-entry__section-title` label
- `.bible-entry__updated-at` — timestamp footer

Established translation on cultural phrase show uses
`.bible-entry__meta-value--highlight` (accent color, semibold).

#### New / Edit Forms

All five follow the same pattern: breadcrumb → page header → `.card` wrapping the
form partial.

Form partial structure: error block (`data-testid="form-errors"`) → two-column
`.bible-form__grid` for short fields (name, Korean name, role, first appearance) →
full-width `form-group` blocks for long-form text areas → `.form-actions` (Save +
Cancel).

`data-testid="bible-entry-form"` on the `<form>` element (via `data: { testid: }` on
`form_with`).

#### Combobox Controller (`combobox_controller.ts`)

Targets: `input`, `results`, `empty`.
Values: `url` (String) — the search endpoint URL.

Result paths are derived at runtime by stripping `/bible/search` from the URL value
and appending `/bible_characters/:id`, `/bible_locations/:id`, etc. No hardcoded
paths. The `CATEGORY_LABELS` and `recordLabel` helpers map `embeddable_type` strings
to display labels and primary name fields respectively.

Keyboard behaviour: ArrowDown/ArrowUp move the `.bible-search__result--active` class
through result items; Enter clicks the active item's `<a>`; Escape calls `close()`.
Outside-click handled via a document-level listener registered in `connect()` and
removed in `disconnect()`.

### Forms (new/edit)
*(to be filled in at M18)*
