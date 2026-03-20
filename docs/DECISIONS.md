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

---

## 2026-03 · Deploy to AMD E2 micro (x86_64) instead of Ampere A1 (ARM64) — Milestone 11

Oracle Cloud A1 capacity was unavailable at deployment time. The existing AMD E2 micro
(1 OCPU, ~1GB RAM, x86_64) is used for initial production deployment. Mitigations for
the memory constraint: 2GB swapfile, WEB_CONCURRENCY=1, RAILS_MAX_THREADS=5 (to match
Solid Queue's thread count across worker + dispatcher + scheduler), Solid Queue
in-process via SOLID_QUEUE_IN_PUMA=true.

ARM64 migration path when A1 capacity opens: change `builder.arch` in `config/deploy.yml`
from `amd64` to `arm64` and run `kamal deploy`. No other changes required.

---

## 2026-03 · Python pipeline runs inside the Rails Docker container — Milestone 11

The Python pipeline ships inside the same Docker image as the Rails app. The Dockerfile
installs Python 3, creates a venv at `/opt/hawk-venv`, and installs `requirements.txt`
into it. `PATH` is set so subprocesses spawned by `Open3.capture3` find the venv python
by default. Alternative (run Python on the VM host) was rejected — adds infrastructure
complexity and breaks the single-deploy model. The pipeline runs as short-lived
subprocesses, not a long-running service.

---

## 2026-03 · PostgreSQL runs on the VM host, not in a Docker container — Milestone 11

Data persistence across `kamal deploy` without managing a Docker volume for a DB
container. The hawk PostgreSQL user and three databases (primary, cache, queue) are
created once on the host and remain through all future deploys. The Rails container
connects via DATABASE_URL pointing to `172.18.0.1` (the kamal Docker network gateway).

---

## 2026-03 · kamal-proxy handles SSL directly; Nginx not used in production — Milestone 11

Initial plan was Nginx:443 (Origin Cert) → kamal-proxy:80 → Rails. This failed because
Kamal 2.10 always binds both port 80 AND port 443 on the host — not configurable.
Nginx could not start with kamal-proxy owning both ports. Final architecture removes
Nginx from the stack entirely: Cloudflare → kamal-proxy:443 → Rails container.
kamal-proxy handles SSL with its own certificate. Cloudflare SSL/TLS mode set to
"Full (strict)". The Cloudflare Origin Certificate files are preserved on the VM at
`/etc/nginx/ssl/` for future use if the architecture changes.

---

## 2026-03 · Cloudflare Origin Certificate, not Let's Encrypt — Milestone 11

Kamal's built-in SSL (Let's Encrypt) requires ACME challenges on port 80. With Cloudflare
proxying all traffic, the challenge never reaches the VM. Cloudflare Origin Certificates
secure the Cloudflare→origin leg without ACME. `force_ssl` is left off in `production.rb`
to avoid a redirect loop; `assume_ssl` is enabled so Rails treats all requests as HTTPS.

---

## 2026-03 · Secrets stored in ~/.config/hawk/ on local machine — Milestone 11

`.kamal/secrets` reads secrets from `~/.config/hawk/` single-line files at deploy time.
Keeps secrets off any git-tracked location and avoids shell environment variable pollution.
The directory is created once manually and never committed. Files: `github_token`,
`db_password`, `anthropic_api_key`.

---

## 2026-03 · HAWK_PROJECT_ROOT set to /rails in the container — Milestone 11

In development, `HAWK_PROJECT_ROOT=/home/jenna/hawk-translations` (`.env`). In the Docker
container, `WORKDIR` is `/rails`, so `HAWK_PROJECT_ROOT=/rails`. Set as a clear env var in
`config/deploy.yml`. `config.py` reads it via `os.environ["HAWK_PROJECT_ROOT"]` (fixed at
Milestone 3) — no code changes required.

---

## 2026-03 · iptables source-based rule for Docker→PostgreSQL — Milestone 11

Oracle Cloud VMs ship with a default iptables REJECT rule that blocks all non-whitelisted
inbound traffic, including container→host connections. ufw is inactive; the block is at the
raw iptables level. Interface-specific rules (per bridge name) break when Docker recreates
the kamal network (e.g. after `docker network rm kamal`) because the bridge interface ID
changes. A source-based rule `iptables -I INPUT -s 172.16.0.0/12 -j ACCEPT` covers the
entire Docker bridge address range and survives network recreation. Saved via
`netfilter-persistent` so it persists across reboots.

---

## 2026-03 · pgvector compiled from source on VM — Milestone 11

Ubuntu 22.04's apt repositories do not include `postgresql-14-pgvector`. pgvector v0.6.0
was compiled from source (`git clone`, `make`, `make install`) and the extension
pre-created in all three production databases as the `postgres` superuser. Pre-creating
the extension means the `hawk` app user (non-superuser) never needs `CREATE EXTENSION`
privileges — Rails' `db:prepare` finds the extension already present and skips it.

---

## 2026-03 · RAILS_MAX_THREADS=5 to match Solid Queue total thread count — Milestone 11

Solid Queue reports "5 threads" but `queue.yml` correctly sets `threads: 3` for the
worker. The discrepancy is Solid Queue counting all internal threads: 3 worker threads
+ 1 dispatcher thread + 1 scheduler thread = 5. The database connection pool must be
≥ 5 to satisfy all threads. `RAILS_MAX_THREADS=5` and `pool=10` in DATABASE_URL
(headroom above the minimum) resolves the mismatch. `queue.yml` config is correct and
does not need changes.

---

## 2026-03 · Oracle Cloud security list must explicitly open ports 80 and 443 — Milestone 11

Oracle Cloud's network security list (external hypervisor firewall) blocks all ports
by default except SSH (22). This is separate from and in addition to the VM's iptables
rules. Ports 80 and 443 must be added as explicit TCP ingress rules from `0.0.0.0/0`
in the subnet's security list. Without these rules, Cloudflare's connections to the VM
are dropped before reaching the OS or any application.
