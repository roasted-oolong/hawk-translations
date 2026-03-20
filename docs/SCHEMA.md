# Hawk Translations — Schema

Canonical data model. Updated as migrations are written and run.
Column types reflect PostgreSQL / ActiveRecord conventions.

Status: **M1–M9 complete, M10 in progress** — migrations run through M9; M10 migrations written, pending `db:migrate`.

---

## Milestone 5 — Core Multi-Tenant Schema ✅

> Migrations run. Models, validations, and associations complete. All specs passing.

### users
| Column | Type | Notes |
|--------|------|-------|
| id | bigint PK | |
| email | string | unique, not null |
| name | string | not null |
| provider | string | e.g. "google_oauth2" |
| uid | string | provider-scoped unique identifier |
| platform_admin | boolean | default false — Platform Admin flag |
| created_at | datetime | |
| updated_at | datetime | |

Index: `(provider, uid)` unique

### organizations
| Column | Type | Notes |
|--------|------|-------|
| id | bigint PK | |
| name | string | not null |
| created_at | datetime | |
| updated_at | datetime | |

Through-associations (no migration required):
- `has_many :memberships, through: :teams`
- `has_many :members, through: :memberships, source: :user` — use `.distinct` when a user may belong to multiple teams in the same org

### teams
| Column | Type | Notes |
|--------|------|-------|
| id | bigint PK | |
| organization_id | bigint FK | not null |
| name | string | not null |
| created_at | datetime | |
| updated_at | datetime | |

### memberships
Join table: users ↔ teams. Carries role within that team.

| Column | Type | Notes |
|--------|------|-------|
| id | bigint PK | |
| user_id | bigint FK | not null |
| team_id | bigint FK | not null |
| role | string | "team_admin" \| "team_member" |
| created_at | datetime | |
| updated_at | datetime | |

Index: `(user_id, team_id)` unique

### series
| Column | Type | Notes |
|--------|------|-------|
| id | bigint PK | |
| organization_id | bigint FK | not null |
| name | string | not null |
| created_at | datetime | |
| updated_at | datetime | |

### novels
| Column | Type | Notes |
|--------|------|-------|
| id | bigint PK | |
| organization_id | bigint FK | not null |
| series_id | bigint FK | nullable |
| poc_user_id | bigint FK | nullable — points to users |
| title | string | not null — UI display text |
| directory_name | string | not null — exact filesystem directory name (e.g. "idols-rewind"), used by PipelineDispatcher |
| korean_title | string | |
| genre | string | |
| summary | text | org-visible |
| tone | text | |
| notes | text | |
| visibility | string | "discoverable" \| "hidden", default "discoverable" |
| created_at | datetime | |
| updated_at | datetime | |

Index: `(organization_id, directory_name)` unique

> `poc_user_id` is nullable with `optional: true`. Discovery view shows "POC not assigned" as placeholder when nil.
> `directory_name` is distinct from `title` — see DECISIONS.md for rationale.

---

## Milestone 6 — Novel Team Assignments ✅

### novel_team_assignments
Join table: novels ↔ teams. Carries permission level.

| Column | Type | Notes |
|--------|------|-------|
| id | bigint PK | |
| novel_id | bigint FK | not null |
| team_id | bigint FK | not null |
| permission_level | string | "viewer" \| "editor" \| "translator" \| "admin" |
| created_at | datetime | |
| updated_at | datetime | |

Index: `(novel_id, team_id)` unique

---

## Milestone 7 — Chapters ✅

### chapters
| Column | Type | Notes |
|--------|------|-------|
| id | bigint PK | |
| novel_id | bigint FK | not null |
| number | integer | not null — chapter number |
| title | string | optional subtitle |
| status | string | "untranslated" \| "translated" \| "reviewed" |
| created_at | datetime | |
| updated_at | datetime | |

Index: `(novel_id, number)` unique

Korean source file and translated output file stored via Active Storage attachments
on the Chapter model — not as columns.

---

## Milestone 8 — Bible Entry Tables ✅

> Migrations run. Models, validations, associations, and scopes complete. All specs passing.

