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

Defined as CSS custom properties on `:root` in `app/assets/stylesheets/application.css`.
All components reference variables, never raw values. Finalized at M14.

### Colour: Base

| Token | Value | Usage |
|-------|-------|-------|
| `--color-bg` | `#F8FAFC` | Page background (slate-50) |
| `--color-surface` | `#FFFFFF` | Cards, panels, nav bar |
| `--color-border` | `#E2E8F0` | Dividers, input borders (slate-200) |
| `--color-border-strong` | `#CBD5E1` | Hover borders, focus rings (slate-300) |

### Colour: Text

| Token | Value | Usage |
|-------|-------|-------|
| `--color-text` | `#0F172A` | Primary body text (slate-900) |
| `--color-text-secondary` | `#475569` | Labels, metadata, captions (slate-600) |
| `--color-text-muted` | `#94A3B8` | Placeholder, disabled (slate-400) |
| `--color-text-inverse` | `#FFFFFF` | Text on dark/accent backgrounds |

### Colour: Brand

| Token | Value | Usage |
|-------|-------|-------|
| `--color-primary` | `#2563EB` | Actions, links (blue-600) |
| `--color-primary-hover` | `#1D4ED8` | Hover state (blue-700) |
| `--color-primary-subtle` | `#EFF6FF` | Hover backgrounds (blue-50) |
| `--color-secondary` | `#64748B` | Secondary actions (slate-500) |
| `--color-accent` | `#7C3AED` | Bible / literary identity (violet-600) |
| `--color-accent-subtle` | `#F5F3FF` | Accent hover backgrounds (violet-50) |

### Colour: Status

| Token | Text | Background | Usage |
|-------|------|------------|-------|
| `untranslated` | `#64748B` | `#F1F5F9` | Chapter not yet started |
| `translated` | `#2563EB` | `#EFF6FF` | Chapter translated, not reviewed |
| `reviewed` | `#059669` | `#ECFDF5` | Chapter reviewed and approved |
| `queued` | `#64748B` | `#F1F5F9` | Job waiting to run |
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
| `--font-family-korean` | `"Apple SD Gothic Neo", "Malgun Gothic", "Nanum Gothic", sans-serif` |
| `--font-family-mono` | `ui-monospace, "SFMono-Regular", Menlo, monospace` |
| `--font-weight-normal` | `400` |
| `--font-weight-medium` | `500` |
| `--font-weight-semibold` | `600` |
| `--font-weight-bold` | `700` |

Inter is self-hosted as a variable font (`inter-variable.woff2`, `inter-variable-italic.woff2`)
in `app/assets/fonts/inter/`. No Google Fonts CDN request. Korean display text uses the
system font stack — no web font loaded for Korean.

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
| `--shadow-xs` | `0 1px 2px rgba(0,0,0,0.05)` |
| `--shadow-sm` | `0 1px 3px rgba(0,0,0,0.08), 0 1px 2px rgba(0,0,0,0.04)` |
| `--shadow-md` | `0 4px 6px rgba(0,0,0,0.07), 0 2px 4px rgba(0,0,0,0.04)` |
| `--shadow-lg` | `0 10px 15px rgba(0,0,0,0.08), 0 4px 6px rgba(0,0,0,0.04)` |

### Transitions

| Token | Value | Usage |
|-------|-------|-------|
| `--transition-fast` | `150ms ease` | State changes, focus rings |
| `--transition-base` | `200ms ease` | Hover effects, flash dismiss |
| `--transition-slow` | `300ms ease` | Modals, complex reveals |

### Layout Constants

| Token | Value | Usage |
|-------|-------|-------|
| `--nav-height` | `3.5rem` (56px) | Fixed nav bar height |
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
  application.css      ← tokens + @font-face + @import chain (entry point)
  _reset.css           ← thin reset on top of modern-normalize
  _typography.css      ← heading scale, body defaults, text utilities
  _layout.css          ← app shell, content container, card, page-header
  _nav.css             ← fixed top nav bar
  _flash.css           ← flash message bar (notice + alert variants)
  _buttons.css         ← btn base + variants (primary, secondary, ghost, danger)
  _login.css           ← login page standalone layout
```

Import order is intentional: tokens must load before any component that references them.

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
  Not a native app — just not broken on small screens.

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
*(to be filled in at M15)*

### Novel Index (`novels/index`)
*(to be filled in at M15)*

### Novel Show (`novels/show`)
*(to be filled in at M15)*

### Chapter List (`chapters/index` + embedded in `novels/show`)
*(to be filled in at M16)*

### Translation Jobs (`translation_jobs/index` + `translation_jobs/show`)
*(to be filled in at M16)*

### Bible Views
*(to be filled in at M17)*

### Forms (new/edit)
*(to be filled in at M18)*
