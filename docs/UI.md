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

- Persistent top navigation bar across all authenticated pages
- Main content area below the nav — constrained max-width, centered
- Login page: standalone, no nav
- No sidebar — the novel → chapter → job hierarchy is shallow enough for breadcrumbs + top nav

---

## Design Tokens

Defined as CSS custom properties on `:root`. All components reference variables, never
raw values. Specific values decided and recorded at M13.

Categories:
- `--color-*` — background, surface, border, text (primary, secondary, muted), accent, danger
- `--color-status-*` — per-status colors for chapter and job badges
- `--space-*` — spacing scale (4px base unit: 4, 8, 12, 16, 24, 32, 48, 64)
- `--text-*` — font size scale
- `--font-*` — font family, weight
- `--radius-*` — border radii
- `--shadow-*` — box shadows
- `--transition-*` — standard durations and easing

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
after a timeout (notice: 4s, alert: stays until dismissed). Manual close button.

### Nav Bar
**Type:** Layout — no behavior  
**Stimulus controller:** None  
**Partial:** `app/views/layouts/_nav.html.erb`  
**Notes:** App name/logo left, sign-out right. No dropdown menus in MVP.

### Breadcrumb
**Type:** Layout — no behavior  
**Stimulus controller:** None  
**Partial:** `app/views/layouts/_breadcrumb.html.erb`  
**Notes:** Rendered at top of every nested resource view. Built with a simple
helper that accepts an array of `[label, path]` pairs.

### Novel Card
**Type:** Display — no behavior  
**Stimulus controller:** None  
**Inputs:** novel record  
**Partial:** `app/views/novels/_card.html.erb`  
**Notes:** Used in novel index and dashboard. Shows title, Korean title, series,
chapter progress (N translated / N total), visibility badge.

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

- **Contrast:** Text on background minimum 4.5:1 (WCAG AA). Use a contrast checker
  when finalising design tokens at M14.
- **Focus states:** All interactive elements (links, buttons, inputs) have a visible
  focus ring. Do not use `outline: none` without a custom replacement.
- **Cursor:** `cursor: pointer` on all clickable non-link elements (buttons, cards).
- **Reduced motion:** Any CSS animation or transition respects
  `@media (prefers-reduced-motion: reduce)` — either remove or reduce to instant.
- **Semantic HTML:** Use `<button>` for actions, `<a>` for navigation, `<nav>`,
  `<main>`, `<header>` landmarks in the layout. No `<div>` click handlers.
- **Form labels:** Every `<input>` and `<select>` has an associated `<label>`.
  No placeholder-only labelling.
- **ARIA:** Use sparingly and only when semantic HTML is insufficient.
  The modal controller must manage `aria-modal`, `aria-labelledby`, and focus trap.
- **Responsive:** Readable at 375px (mobile), 768px (tablet), 1024px+ (desktop).
  Not a native app — just not broken on small screens.

---

## Page-by-Page Notes

Decisions and notes specific to individual views, recorded as they are built.

### Login (`sessions/new`)
*(to be filled in at M13)*

### Dashboard (`dashboard/index`)
*(to be filled in at M14)*

### Novel Index (`novels/index`)
*(to be filled in at M14)*

### Novel Show (`novels/show`)
*(to be filled in at M14)*

### Chapter List (`chapters/index` + embedded in `novels/show`)
*(to be filled in at M15)*

### Translation Jobs (`translation_jobs/index` + `translation_jobs/show`)
*(to be filled in at M15)*

### Bible Views
*(to be filled in at M16)*

### Forms (new/edit)
*(to be filled in at M17)*