All five tables share common columns: `novel_id` (FK, not null), `first_appearance_chapter` (integer, nullable), `notes` (text, nullable), `last_updated_at` (datetime, set via `before_save` callback), `created_at`, `updated_at`.

`last_updated_at` is set automatically via a `before_save` callback on each model — not managed by Rails. Distinct from `updated_at` to allow future suppression for minor edits if needed.

### bible_characters
| Column | Type | Notes |
|--------|------|-------|
| id | bigint PK | |
| novel_id | bigint FK | not null |
| name | string | not null |
| korean_name | string | |
| aliases | text | |
| role | string | |
| significance | string | |
| physical_description | text | |
| speech_pattern | text | |
| honorifics_used_toward | text | |
| honorifics_they_use | text | |
| relationships | text | |
| first_appearance_chapter | integer | |
| notes | text | |
| last_updated_at | datetime | set via before_save |
| created_at | datetime | |
| updated_at | datetime | |

Scope: `by_name` — orders alphabetically by name.

### bible_locations
| Column | Type | Notes |
|--------|------|-------|
| id | bigint PK | |
| novel_id | bigint FK | not null |
| name | string | not null |
| korean_name | string | |
| location_type | string | |
| description | text | |
| significance | text | |
| first_appearance_chapter | integer | |
| notes | text | |
| last_updated_at | datetime | set via before_save |
| created_at | datetime | |
| updated_at | datetime | |

Scope: `by_name` — orders alphabetically by name.

### bible_terminology
| Column | Type | Notes |
|--------|------|-------|
| id | bigint PK | |
| novel_id | bigint FK | not null |
| term | string | not null |
| korean_term | string | |
| definition | text | |
| usage_notes | text | |
| first_appearance_chapter | integer | |
| notes | text | |
| last_updated_at | datetime | set via before_save |
| created_at | datetime | |
| updated_at | datetime | |

Scope: `by_term` — orders alphabetically by term.

### bible_cultural_phrases
| Column | Type | Notes |
|--------|------|-------|
| id | bigint PK | |
| novel_id | bigint FK | not null |
| phrase | string | not null |
| korean_phrase | string | |
| literal_translation | text | |
| intended_meaning | text | |
| context | text | |
| established_translation | string | |
| first_appearance_chapter | integer | |
| notes | text | |
| last_updated_at | datetime | set via before_save |
| created_at | datetime | |
| updated_at | datetime | |

Scope: `by_phrase` — orders alphabetically by phrase.

### bible_story_entries
| Column | Type | Notes |
|--------|------|-------|
| id | bigint PK | |
| novel_id | bigint FK | not null |
| category | string | "main_plot" \| "subplot" \| "watch_list" \| "theme" \| "world_building" — not null |
| title | string | not null |
| content | text | |
| first_appearance_chapter | integer | |
| notes | text | |
| last_updated_at | datetime | set via before_save |
| created_at | datetime | |
| updated_at | datetime | |

Scopes: `by_title` — orders alphabetically by title. `by_category(cat)` — filters to a single category. Index view groups entries by category using `BibleStoryEntry.categories.keys`.

---

## Milestone 10 — Jobs 🔲

> Migrations written, pending `rails db:migrate`.

### novels (addition)
`directory_name` column added via `20260319000001_add_directory_name_to_novels`.
See novels table above for full column list.

### translation_jobs
| Column | Type | Notes |
|--------|------|-------|
| id | bigint PK | |
| novel_id | bigint FK | not null |
| user_id | bigint FK | not null |
| job_type | string | "preread" \| "bible_build" \| "post_translation_review" |
| status | string | "queued" \| "running" \| "completed" \| "failed" |
| chapter_start | integer | nullable — nil for bible_build (no chapter range) |
| chapter_end | integer | nullable — nil for bible_build; equals chapter_start for single-chapter jobs |
| result_payload | text | stdout/stderr from pipeline, or stub message |
| solid_queue_job_id | string | nullable — reserved for future cancellation via Solid Queue internals |
| created_at | datetime | |
| updated_at | datetime | |

Indexes: `status`, `job_type`, `(novel_id, created_at)`
