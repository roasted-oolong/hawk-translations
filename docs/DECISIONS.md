# Hawk Translations — Decisions Log

Architectural and product decisions with rationale. Append-only.
Format: date · decision · why.

---

## 2026-03 · Rails app at repo root, not `rails/` subdirectory

The PRD specified a `rails/` subdirectory. After reviewing the actual repo,
all Python pipeline files live at root level. Nesting Rails one level deeper
adds path complexity to Kamal config, Nginx config, and all documentation
with no benefit. Rails generated at root; Python pipeline is a peer directory.

---

## 2026-03 · App name: `hawk`

Short, unambiguous, no collision with any class names. Full name
"Hawk Translations" appears in UI copy only.

---

## 2026-03 · Auth: Google OAuth via OmniAuth, not `has_secure_password`

PRD is source of truth. System prompt said `has_secure_password` but that
was stale. Google OAuth is the correct approach per PRD §2.6.
`has_secure_password` would require an invite/password flow we're not building.

---

## 2026-03 · Enums stored as strings, not integers

ActiveRecord integer enums are a persistent source of bugs when values are
reordered or inserted. String enums are self-documenting in the database and
safe to extend. Small performance cost is irrelevant at this scale.

---

## 2026-03 · Bible tables: one table per category, not a polymorphic `bible_entries` table

Five separate tables (characters, locations, terminology, cultural_phrases, story_entries).
Each category has materially different columns. A single polymorphic table would
require many nullable columns or a JSONB blob — both make validation and querying
harder. Separate tables are explicit, validatable, and indexable per category.

---

## 2026-03 · pgvector enabled at Milestone 5, used at Milestone 12

Extension enabled early so production database never needs a migration that
adds an extension to a live, populated database. Cost is negligible.

---

## 2026-03 · TranslationJob model name (not `Job`)

`Job` collides conceptually with ActiveJob internals and would be confusing.
`TranslationJob` is unambiguous and self-documenting.

---

## 2026-03 · Solid Queue, no Redis

Rails 8 built-in. No additional infrastructure on the Oracle VM.
The VM runs a forex bot; keeping dependencies minimal reduces operational
surface area. Revisit only if Solid Queue proves insufficient at scale.

---

## 2026-03 · No Action Cable, no WebSockets for job status

Job status updates via Turbo Streams over HTTP polling. Simpler infrastructure,
sufficient for the use case. A translator checking job status every few seconds
is not a hard real-time requirement.

---

## 2026-03 · User model created in full at Milestone 4, not split across M4 and M5

SCHEMA.md lists User under Milestone 5 (core multi-tenant schema). In practice,
all User columns are auth columns — email, name, provider, uid, platform_admin.
Creating the model in full at M4 avoids a second users migration at M5 with no
downside. ROADMAP and SCHEMA.md updated to reflect this. M5 adds no users migration.

---

## 2026-03 · Organization has_many :members through :teams

Added `has_many :memberships, through: :teams` and `has_many :members, through: :memberships, source: :user`
to Organization. No migration required — traverses existing tables. Keeps data operations in the database
rather than Ruby (avoids `flat_map(&:users).uniq` in application code). Callers use `.distinct` explicitly
when a user may belong to multiple teams in the same org. Dependent destroy not set on through-associations
— destruction already cascades via `teams: dependent: :destroy`.

---

## 2026-03 · ANTHROPIC_API_KEY stays in .env, not Rails credentials

The Python pipeline reads ANTHROPIC_API_KEY directly from the environment via
`os.environ`. Moving it to Rails encrypted credentials would require the Rails
job runner to explicitly inject it back into the subprocess environment at
Milestone 10 — extra indirection with no current benefit. Left in .env for now.
Revisit at Milestone 10 when job invocation is designed and we control exactly
how the subprocess environment is constructed.

---

## 2026-03 · Request spec sign_in helper drives real OAuth callback, not forged cookies

