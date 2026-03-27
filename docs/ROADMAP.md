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
**Status: 🔄 In Progress**

Replace the two-panel layout (`new.html.erb`: bulk panel + single panel) with a single
unified upload experience. The user selects or drops any number of files. The interface
immediately shows a per-file review table. Language (Korean vs English) is detected from
**file content** on both client and server — filename is never used to infer language.
Chapter number is extracted from the **filename** as a convenience; if unparseable, the
user fills in the number manually before submitting. No status select anywhere on the form.

### Core design principles

**Language detection from content, not filename — on both sides.**
A file's language is determined by scanning its text for Hangul characters (Unicode block
U+AC00–U+D7A3). If >50% of non-whitespace, non-ASCII characters are Hangul, the file is
classified as Korean source; otherwise classified as translated output. This threshold
handles real-world translated files that quote the original Korean in footnotes or
translator notes. The same detection logic runs client-side (via `FileReader` before
upload) and server-side (on the uploaded stream). The filename plays no role in language
classification on either side.

**Chapter number from filename as a convenience, not a gate.**
The system tries to extract a chapter number from the filename using two patterns only
(see below). If it succeeds, the review table pre-fills the number field. If it fails,
the field is left blank and the user enters it manually. Upload is not blocked by an
unparseable filename — only by a missing or invalid number at submission time.

**Filename conventions (recommended, not enforced).**
These conventions make the number-extraction step reliable. Using them means the review
table fills in automatically with no manual input required:

| Convention | Example |
|------------|---------|
| `{N}화.txt` | `3화.txt`, `제3화.txt` |
| `Chapter {N}.txt` | `Chapter 3.txt`, `Chapter 3 - Some Title.txt` |

Any other filename is accepted. Language is still detected from content; the user provides
the chapter number manually.

**Status inferred from language.**
- Korean source → status `untranslated`
- Translated output → status `translated`
No status select on the upload form.

**Client-side preview; server-side authority.**
The review table is rendered entirely client-side by `upload_review_controller.ts` using
the `FileReader` API — no round-trip for the preview step. The server re-runs language
detection and number validation on submit and is the final authority. Both sides apply
identical rules; the client provides immediate feedback, the server enforces correctness.

### Service (`app/services/chapter_file_classifier.rb`)

Single-responsibility service. Given an IO-like object (file stream) and a filename:
- Reads a sample of the file content (first 4KB)
- Returns `language` (`:korean` or `:english`) — always set, derived from content only
- Returns `chapter_number` (Integer or nil) — extracted from filename only, using exactly
  two patterns (tried in order, first match wins):
  1. `{N}화` anywhere in the basename — e.g. `3화.txt`, `제3화.txt`
  2. `Chapter {N}` at the start of the basename — e.g. `Chapter 3.txt`, `Chapter 3 - Title.txt`
- If neither pattern matches, `chapter_number` is nil — no integer fallback

### Controller (`app/controllers/chapters_controller.rb`)

- Remove `extract_chapter_number` private method — replaced by `ChapterFileClassifier`
- `create_bulk` — for each file:
  - Instantiate `ChapterFileClassifier.new(file, file.original_filename)` and call `classify`
  - `language: :korean` → attach to `korean_source`, status `untranslated`
  - `language: :english` → attach to `translated_output`, status `translated`
  - `chapter_number` nil → read from submitted `chapter[numbers][filename]` param
    (a number input in the review row, submitted with the form)
  - Number still nil or invalid → skip that file, add to flash error list
- `create_single` — same classifier call; number read from `chapter[number]` param;
  status inferred, not submitted
- Remove `:status` from `chapter_params` — no longer a form field

### View (`app/views/chapters/new.html.erb`)

- Remove the two-panel layout entirely
- Single `form_with` posting to `novel_chapters_path`, multipart
- One drop zone (`multiple: true`, accepts `.txt`) controlled by `upload_review_controller`
- After files are selected: a review table appears (rendered client-side into a target div)
- Each review row contains:
  - Filename (display only)
  - Language badge: "Korean" or "English" (detected from content client-side)
  - Chapter number input: `<input type="number" name="chapter[numbers][{filename}]">`
    pre-filled from filename when parseable; blank and editable otherwise
  - Remove button
- Submit button: "Upload {N} file(s)" — disabled until every visible row has a number
- No status select anywhere

### JavaScript (`app/javascript/controllers/upload_review_controller.ts`)

New controller. `file_upload_controller.ts` is removed entirely — its responsibilities
move here or are no longer needed.

**Targets:** `input`, `reviewTable`, `reviewBody`, `submitButton`, `dropZone`

**On file select / drop:**
1. For each file, read first 4096 characters via `FileReader` as text
2. Run Hangul detection: if >50% of non-whitespace non-ASCII chars are Hangul →
   `language = "Korean"`; else `language = "English"`
3. Attempt number extraction from filename (patterns 1 and 2 only — no integer fallback)
4. Render a review row into `reviewBody`
5. Show `reviewTable`, update submit button label, run validation

**On number input change:** re-run validation (all rows must have a number ≥ 1)

