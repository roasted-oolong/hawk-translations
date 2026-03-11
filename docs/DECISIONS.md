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

## 2026-03 · Chapter file naming: three patterns exist, migration script deferred to Milestone 9

Observed patterns in idols-rewind/chapters:
1. `Chapter_1 - The Super Manager's Regression.txt` — translated, has subtitle
2. `Chapter_68 - Script Reading(1).txt` — translated, has subtitle with number
3. `Chapter_10.txt` — translated, no subtitle
4. `ch1_korean` — Korean source, no extension

Rename script will normalize all translated output to `Chapter X.txt` and
Korean source to `Chapter X (Korean).txt`. Script written at Milestone 9,
not before — no need to touch existing files until the chapter model exists.