Initial implementation used ActionDispatch::Cookies internals to forge a signed
session cookie in request specs. This failed — rack-test does not process a
forged cookie header through session middleware the way a real browser would,
so session[:user_id] was never populated. Replaced with a sign_in helper that
hits GET /auth/google_oauth2/callback with a mocked OmniAuth hash, exercising
the real SessionsController#create code path. rack-test maintains session state
correctly across subsequent requests within the same example.

---

## 2026-03 · Bulk upload parses chapter numbers from filenames in ChaptersController

Bulk upload (multiple files at once) has no number field — numbers are parsed from filenames
using two patterns: `ch{N}_korean` and `Chapter_{N}...`. Files that don't match either pattern
are skipped with an error message surfaced in the redirect flash. This logic lives in
`ChaptersController#extract_chapter_number`, a private method, keeping the parsing out of
the model and easy to test or extend without touching Active Record.

---

## 2026-03 · Chapter file naming: already clean, no rename script needed (Milestone 9)

On inspection at Milestone 9, all 74 chapter files already follow the clean naming
convention: `Chapter N.txt` (translated output) and `Chapter N (Korean).txt` (Korean
source). The three legacy patterns documented above were resolved before this milestone.
No rename script required.

---

## 2026-03 · `world_building` added to `BibleStoryEntry` category enum at Milestone 9

The `story.md` bible template includes a World Building section as a first-class
category alongside Main Plot, Subplots, Themes, and Watch List. Although idols-rewind
has no world building content (grounded real-world novel), future novels on the platform
may have magic systems, political structures, or other world-building elements that do
not fit the existing categories. Adding `world_building` now costs one no-op migration
and keeps the schema honest to the feature. A polymorphic workaround or future data
migration would cost more. The category is string-backed with no DB check constraint,
so the change requires no column alteration.

---

## 2026-03 · Bible import script in `db/import/`, not `db/seeds.rb`

`db/seeds.rb` is for data required in every environment on every setup (e.g., lookup
tables, default roles). The idols-rewind bible data is one-time content for a specific
novel — not infrastructure. Placing it in `db/import/idols_rewind_bible.rb` and running
it with `rails runner` makes the intent explicit: this is a one-time migration of
existing content, not a seed that should run on every `db:setup`. The script is
idempotent (skips existing records) so re-running it is safe.

---

## 2026-03 · `novels.directory_name` is a separate column, not derived from `title` (Milestone 10)

`Novel#title` is UI display text. The filesystem directory name (e.g. `idols-rewind`)
is a separate concern — it cannot be reliably derived from the title because the two
can diverge legitimately (a title of "Idols: Rewind" does not parameterize to
`idols-rewind`). A separate `directory_name` column is explicit, validatable at the
model layer, and visible in the database. `PipelineDispatcher` uses `novel.directory_name`
directly rather than performing any transformation. Uniqueness is scoped to
`organization_id` — two orgs may have a novel in a directory with the same name.

---

## 2026-03 · Single `PipelineJob` ActiveJob class, not one class per job type (Milestone 10)

Three job types (preread, bible_build, post_translation_review) are data on the
`TranslationJob` record, not separate ActiveJob subclasses. A single `PipelineJob`
receives a `translation_job_id`, looks up the record, and delegates dispatch to
`PipelineDispatcher`. This keeps the queue simple (one queue entry type), the status
lifecycle in one place, and the dispatch logic easy to extend — adding a new job type
means updating `PipelineDispatcher#call`, not adding a new ActiveJob class and queue
configuration.

---

## 2026-03 · Non-interactive Python wrappers `run_preread.py` and `run_review.py` (Milestone 10)

`preread.py` and `review.py` are interactive CLI tools that call `input()` to gather
parameters before running. A Solid Queue background job has no terminal — shelling out
to them directly would hang indefinitely. Two thin wrapper scripts (`run_preread.py`,
`run_review.py`) accept CLI arguments and call the same underlying runner functions
(`src.preread.runner.run_preread`, `src.bible_review.runner.run_review`) that the
interactive scripts call. The existing interactive scripts are untouched and continue
to work from the terminal. The wrappers are not modifications to the pipeline — they
are a second entry point to the same logic, following the pattern the pipeline already
uses (runner functions are designed for programmatic injection via `api_call_fn`).