**On remove button click:**
- Remove the file from the internal `DataTransfer` list
- Remove the row from `reviewBody`
- Sync `inputTarget.files` to the updated `DataTransfer`
- Re-run validation; hide `reviewTable` and disable submit if no rows remain

**On submit:** form submits normally — number inputs and file input carry all data

**Hangul detection (same logic as server, expressed in TypeScript):**
```typescript
function isHangul(char: string): boolean {
  const code = char.charCodeAt(0)
  return code >= 0xAC00 && code <= 0xD7A3
}

function detectLanguage(sample: string): "Korean" | "English" {
  const nonAsciiNonSpace = Array.from(sample).filter(
    c => c.charCodeAt(0) > 127 && c.trim() !== ""
  )
  if (nonAsciiNonSpace.length === 0) return "English"
  const hangulCount = nonAsciiNonSpace.filter(isHangul).length
  return hangulCount / nonAsciiNonSpace.length > 0.5 ? "Korean" : "English"
}
```

**Number extraction (same two patterns as server):**
```typescript
function extractChapterNumber(filename: string): number | null {
  const base = filename.replace(/\.[^.]+$/, "") // strip extension
  const hwa = base.match(/(\d+)화/)
  if (hwa) return parseInt(hwa[1], 10)
  const chapter = base.match(/^Chapter\s+(\d+)/i)
  if (chapter) return parseInt(chapter[1], 10)
  return null
}
```

**Disconnect:** remove document-level drag listeners (same pattern as `file_upload_controller`)

### Specs (written first)

**Service spec** — `spec/services/chapter_file_classifier_spec.rb`:

Language detection:
- Pure Korean content → `language: :korean`
- Pure English content → `language: :english`
- Mixed content where Hangul > 50% of non-ASCII → `language: :korean`
- Mixed content where Hangul < 50% of non-ASCII → `language: :english`
- Content with no non-ASCII characters (ASCII-only) → `language: :english`

Number extraction (filename only — language content irrelevant to these cases):
- `3화.txt` → `chapter_number: 3`
- `제3화.txt` → `chapter_number: 3`
- `Chapter 3.txt` → `chapter_number: 3`
- `Chapter 3 - Some Title.txt` → `chapter_number: 3`
- `chapter 3.txt` (lowercase) → `chapter_number: 3` (case-insensitive)
- `notes.txt` → `chapter_number: nil`
- `3.txt` (bare integer — no recognised pattern) → `chapter_number: nil`
- `ep3.txt` (no recognised pattern) → `chapter_number: nil`

**Request spec** — `spec/requests/chapters_spec.rb` (replace all upload cases):
- POST file with Korean content → chapter created, `korean_source` attached, status `untranslated`
- POST file with English content → chapter created, `translated_output` attached, status `translated`
- POST mixed files (one Korean-content, one English-content) → correct records for each
- POST file with parseable filename (`3화.txt`) → chapter number taken from filename
- POST file with unparseable filename, number provided in param → number taken from param
- POST file with unparseable filename, no param → file skipped, flash error
- POST duplicate chapter number for same attachment slot → validation error, others succeed
- Single upload: missing number param → `unprocessable_entity`

**System spec** — `spec/system/chapters_jobs_spec.rb` (rewrite upload section from scratch):
- Drop zone renders (`data-testid="upload-zone"`)
- Submit button disabled before files selected
- After attaching a Korean-content `.txt` file: review table appears, language badge shows "Korean"
- After attaching an English-content `.txt` file: review table appears, language badge shows "English"
- Chapter number pre-fills when filename matches a known pattern
- Chapter number field is blank when filename does not match
- Submit button disabled while any row has no chapter number
- Submit button enables once all rows have a number
- Submit button label reflects file count
- Remove button removes its row from the review table
- After removing all rows: review table hidden, submit button disabled

### `data-testid` inventory

| Attribute | Element |
|-----------|---------|
| `upload-zone` | The drop zone wrapper div |
| `upload-review-table` | The review table (`<table>`) |
| `upload-review-row` | Each `<tr>` in the review table |
| `upload-language-badge` | Language badge cell within a row |
| `upload-number-input` | Chapter number input within a row |
| `upload-remove-btn` | Remove button within a row |
| `upload-submit` | The submit button |

### CSS (`_chapters.css`)

- Remove `.upload-panels`, `.upload-panel`, `.upload-panel__header`, `.upload-panel__title`,
  `.upload-panel__description`, `.upload-panel__form`
- Add `.upload-review` — container for the review table; hidden by default; shown by
  controller when rows exist
- Add `.upload-review__table` — inherits `.data-table` styling; column widths: filename
  (flex), language badge (fixed), number (fixed narrow), remove (fixed narrow)
- Add `.upload-language-badge` — pill, same radius as `.status-badge`;
  `.upload-language-badge--korean`: uses untranslated status colours;
  `.upload-language-badge--english`: uses translated status colours

### Docs
- `docs/DECISIONS.md` — unified upload rationale; language detection from content not
  filename; same logic on client and server; `ChapterFileClassifier` service; 50% Hangul
  threshold rationale; no integer fallback rationale
- `docs/UI.md` — update Chapter new page notes; replace File Upload component entry
  with Upload Review component entry
- `docs/CHANGELOG.md` — mark complete when done

---

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
