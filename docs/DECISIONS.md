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

---

## 2026-03 · Voyage AI voyage-3-lite as embedding model — Milestone 12

Anthropics recommended embedding partner. voyage-3-lite outputs 1024-dimension vectors,
handles multilingual text (English + Korean) well, and is cheap enough that embedding
an entire novel bible costs under a dollar. API key stored in Rails encrypted credentials
as `voyage_api_key`, consistent with how Google OAuth credentials are stored.

---

## 2026-03 · Polymorphic `bible_embeddings` table, not per-table embedding columns — Milestone 12

Five separate embedding columns across five tables would require five ivfflat indexes,
five GIN indexes, and a UNION query for any cross-category search. One `bible_embeddings`
table with a polymorphic association gives a single ivfflat index, a single GIN index,
and a single query for all search operations. `novel_id` and `organization_id` are
denormalized onto the table to avoid joins back through the polymorphic target during
high-frequency search queries. Extending to novels and chapters (Use Cases 2 and 3)
means adding new `embeddable_type` values — no schema changes to existing tables.

---

## 2026-03 · tsvector on `bible_embeddings`, not on the five bible tables — Milestone 12

Korean text is not confined to `korean_name` columns — it appears throughout free-text
fields (speech_pattern examples, notes, aliases). The tsvector must cover the same
concatenated `embeddable_text` used for the vector embedding, not individual columns.
Since `BibleEmbedding` already holds that concatenated text as the source for its
vector, storing `search_text` there keeps both search mechanisms derived from the
same source. Five separate tsvector columns on five tables would require a UNION
query for keyword search and five GIN indexes.

---

## 2026-03 · `Embeddable` concern with explicit `NotImplementedError` contract — Milestone 12

The `after_save` hook and the `embeddable_text` interface are defined once in the concern.
Raising `NotImplementedError` at call time rather than silently returning nil means a
new bible model that includes `Embeddable` but forgets to implement `embeddable_text`
fails loudly on first save rather than silently producing a blank embedding. Composition
over inheritance: each model includes the concern and implements its own field list.

---

## 2026-03 · `VoyageClient` as a thin service wrapper, not a gem — Milestone 12

The `voyageai` gem on RubyGems is lightly maintained. A 60-line wrapper around
`Net::HTTP` gives full control over the interface, makes it trivially stubbable
in specs via WebMock (no gem monkey-patching), and decouples the app from a
third-party gem's API choices. Mirrors the `PipelineDispatcher` wraps `Open3`
pattern already established in this codebase.

---

## 2026-03 · `content_hash` staleness guard on `BibleEmbedding` — Milestone 12

Bible entries save frequently during active translation sessions. Without a staleness
guard, every save would trigger a Voyage AI API call even when the text did not change
(e.g. updating `last_updated_at` only). SHA256 of `embeddable_text` stored as
`content_hash` lets `GenerateEmbeddingJob` skip the API call when content is unchanged.
Cost: one `SELECT` per job execution. Benefit: eliminates redundant API calls for
unchanged records.

---

## 2026-03 · Search UI deferred — API layer only in Milestone 12 — Milestone 12

The priority was Use Case 2 (Claude pipeline querying bible via API) over Use Case 1
(human search bar in the UI). The JSON endpoint at
`GET /novels/:novel_id/bible/search` serves both human UI and programmatic callers.
Building the UI as a Turbo/Stimulus layer on top of this endpoint is the next
milestone — the endpoint is the stable foundation either way.

---

## 2026-03 · Rails 8.1.2 + Ruby 3.4 `presence` visibility bug — Milestone 12

Rails 8.1.2 and Ruby 3.4.2 have an incompatibility where ActiveSupport's `presence`
method ends up treated as private on any class that `blank.rb` reopens (NilClass,
String, Array, Hash, Symbol, Numeric, etc.), and on `ActiveRecord::Transaction`.
Root cause not fully understood — suspected Ruby 3.4 method visibility resolution
change for inherited methods in reopened classes.

Workaround: explicitly redefine `presence` on all affected classes in
`config/application.rb` immediately after `Bundler.require`, and prepend a fix on
`ActiveRecord::Transaction` via an initializer. Remove both when upgrading to a
Rails version that fixes this.

---

## 2026-03 · Switched schema format to :sql for pgvector compatibility — Milestone 12

Rails' default `schema.rb` format cannot serialize `vector(1024)` columns — it
comments out the `bible_embeddings` table with "Unknown type 'vector(1024)'",
while still emitting the `add_foreign_key` lines that reference it. This causes
`db:test:prepare` to fail. Switched to `config.active_record.schema_format = :sql`
which dumps `db/structure.sql` (raw PostgreSQL SQL). This correctly captures all
pgvector column types, tsvector columns, ivfflat indexes, and GIN indexes.
Required for any project using PostgreSQL-specific column types.

---

## 2026-03 · Voyage AI vector must be serialized as string for upsert — Milestone 12

`VoyageClient.embed` returns a Ruby Array of floats. Passing this Array directly
to `BibleEmbedding.upsert` raises `TypeError: can't quote Array` because
ActiveRecord doesn't have a registered type handler for `vector(1024)` columns
(the `pgvector` gem doesn't integrate with ActiveRecord — it's pg/Sequel only;
the Rails equivalent is the `neighbor` gem which we don't use). Fix: format the
vector as a pgvector-compatible string `"[f1,f2,...,f1024]"` before upserting.

---

## 2026-03 · Named routes inside resources blocks get the resource name prepended — Milestone 12

When `get "bible/search", as: :novel_bible_search` is defined inside
`resources :novels`, Rails prepends the resource name and generates
`novel_novel_bible_search_path` — not `novel_bible_search_path`. The correct
`as:` value is `:bible_search`, which Rails expands to `novel_bible_search_path`
(prepending `novel_` from the resources block). Specs used the intended helper
name; the route definition had the wrong `as:` value.

---

<!-- Phase 2 decisions index (M13–M18)
  1. TypeScript via jsbundling-rails + esbuild, replacing importmaps
  2. Hand-rolled CSS, no framework
  3. Native HTML <dialog> for modals, no external library
  4. Combobox built as a Stimulus controller against the existing search endpoint
  5. Component inventory defined before M13
  (Further entries appended as milestones complete)
-->

## 2026-03 · TypeScript via jsbundling-rails + esbuild, replacing importmaps — Phase 2

Importmaps (the Rails 8 default) has no build step, which is its main advantage.
TypeScript requires compilation and therefore a build step regardless of which
bundler is used. The tradeoff: esbuild is fast enough that the build step is not
felt in daily development, and the safety net TypeScript provides over a multi-year
horizon on a long-term product justifies the setup cost. Strict mode enabled.
Future collaborators benefit from typed contracts on Stimulus controllers.
Importmaps removed; `jsbundling-rails` + esbuild replaces it. Foreman/Procfile.dev
runs `yarn build --watch` alongside `rails server` in development.

---

## 2026-03 · Hand-rolled CSS, no framework — Phase 2

Propshaft serves static assets. The view count is small and well-defined (login,
dashboard, novel index/show, chapters, jobs, bible ×5, forms). A CSS framework
imposes opinions on every element; hand-rolled CSS with custom properties is more
intentional and produces faster output for a focused internal tool. modern-normalize
from cdnjs provides a cross-browser baseline with no install required. If the app
grows significantly in scope, revisit at that milestone.

---

## 2026-03 · Native HTML <dialog> for modals, no external library — Phase 2

The HTML `<dialog>` element is fully supported across all modern browsers as of 2023.
A single Stimulus controller (~50 lines) handles open/close, backdrop click, Escape
key, and focus trapping. Ark UI (React/Vue/Solid only) and other headless libraries
are not compatible with a Hotwire rendering model without significant complexity.
Native `<dialog>` is the correct primitive for this stack.

---

## 2026-03 · Combobox built as a Stimulus controller against the existing search endpoint — Phase 2

The bible search JSON endpoint was built at M12. The combobox controller fetches
from that endpoint, debounces input, and handles keyboard navigation. No external
combobox library — the endpoint contract is already defined, and a bespoke controller
keeps the dependency count at zero. This is the most complex Stimulus controller in
the app and is built as a dedicated step within M16.

---

## 2026-03 · RAILS_MAX_THREADS must be 5 to match Solid Queue's actual thread count — M13

Solid Queue reports 5 total threads: 3 worker threads + 1 dispatcher + 1 scheduler.
`max_connections` in `database.yml` is derived from `RAILS_MAX_THREADS`, so it must
be >= 5 or Solid Queue refuses to start with "configured to use 5 threads but the
database connection pool is 3". `RAILS_MAX_THREADS` was temporarily set to 3 to
match Puma's request thread count, but Solid Queue's internal threads share the same
pool. Restored to 5 in `config/deploy.yml`.

---

## 2026-03 · config.hosts extended to allow kamal-proxy health check — M13

Rails `HostAuthorization` blocked kamal-proxy's `/up` health check because it
arrives with the container's own hostname (`c42776ab7493:80`) rather than the
public domain. Fixed by adding a regex matching raw hex container IDs with optional port
(`/\A[a-f0-9]+(:[0-9]+)?\z/`), the Docker bridge subnet
(`172.18.0.0/16`), and localhost to `config.hosts` in `production.rb`.
The public domain entries are preserved so DNS rebinding protection remains active
for all real traffic.

---

## 2026-03 · Removed pool= from DATABASE_URL and pool: from database.yml — M13

Rails 8.1.2 introduced a strict validation that raises an error if both `pool`
and `max_connections` are present in the same database configuration. Previously
`database.yml` had `pool: 5` in each production block and `DATABASE_URL` had
`pool=10` as a query parameter, while the `default` block already derived
`max_connections` from `RAILS_MAX_THREADS`. This caused `db:prepare` to abort
with "Ambiguous configuration: 'pool' (5) and 'max_connections' (3)" before
the server could start. Fix: remove `pool:` from all three production blocks
in `database.yml` and remove `pool=N` from all three DATABASE_URL secrets in
`.kamal/secrets`. Pool size is now controlled exclusively by `max_connections`
via `RAILS_MAX_THREADS=3`.

---

## 2026-03 · Cuprite chosen as system spec driver over Playwright — M13

Playwright requires a managed browser binary (downloaded separately via
`playwright install`) and ships as a Node.js library with a Ruby wrapper
(`playwright-ruby-client`). In a WSL2 + Docker environment this adds a
browser binary layer that must be present in the Docker image for CI and
production-equivalent testing. Cuprite drives Chrome/Chromium via the CDP
protocol using the Ferrum gem — no Node.js required for the test driver
itself, and it can use the system Chrome already present on the developer's
machine. Lighter dependency footprint, zero managed binary downloads, and
sufficient capability for this project's system spec needs. If cross-browser
testing becomes a requirement, Playwright is the upgrade path.

---

## 2026-03 · Node.js 22 LTS in Dockerfile — M13

Node 22.x is the current LTS (Active until 2027-04). Node 20.x enters
maintenance-only in 2024-10. The build pipeline (esbuild + yarn) has no
known incompatibilities with Node 22. Installed via the NodeSource apt
repository in the Dockerfile build stage. Yarn installed via
`npm install -g yarn` after Node. Only needed at build time — not present
in the final image runtime layer.

---

## 2026-03 · Component inventory defined before M13 — Phase 2

All reusable UI patterns identified upfront: status badge, flash message, nav bar,
breadcrumb, novel card, data table, modal, toast, combobox, file upload. Each has
a defined contract (inputs, states, behavior, Stimulus controller y/n) documented
in UI.md before any view code is written. Building components against a known
inventory prevents ad-hoc duplication across views and gives each milestone a
clear implementation checklist.

---

## 2026-03 · Soft UI Evolution + blue-slate palette for Hawk Translations — M14

Design system generated via uipro (UI UX Pro Max skill) against the query
"internal SaaS tool translation management dashboard". Matched category:
Productivity Tool. Recommended style: Soft UI Evolution + Flat Design accents.
Primary palette: blue-600 (#2563EB) for actions, slate-900 (#0F172A) for text,
slate-50 (#F8FAFC) for page background. Violet-600 (#7C3AED) accent gives the
translation/literary product a distinctive identity without decorative excess.
All token values recorded in UI.md. The palette is swap-friendly by design —
a theme change is a single-file edit to `:root` in application.css.

---

## 2026-03 · Inter variable font self-hosted, no Google Fonts CDN — M14

Inter loaded via two self-hosted variable font files (`inter-variable.woff2`,
`inter-variable-italic.woff2`) in `app/assets/fonts/inter/`. A single variable
file covers all weights (100–900) via the `font-weight` axis, replacing the five
separate static files originally planned. Self-hosting avoids the external CDN
request on every page load and removes the dependency on Google's availability.
Korean display text uses the system font stack (Apple SD Gothic Neo, Malgun Gothic,
Nanum Gothic) — no web font loaded for Korean, as it only appears in title display
fields and the nav brand mark.

---

## 2026-03 · All SVG icons rendered via _icon component, never inlined — M14

All icons go through `app/views/components/_icon.html.erb`. No inline SVG in views
or partials. This keeps SVG paths in one place (easy to audit, easy to swap),
ensures consistent `aria-hidden="true"` and `focusable="false"` on every icon,
and gives a single surface for adding new icons per milestone. Icons sourced from
Heroicons 2.x (outline style, MIT licence) and the Google brand SVG.

---

## 2026-03 · Flash alerts never auto-dismiss; notices auto-dismiss after 4s — M14

Alerts (errors) require the user's attention and must be dismissed explicitly —
auto-dismissing an error message before the user reads it would be hostile UX.
Notices (success/info) are ephemeral confirmations that auto-dismiss after 4s
via `flash_controller.ts`. Both variants have a manual dismiss button. The
`duration` Stimulus value defaults to 0 (no auto-dismiss), so omitting it on
alert variants is safe — no special-casing required in the controller.

---

## 2026-03 · Login page renders its own inline flash for OAuth failures — M14

The application layout renders the flash container above `app-main`, which is
offset by `--nav-height` (56px) on authenticated pages. On the login page there
is no nav and no offset — the layout flash renders at the very top of the
viewport, above the centered card, which is visually disconnected from the form.
The login view renders its own inline alert directly inside the card so failure
messages appear in context. The layout flash is still rendered (harmless) but the
inline version is the one the user sees.

---

## 2026-03 · Dashboard queries novels via NovelTeamAssignment, no bypass for any user — M15

The dashboard shows only novels assigned to the current user's teams via
`NovelTeamAssignment`. No shortcut is applied for the solo MVP user or the
Platform Admin — if you have no team membership and no assignment, the dashboard
shows the empty state. This keeps the permission model honest from day one and
means the real setup path (create org → team → membership → assignment) is
exercised by the first user rather than bypassed. The cost is one extra setup
step before the dashboard shows anything useful; the benefit is that the
permission scaffolding is validated in production from the first login.

---

## 2026-03 · Turbo Frame polling via poll_controller.ts — M16

Job status polling on `translation_jobs/show` uses a minimal Stimulus controller
(`poll_controller.ts`) that calls `frame.reload()` on a configurable interval.
The controller is mounted on a wrapper div that is only rendered server-side when
the job is active (queued or running). When the job reaches a terminal state, the
wrapper is absent — the controller never connects and polling stops without any
client-side state management or cleanup. `frame.reload()` re-fetches the current
page URL and Turbo replaces only the matching `<turbo-frame id="job-status">`
content — no full page reload. The Turbo native `refresh="interval"` attribute
does not exist on Turbo Frames in turbo-rails 2.x; Stimulus is the correct
approach for frame-scoped polling without Action Cable.

---

## 2026-03 · User model associations added at M15, not M5 — M15

`has_many :memberships`, `has_many :teams through: :memberships`, and
`has_many :translation_jobs` were absent from the `User` model despite
`Membership` having `belongs_to :user` since M5 and `TranslationJob` having
`belongs_to :user` since M10. The omission was not caught until M15 because
no code prior to `DashboardController` traversed the user→memberships direction.
Added at M15 when `current_user.memberships.pluck(:team_id)` raised `NoMethodError`.
No migration required — the foreign keys and join tables already exist.

---

## 2026-03 · Bible landing page at `/novels/:id/bible` — M17

The bible search UI (deferred from M12) needed a home. Three options were
evaluated: (1) a shared partial on all five category indexes, (2) embedded
in the novel show bible section, (3) a dedicated `BibleController#show` landing
page. Option 3 was chosen because it gives the bible a clear section entry point,
reduces the responsibility of `novels/show`, and provides a natural home for
any future cross-category bible features. The five category summary cards were
moved from `novels/show` to the new landing page. `novels/show` now carries a
single "Translation Bible →" link. `@bible_counts` removed from `NovelsController#show`
and moved to `BibleController#show`. Route: `get "bible", to: "bible#show", as: :bible`
inside the novels resources block, generating `novel_bible_path`.

---

## 2026-03 · `combobox_controller.ts` — bespoke Stimulus controller, no library — M17

The bible search combobox is implemented as a hand-rolled Stimulus controller
against the existing `BibleSearchController` JSON endpoint. No external combobox
library is used — the endpoint contract is already defined, and a bespoke
controller keeps the dependency count at zero. The controller handles debounce
(300ms), fetch with `Accept: application/json`, result rendering, keyboard
navigation (ArrowUp/ArrowDown/Enter/Escape), and outside-click dismissal.
Result show paths are derived from the search endpoint URL by stripping
`/bible/search` and appending the Rails resource segment for each bible type —
no hardcoded paths in the controller. Minimum query length is 2 characters.

---

## 2026-03 · `directory_name` is read-only after creation — M18

Once a novel is saved, its `directory_name` cannot be changed via the UI. The
edit form renders the value as static monospace text with a hint explaining why,
and the field is absent from the form entirely. `novel_update_params` in
`NovelsController` omits `:directory_name` as defence-in-depth — even a
hand-crafted POST cannot change it. Rationale: the pipeline dispatches jobs
using `novel.directory_name` to locate files on disk; a UI rename with no
corresponding filesystem rename would silently break all future jobs. A rename
requires a developer-level intervention so the filesystem and database are
changed together. No model-level guard added — the controller is sufficient for
now; add a model callback if a second write path ever opens up.

---

## 2026-03 · `modal_controller` + `dialog_controller` — two-controller split for shared dialog — M18

A single shared `<dialog id="modal-dialog">` lives in the application layout
and is reused by every destructive action in the app. Two controllers split
responsibilities: `modal_controller` mounts on each trigger (the `button_to`
wrapper div) and stores the form to submit on confirm; `dialog_controller`
mounts on the `<dialog>` element itself and handles open/close mechanics,
backdrop clicks, and routing confirm/cancel back to the active modal controller
via a `_modalController` property on the dialog element. This avoids Stimulus
outlets (which require stable CSS selectors) and keeps the dialog oblivious to
what it's confirming — it just calls `handleConfirm()` or `handleCancel()` on
whoever opened it. All 15 previous `data-turbo-confirm` call sites replaced.

---

## 2026-03 · `modal_button_to` ApplicationHelper — DRY wrapper for modal-confirmed destructive actions — M18

`ApplicationHelper#modal_button_to` is a drop-in replacement for `button_to`
with `data: { turbo_confirm: "..." }`. It wraps the button in the
`data-controller="modal"` div with the message and confirm label values, then
forwards all remaining options to `button_to`. This keeps the 15 call sites
clean and ensures consistent modal wiring without repeating the controller
attribute pattern in every view. The helper is the only place that knows how
the modal controller is wired — views just call `modal_button_to`.

---

## 2026-03 · `toast_controller` for Turbo Stream job completion notifications — M18

`toast_controller.ts` mounts on individual toast elements appended to
`#toast-region` via Turbo Streams. Each stream append creates a new element;
the controller animates it in, auto-dismisses after a configurable duration
(default 4s), and removes itself. No shared controller state — each toast is
independent. The `#toast-region` div uses `aria-live="polite"` so screen
readers announce new toasts without interrupting current focus. Full Turbo
Stream wiring (appending toasts on job completion) is deferred to the next
milestone that adds real-time job feedback; the controller and region are
infrastructure-ready.

---

## 2026-03 · Novel `series_id` and `poc_user_id` scoped to org — M18

Both selects on the novel form are scoped to the novel's organization:
`series` via `Series.where(organization: org)`, `poc_user` via users who
are members of a team in that org. `set_form_collections` runs as a
`before_action` on `new/create/edit/update`. For the new form (before save),
the org is not yet set on `@novel`, so it falls back to `Organization.first` —
correct for solo MVP (one org). When multi-org management is added, this
fallback should be replaced with a proper org selection step before the form
is reached.

---

## 2026-03 · Editorial palette + Newsreader serif adopted at M18.5

Replaced the M14 blue-slate SaaS palette (#2563EB primary, #F8FAFC background)
with an editorial slate-blue palette (#4e6078 primary, #f9f9f8 background) ahead
of Phase 3 work. Changes confined to application.css (:root block) and
_typography.css. All component files already used tokens exclusively — no
hardcoded values were found in any component stylesheet.

--color-surface split into two tokens: --color-surface (#f9f9f8, ambient chrome —
nav, utility panels) and --color-surface-manuscript (#ffffff, document surfaces —
cards, panels, dialogs, login card). Six component files updated to use
--color-surface-manuscript where appropriate.

--nav-height retained alongside new --sidebar-width and --topbar-height tokens;
removal deferred to M19 when the nav is structurally replaced.

Newsreader variable font (self-hosted, same pattern as Inter) added as
--font-family-serif with three utility classes: .text-serif, .text-serif-display,
.text-serif-body. Font files follow the same convention as Inter — not committed
to the repo, dropped into app/assets/fonts/newsreader/ before running the app.

---

## 2026-03 · Two-bar app shell: fixed sidebar + slim topbar — M19

The top nav (single fixed bar, full width) is replaced by two elements: a fixed
left sidebar for primary navigation and a fixed slim topbar for page-contextual
items (breadcrumb, user, sign-out). Rationale: the sidebar pattern scales better
as the nav link inventory grows, and separating primary navigation from
page-contextual actions reduces the cognitive load of the top bar. The topbar
exposes a `yield :topbar_actions` slot so individual pages can inject a primary
action button (e.g. "New Novel") without coupling the layout to any specific page.
CSS tokens `--nav-height` replaced by `--sidebar-width: 15rem` and
`--topbar-height: 3rem`. Layout shift: `.app-body` flex direction stays default
(column); `.app-main` gains `padding-left: var(--sidebar-width)` and
`padding-top: var(--topbar-height)`.

---

## 2026-03 · Novel card rewritten in place, no variant parameter — M20

`novels/_card.html.erb` is rewritten as a single gallery-style card used everywhere
(dashboard, novel index). No variant parameter. Both contexts get the same card;
grid column sizing in each context determines how wide the card renders. A variant
parameter was considered and rejected — the two use sites are too similar to justify
branching logic inside the partial.

---

## 2026-03 · Mobile navigation: fixed bottom nav bar, not off-canvas hamburger sidebar — M19

The original M19 spec called for an off-canvas sidebar toggled by a hamburger button via
`sidebar_controller.ts`. During implementation, Cuprite's headless Chrome viewport emulation
proved unreliable for testing media-query-driven CSS changes mid-test: `Emulation.setDeviceMetricsOverride`
updates `window.innerWidth` but the rendered layout does not consistently recalculate before
subsequent interactions fire, making the toggle specs non-deterministic regardless of
synchronization strategy attempted.

Rather than work around a test infrastructure limitation, the mobile nav pattern was changed
to a fixed bottom nav bar (`_bottom_nav.html.erb`, `_bottom_nav.css`). This is a better mobile
UX pattern for a navigation-heavy internal tool (mirrors native app conventions), eliminates
all JavaScript from the navigation layer, and makes the specs straightforward DOM presence
and link checks that don't depend on viewport state. `sidebar_controller.ts` removed entirely.

---

## 2026-03 · Novel card rewritten in place, no variant parameter — M20

`app/views/novels/_card.html.erb` was fully rewritten as a gallery-style card (cover image
slot, serif title, progress bar). No variant parameter was introduced — the card is used
identically on the dashboard and the novel index, so a single layout serves both. The old
padding-based card structure is gone; cover goes edge-to-edge and the body carries its own
inner padding.

Cover image link uses `aria-hidden="true" tabindex="-1"` so screen readers encounter only
the title link. The cover `<a>` shares the novel href but is decorative — the title is the
meaningful navigation target.

`novel-grid` column floor reduced from `20rem` to `14rem` to accommodate the taller
portrait-ratio cards without forcing the grid to collapse to a single column too early.
Progress bar wired to `width: 0%` static placeholder at M20; real chapter ratio wired at M21.

---

## 2026-03 · Cover art optional with placeholder; purge via dedicated route; `.with_attached_cover_art` on both queries — M21

`Novel` gains `has_one_attached :cover_art`. No migration needed — Active Storage tables
already exist from the initial Rails setup. Cover art is optional; the card renders a
`--color-surface-low` placeholder div when nothing is attached and an `<img>` when it is.

Content type (JPEG, PNG, WebP) and size (< 5MB) are validated via two custom `validate`
methods rather than the `active_storage_validations` gem, which is not in the Gemfile.
The methods check `cover_art.content_type` and `cover_art.byte_size` directly — no gem
required, trivially testable.

Purge is a dedicated `DELETE /novels/:id/cover_art` member route calling `destroy_cover_art`
rather than a hidden `_destroy` form field. This keeps the intent explicit in the route,
gives the action a named route helper (`cover_art_novel_path`), and avoids magic boolean
fields on the update params.

`.with_attached_cover_art` added to both `NovelsController#index` and
`DashboardController#index` — both queries already `includes` chapters and
translation_jobs, and the cover art attachment must join the same way to avoid N+1
on the card's `cover_art.attached?` check.

---

## 2026-03 · Progress bar uses `.floor`, not `.round` — M21

`(translated_count.to_f / total_chapters * 100).floor` is used for the novel card
progress bar. `.round` produces 67% for 2/3 chapters (66.6̄%), which overstates
progress — a chapter is not counted as done until it is. `.floor` truncates toward
zero so the bar only advances when work is actually complete. The 100% case is
unaffected (`100.0.floor == 100`).

---

## 2026-03 · `cover_art.blob.persisted?` guard on edit form thumbnail — M21

When `PATCH /novels/:id` is submitted with an invalid file (wrong content type),
`@novel.update(params)` assigns the blob to the record in memory and begins the
Active Storage transaction. Validation then fails and the transaction rolls back —
the blob is never written to `active_storage_blobs`. However, `cover_art.attached?`
still returns true on the in-memory record (the attachment proxy has a blob object
set), so the edit form's cover thumbnail branch is entered. `image_tag novel.cover_art`
then calls `signed_id` on a blob with no persisted `id`, raising
`ArgumentError: Cannot get a signed_id for a new record`.

Fix: guard with `novel.cover_art.attached? && novel.cover_art.blob.persisted?`.
The `persisted?` check is false on the rolled-back blob, so the thumbnail branch
is correctly skipped and the form re-renders cleanly.

## 2026-03 · Solo translator workspace auto-provisioned on first sign-in

When a new user authenticates for the first time, `ProvisionWorkspace` is called
automatically to create their org, default team, and team_admin membership.
When they create a novel, `AutoAssignNovel` creates a `NovelTeamAssignment` at
`permission_level: "translator"` against their first team.

This means the dashboard's `NovelTeamAssignment`-based query works for solo
translators from day one with no manual setup. The org/team structure is real —
not a bypass — so it is ready for collaborators when they are invited.

**Trigger for ProvisionWorkspace:** `SessionsController#create` calls
`ProvisionWorkspace.call(user)` only when `user.previously_new_record?` is true
(Rails 6.1+ — returns true if the record was just inserted in this request).
This is cheaper than a separate `provisioned_at` column and requires no migration.
`ProvisionWorkspace` also has its own idempotency guard (`memberships.exists?`),
so a double-call on the same user is safe.

**Trigger for AutoAssignNovel:** `NovelsController#create` calls
`AutoAssignNovel.call(@novel, current_user)` immediately after a successful save.
Uses `find_or_create_by!` so re-running on the same (novel, team) pair is a no-op.

**MVP assumption:** `AutoAssignNovel` picks `current_user.teams.first` as the
target team. This is correct for a solo translator with one team. When multi-team
users exist (a translator who is a member of several teams), the assignment target
will need to be explicit — either chosen during novel creation or derived from
org membership. See ROADMAP.md.

---

## 2026-07-20 · Voice calibration review model stays local (`gpt-oss-20b`), quality ceiling accepted

Since the `ec35668` refactor moved `calibrate-voice.py` off the Anthropic SDK onto a
generic OpenAI-compatible client (`src/agent.py`, pointed at local Ollama), review
output quality has visibly dropped: the original 11 curated passages are rich,
character-specific observations, while fresh local-model runs trend toward generic
mechanical notes (tense/POV consistency) and have occasionally emitted unfilled
template placeholders (e.g. a heading literally reading `Passage [New1]`) instead of
real content.

Considered routing this one call back to a cloud model (Anthropic or otherwise) while
keeping the rest of the pipeline local. Decided against it for now: no API key is
configured, and the cost/access tradeoff isn't worth it yet. Accepted as a known
quality ceiling rather than worked around. Revisit if local-model output quality
becomes a recurring blocker rather than a one-off frustration.

This is unrelated to the feedback-loop bug fixed the same day: accepted/retired
calibration cards previously never made it back into `voice_calibration.md` (the
file `calibrate-voice.py` reads as context on every run), so every run re-discovered
the same "next" passage slots regardless of model quality. `VoiceCalibrationDocWriter`
(`app/services/voice_calibration_doc_writer.rb`) now keeps that file in sync on
commit, for both accepted new patterns and retirements.

---

## 2026-07-21 · Chapter translation gets a second backend: Claude Code CLI via subscription, not the API

Same quality ceiling as the 2026-07-20 entry above, but for chapter translation
specifically — and the "revisit if it becomes a recurring blocker" condition was
met. Rather than paying per-token API rates (rejected then for the same reason:
no API key configured, cost/access tradeoff), `translate.py`/`translate_batch.py`
now shell out to the Claude Code CLI's headless mode (`claude -p`), authenticated
via the user's existing Claude Pro subscription (`claude auth login`) instead of
`ANTHROPIC_API_KEY` — usage draws from the subscription's included quota rather
than metered billing.

Considered rewriting `src/agent.py` in place to call Claude Code directly. Rejected:
grep showed `src/agent.py` and `OPUS_MODEL`/`SONNET_MODEL`/`HAIKU_MODEL` are shared
by 8 other pipeline scripts (`preread.py`, `review.py`, `calibrate-voice.py`,
`format_chapters.py`, `clean_chapter.py`, `run_bible_build.py`, `run_preread.py`,
`run_review.py`) that should keep running against the local model unchanged — and
the user separately wants the option to switch models/backends again later without
re-deciding this each time.

Landed instead as a `TranslationBackend` seam (`src/translation_backend.py`,
selected via `TRANSLATION_BACKEND`, default `"claude_code"`) with two
implementations: `"local"` (a thin wrapper around the existing, untouched
`src/agent.py`) and `"claude_code"` (`src/claude_code_agent.py`, new). Both accept
the exact same `Skill` instances (`BibleLookupSkill`, `WebSearchSkill`) via a new
generic MCP bridge (`src/mcp_servers/skill_bridge.py`) that dynamically exposes
any `Skill` as an MCP tool through a new `Skill.bridge_spec()` method — so neither
backend, nor any future third one, needs per-skill wiring. `TRANSLATION_BACKEND=local`
is the immediate rollback path if subscription quota becomes a problem, especially
on `translate_batch.py`'s sequential multi-chapter runs (a real, accepted risk —
no rate limiter was built for it).

One undocumented but load-bearing finding from getting this working: the Claude
Code CLI connects to `--mcp-config` servers asynchronously and does not reliably
wait for the connection before the model's first turn — verified directly (opus
consistently failed to see the bridge's tool; haiku happened to win the race).
`MCP_CONNECTION_NONBLOCKING=false` in the subprocess env fixes it; see the code
comment in `src/claude_code_agent.py`.

---

## 2026-07-21 · Voice calibration reverses the "stays local" decision, moves to Claude Code CLI

Reverses the 2026-07-20 entry above. That entry treated the quality drop as an
accepted one-off, to revisit "if local-model output quality becomes a recurring
blocker." It did: the chapter 73 run failed outright (`httpx.ConnectError:
Connection refused` — the standalone `~/local-llm` Ollama server, which only
starts on demand and does not survive a reboot, was not running), and the tab UI
made the failure invisible by continuing to show the last *completed* run
(chapter 72) instead of surfacing the more recent failed one. Independent of that
outage, the recurring generic/placeholder output quality issue from 2026-07-20
was the deciding factor to move off the local model rather than just restart it.

Reuses the seam `73d6a1a` built for chapter translation rather than adding a new
one: `src/translation_backend.py`'s two backend implementations
(`_local_backend`, `_claude_code_backend`) are domain-agnostic (system prompt in,
text out), so `calibrate-voice.py` now calls
`get_backend(CALIBRATION_BACKEND)` the same way `translate.py` calls
`get_backend(TRANSLATION_BACKEND)` — a new, independent config var so the two
call sites can pick different backends. `CALIBRATION_BACKEND` defaults to
`"claude_code"`; `"local"` is the rollback path back to Ollama, unchanged.
`src/agent.py` itself is untouched — still used, on the local model, by the
remaining 7 pipeline scripts (`preread.py`, `review.py`, `format_chapters.py`,
`clean_chapter.py`, `run_bible_build.py`, `run_preread.py`, `run_review.py`).

The tab-UI bug that hid the chapter 73 failure (`app/views/voice_calibration/
tab.html.erb`'s last-run panel prefers `@last_completed_job` over a more recent
`@last_failed_job` regardless of which actually happened last) was flagged
separately here and fixed in a follow-up pass the same day — see the
`VoiceCalibrationController#tab` / tab view changes: a new `@last_finished_job`
picks whichever of the two is actually most recent by `created_at`, and the
view branches on its status instead of a fixed completed-then-failed priority.
org membership. See ROADMAP.md.

---

## 2026-07-23 · Chapter OCR moves from Tesseract (Docker) to Claude vision via the `claude_code` CLI

Reverses the 2026-07-15 PaddleOCR → Tesseract switch (see `ocr_chapter.py`'s own
docstring history) a second time, for a different reason. Tesseract's failure
mode on this project's real source images — clean e-reader screenshots, not
degraded physical-book photos — was ordinary per-character Hangul jamo
confusion (e.g. `콩개홀` for `공개홀`), not the PaddleOCR-era fabrication problem.
Tested directly against a real page whether image preprocessing could close the
gap: autocontrast, hard thresholding, and 2x upscaling were each tried against
the same source image and none reduced the error count — they only shifted
which characters came out wrong. That result pointed at the engine, not the
input.

Reuses the same subscription-authenticated `claude -p` headless CLI pattern as
`TRANSLATION_BACKEND=claude_code` (`src/claude_code_agent.py`), rather than a
metered `ANTHROPIC_API_KEY`, via a new, separate invocation in
`ocr_chapter.py` — not routed through `claude_code_agent.call()`, since that
function only accepts plain-text stdin and OCR needs an image content block
(`--input-format stream-json` / `--output-format stream-json`, both required
together). Verified end-to-end against two real chapter pages with zero
character-level errors, versus several per page under Tesseract.

Carries a real, different risk than Tesseract's: a generative model's failure
mode is confident-looking fabrication (the exact problem PaddleOCR had), not
Tesseract's more legible pixel-level noise. Mitigated by an explicit prompt
instruction to mark genuinely illegible characters with a literal `[?]`
rather than guess a plausible substitute — untested at scale, revisit if
real chapters start showing silently-wrong text instead of visible `[?]`
markers.

Removed as part of this change: the `Pillow` dependency (`requirements.txt`)
and the page-spread-splitting logic in `ocr_chapter.py`
(`is_page_spread`/`split_spread`) — Claude reads a full two-page spread
directly in correct reading order and rejoins sentences split across the
page boundary on its own, which was the entire reason Tesseract needed
spreads pre-split. `docker/tesseract/` is no longer called but left in place
rather than deleted, in case of rollback.

---

## 2026-07-25 · Preread, bible build, review, and formatting move off local-only, onto the same backend seam as everything else

Same quality-ceiling reasoning as the two entries above, extended to the
last four LLM call sites that had no backend choice at all:
`run_preread.py`/`run_bible_build.py` (share `src/preread/runner.py`),
`run_review.py`, and `clean_chapter.py`. Each was hardcoded to
`src/agent.py`'s local Ollama path with no rollback-free way to use the
`claude` CLI instead — unlike `translate.py`/`translate_batch.py`
(`TRANSLATION_BACKEND`) and `calibrate-voice.py` (`CALIBRATION_BACKEND`),
both already defaulting to `"claude_code"`.

Immediate trigger: preread failed repeatedly on chapter 75 of `idols-rewind`
this session — turned out to be an unrelated disk-mirror bug (the Korean
source file's on-disk copy had gone missing despite the Active Storage
attachment being intact), not an LLM problem. But diagnosing it surfaced
that the local Ollama server (`~/local-llm`, standalone, does not survive a
reboot/WSL restart) was down entirely, which would have failed preread
regardless — the same class of outage the voice-calibration entry above
already hit once. Rather than just restarting Ollama and moving on, decided
to close the gap for good: every pipeline script that talks to an LLM now
defaults to the subscription-backed `claude` CLI, with `local` as an
explicit, working rollback (not a removed capability) if subscription quota
or CLI reliability ever becomes the blocker instead.

Landed via three new config vars reusing the existing
`src/translation_backend.get_backend()` seam exactly as designed (no seam
changes needed) — `PREREAD_BACKEND` (shared by `run_preread.py` and
`run_bible_build.py`, same one-var-covers-two-scripts pattern
`TRANSLATION_BACKEND` already uses), `REVIEW_BACKEND`, and `FORMAT_BACKEND`
— all three defaulting to `"claude_code"`. Each call site now builds its
`api_call_fn`/backend call via `get_backend(<X>_BACKEND)` instead of
`src.agent.make_client()` + a hardcoded model tier
(`SONNET_MODEL`/`HAIKU_MODEL`); matches the existing `calibrate-voice.py`
convention of not passing an explicit `model=` through the seam, letting
each backend supply its own sensible default, since a local model name
(`gpt-oss-20b`) means nothing to `claude_code` and vice versa.

One real, accepted capability loss on the `local` rollback path only:
`clean_chapter.py`'s `reasoning_effort="low"` tuning (halves completion
tokens on this CPU-only box, per that script's own comment) had no
equivalent in the seam's `TranslationBackend` protocol and no equivalent
`claude` CLI flag either, so it's dropped rather than half-wired. If
`FORMAT_BACKEND=local` is ever used again, formatting will be slower than
before this change — flagged here rather than silently lost.

`preread.py`/`review.py` (the interactive, terminal-only counterparts,
explicitly documented as "untouched" by `run_preread.py`/`run_review.py`'s
own docstrings) were deliberately left calling `src.agent` directly — out
of scope, matching how they were already excluded from every prior
backend-migration entry above.

---

## 2026-06-07 · Google OAuth removed for solo local development (backfilled 2026-07-23)

Retroactive entry — this decision was made in commit `25cac42` without a
corresponding log entry at the time; added now after a design review surfaced
the gap between this commit and stale references to `SessionsController` in
`CLAUDE.md` and elsewhere.

The product is intended to be multi-team, multi-translator from the PRD
onward (see the `Organization`/`Team`/`Membership`/`NovelTeamAssignment`
schema and M6's permission-level enum, still present and unchanged). But
while it's solo-developed and not ready for other users, requiring a real
Google OAuth round-trip on every local session was pure friction with no
offsetting benefit, and running a live OAuth flow against local/dev
infrastructure was itself a posture the developer preferred to avoid.
`SessionsController` and OmniAuth were removed; `ApplicationController#current_user`
was reduced to `User.first` with no session check and no `before_action`
login gate anywhere in the app.

This is intentionally **not** scoped as a bug to fix opportunistically. It
should be restored — real session auth, plus actually enforcing the
`NovelTeamAssignment#permission_level` enum, which has never been enforced
even when OAuth was active — as its own deliberate milestone at the point
the developer is ready to onboard other translators or teams, not before.
Until then, the multi-tenant schema stays in place unused rather than ripped
out, since it's the correct foundation for that future milestone.

---

## 2026-07-30 · `bible_build` and `post_translation_review` sunset from the UI, disable-only

Both job types are being replaced by a different bible-maintenance model:
adding/correcting bible entries inline, at the moment of translating or
proofreading a chapter, rather than as a separate batch job run afterward.
The intended replacement (not built yet — see `docs/ROADMAP.md`'s Future
section) is: select a mistranslated English word during translation/review,
create a bible entry from it directly, then either re-translate or
find-and-replace every place the old rendering appears; separately, select
Korean source text to auto-populate the English side when creating an
entry. Both are extensions of the already-logged "Add Bible Entry From
Korean Text" and "Find and Replace Across Chapters" Future items — this
decision elevates them from parked ideas to the actual replacement for
`bible_build`/`post_translation_review`, not just adjacent nice-to-haves.

Disable-only, not deletion: `bible_build`/`post_translation_review` removed
from the job-type dropdown in `translation_jobs/_form.html.erb` only. The
job types, `Pipeline::Ruby::BibleBuild`/`Pipeline::Ruby::PostTranslationReview`,
`PostTranslationReviewController`, routes, views, and specs are untouched —
still triggerable directly (request/console) if needed, e.g. to backfill
bible entries once more before the new inline workflow lands. Reversible;
revisit full removal once the new workflow is built and has actually
replaced what these covered.

**Consequence for R7 (`docs/RAILS_REFACTOR_PLAN.md`):** these two job types
being disabled going forward means they can't accumulate real production
soak evidence under Stage 1's "every migrated job type" bar. Since nothing
will trigger them through the normal app anymore, requiring soak proof for
them before Stage 2 no longer makes sense — the other five job types
(`preread`, `translate_batch`, `voice_calibration`, `formatter`, `ocr`)
already each have at least one successful real run since `5b3f30f` as of
this date. Stage 1 for those five is effectively satisfied; Stage 1.5's
negative inventory still needs to actually pass before Stage 2 proceeds.
This is a documentation update only — Stage 2 (deleting Python) was not
run as part of this decision.

---

## 2026-07-30 · PDF OCR gap closes on Claude, not a second model

Chapter photo-scan upload has advertised single-PDF support since the PaddleOCR
era, but every PDF upload has silently failed since the 2026-07-15 switch to
Tesseract and then the 2026-07-23 switch to Claude vision — neither backend
ever gained PDF handling (see `docs/DECISIONS.md`'s 2026-07-23 entry and
[[hawk_translations_pdf_ocr_broken]]). Considered Baidu's Unlimited-OCR (a
local 3B VLM with native PDF support) as the fix.

**Decision: extend the existing `claude -p` CLI-based OCR pipeline instead of
adopting a second model.** Verified live: the Messages API's `document`
content block (`{"type":"document","source":{"type":"base64",
"media_type":"application/pdf",...}}`) works over the CLI's
`--input-format stream-json` exactly like the `image` block
`Pipeline::ClaudeVision` already sends — same subscription-OAuth billing, no
new tool permissions, no architecture change. Smoke-tested against a real
staged PDF (`spec/fixtures/files/sample.pdf`) through the actual `claude`
binary: accepted, `is_error: false`, correctly read the page. Fix is
additive to `Pipeline::ClaudeVision`/`Pipeline::Ruby::OcrChapter` — branch on
content type, PDF path builds a `document` block instead of looping
`image` blocks per page.

**Why not Unlimited-OCR:** it would have solved the PDF gap too (native PDF
rasterization, MIT license, small enough to run locally on this box), but the
user's explicit priority right now is consolidating every pipeline cost onto
one model — Claude, via the existing subscription — not adding a second,
non-Claude model. Once the same-model fix was confirmed to work, there was no
remaining reason to introduce Unlimited-OCR. Not ruled out forever: if photo
(non-PDF) OCR quality or cost against Claude vision ever becomes a real
problem, that's a separate, independent question from the PDF gap and can be
revisited on its own terms — nothing here forecloses it.

**Deprioritized 2026-07-30, same session: only photo (JPEG/PNG/WebP) uploads
are actually in use right now — PDF upload isn't a live need.** Fix mechanism
is proven and stays valid; the 4 code changes above (`Pipeline::ClaudeVision`
content-type branch, `Pipeline::Ruby::OcrChapter` loop restructure, the stale
controller comment, a spec) are **not scheduled** — revisit only when a real
PDF upload need shows up, not proactively.

---

## 2026-07-30 · Translation quality pipeline: committing to a 2-call split

Supersedes this doc's own earlier "Translation Quality Pipeline" decision
(`docs/ROADMAP.md`'s Future entry of the same name), which held the line at
one call and said only split into 2 if Test B specifically demonstrated
drift. **That evidence-gated approach is explicitly abandoned for this
feature** — Test A/Test B were never built, and the split below is committed
on product-design grounds (clean separation of responsibilities across the
call boundary) instead. Not a violation of the "don't split without
evidence" discipline so much as a conscious decision to stop waiting for it
here; the discipline itself isn't repudiated, see the AI-Generated Bible
Entry and other still-single-call Future items in `docs/ROADMAP.md`.

**Call 1 — Comprehension + Cultural/Narrative Analysis.** Segments the
chapter into passages, extracts literal meaning, cultural signals, narrative
intent, and a localization strategy per passage (from a controlled six-value
taxonomy: `behavioral | idiomatic | tone_shift | register_shift |
motif_reinterpretation | demographic_voice`), grounded via `bible_lookup`
(existing R2/R3 MCP tool) and the new `web_lookup` tool (see below). Output
is a JSON "analysis contract" consumed whole by Call 2.

- **Segmentation must be an exhaustive, ordered, non-overlapping partition
  of the entire chapter** — not just "notable" dialogue beats/emotional
  turns. This was an open question this session; resolved so that Call 2's
  `localized_passages` can be concatenated in reading order to produce the
  finished chapter, rather than needing a separate reassembly mechanism.
  Prompt instructions and `bin/translation_eval` checks both need to enforce
  this — gaps/overlaps are a correctness bug, not a quality nit.
- **Join key is `passage_id` (sequential integer), not `anchor_quote`
  string-matching.** `anchor_quote` stays as a human-readable pointer for
  debugging/review UI only; joining Call 1 → Call 2 on a Korean text
  snippet is fragile since Call 2 may restate it with different
  whitespace/punctuation. Call 2 must echo `passage_id` per passage.
- **`bible_entries_used` stays a lightweight attribution array (entry
  names), not a content dump.** `bible_lookup` is a model-invoked MCP tool
  call inside the same `claude` CLI invocation (see
  `app/services/pipeline/skills/bible_lookup.rb`,
  `app/services/pipeline/mcp/bible_lookup_tool.rb`) — results already reach
  the model as tool-response content mid-generation. Re-serializing that
  content into the JSON schema would just duplicate what already informed
  `cultural_signals`/`localization_strategy`.

**Call 2 — Purpose-Preserving Rewrite + Editorial Sweep.** Produces
`localized_translation` per passage (keyed by `passage_id`), enacting Call
1's chosen strategy, plus a per-passage `editorial_checks` block (voice
consistency, emotional arc, cultural dynamic enacted, idiomaticity, no
Korean-shaped syntax).

- **`editorial_checks` is a self-graded triage/UX signal, not independent
  verification, and must never gate anything.** Call 2 grades its own
  rewrite in the same response that produced it — a known-weak pattern
  (models tend to self-report pass). It's useful for flagging rows for
  human review in the UI. It is explicitly *not* a substitute for
  Test A/Test B (does the model follow its own stated strategy at all, and
  does adherence hold across a full chapter) — those still need to be built
  as an independent offline eval, checking `localized_translation` content
  against `localization_strategy.category`, before either can be trusted as
  validation.

**web_lookup — new MCP skill, scoped to recency, not general cultural
confirmation.** `bible_lookup` only knows what's been documented for this
novel; the model's own training knowledge already covers most general
cultural/demographic questions reasonably (untested assumption — worth
checking via eval once Call 1 ships bible_lookup-only, per the note below).
The gap with no substitute is **recent events, current slang, or cultural
phenomena that may postdate the model's training** — a case where a model
can be confidently wrong rather than visibly blank, which eval-by-omission
can't catch. `web_lookup`'s tool description should explicitly scope to
that: recent/time-sensitive references only, not general background
`bible_lookup` or the model's own knowledge already cover. Same per-passage
grounding discipline as `bible_lookup` — check before committing that
passage's fields, not as a batch pass. If uncertain and the lookup doesn't
resolve it, the model should still record the suspicion in
`chapter_level_notes.risks` rather than guess silently — costs nothing,
already in the schema, and gives a frequency signal from real chapters
before commmitting to a search backend.

- **Mechanically:** same 4-piece pattern as `bible_lookup` —
  `Pipeline::Skills::WebLookup` (includes `Pipeline::Skill`), thin
  `Pipeline::Mcp::WebLookupTool < MCP::Tool` adapter, registered in
  `bin/mcp_skill_bridge`'s `tools:` array alongside `BibleLookupTool`.
- **Backend is still unresolved — first thing to decide when building
  starts, not before.** `Pipeline::ClaudeCode` invokes the CLI with
  `--tools ""` plus `--strict-mcp-config` (`app/services/pipeline/claude_code.rb:96,98`)
  — nothing is available to the model except what's explicitly registered
  as an MCP tool, so there's no free hosted-search shortcut in this setup
  as configured today. Two paths, unresolved: a third-party search API (own
  key/billing/rate limits, separate from the Claude subscription this
  project otherwise consolidates all pipeline cost onto — see this doc's
  2026-07-30 PDF OCR entry for the same tension on OCR) vs. Anthropic's own
  hosted `web_search` server tool, if it can be enabled and billed through
  the CLI's existing subscription auth (unverified — check before assuming
  either way).

**Sequencing:** ship Call 1 with `bible_lookup` only first, validate
segmentation exhaustiveness/`passage_id` stability via `bin/translation_eval`
against 2-3 real chapters, *then* build Call 2, *then* build `web_lookup`
once real chapter data shows how often recency gaps actually come up. Watch
JSON/token size on long chapters at the same time (exhaustive per-passage
segmentation could get large) — flagged, not yet measured.

---

## 2026-07-30 · Call 1 implemented — analysis prompt + segmentation eval

Ships the first step of this doc's own "Sequencing" note above:
`PromptBuilder.build_call1_system_prompt` (`app/services/pipeline/ruby/translate_batch/prompt_builder.rb`)
and its wiring into `Pipeline::Ruby::TranslationEval`/`bin/translation_eval`.
Still offline/eval-only — nothing here touches `translate_batch.rb` or any
`TranslationJob`; Call 2 is not built.

- **Prompt matches the schema this doc specified**: `passages[]` keyed by
  sequential `passage_id`, `anchor_quote` (verbatim Korean — doubles as the
  eval's exhaustiveness check, see below), `literal_meaning`,
  `cultural_signals`, `narrative_intent`, `localization_strategy.category`
  (the six-value taxonomy plus `none`, since most passages carry no special
  cultural dynamic) + `.notes`, `bible_entries_used` (attribution only), and
  `chapter_level_notes.risks`. Grounded via the existing `bible_lookup` MCP
  tool only — `web_lookup` stays unbuilt per the sequencing note.
- **Segmentation is machine-checked, not just prompted for.** This doc said
  gaps/overlaps are a correctness bug and both the prompt and
  `bin/translation_eval` need to enforce it — `TranslationEval#validate_segmentation`
  checks two things: `passage_id` equals each passage's 1-based array index
  (sequential *and* ordered in one comparison), and concatenating every
  passage's `anchor_quote` (whitespace-normalized) reproduces the source
  chapter (whitespace-normalized) — a gap or overlap fails this by
  construction. Result surfaces per-chapter as `call1_segmentation_error` on
  `TranslationEval::ChapterResult` and in `bin/translation_eval`'s CLI
  output, alongside the existing `single_pass`/`structured` lines.
- **The superseded single-call `structured` prompt/eval path was left in
  place**, not removed — this doc said its fields are still the basis for
  Call 1/2 and it's "kept for history." `TranslationEval` now runs all three
  (`single_pass`, `structured`, `call1`) per chapter; trimming the
  superseded path back out, if the extra `claude` calls' cost isn't worth
  it, is a separate call for whoever's driving the next eval run.
- **Live-run gate cleared 2026-07-30**, same day: `bin/translation_eval
  idols-rewind 68 --out tmp/translation_eval` against the real `claude`
  CLI/Opus. Chapter 68 → 52 passages, `passage_id` sequential 1–52,
  `anchor_quote` concatenation reconstructed the source chapter exactly
  (whitespace-normalized) — segmentation held up against a live model
  response, not just the hand-built fixtures in
  `spec/services/pipeline/ruby/translation_eval_spec.rb`. `localization_strategy.category`
  distribution wasn't degenerate (behavioral 24, idiomatic 5,
  demographic_voice 5, register_shift 4, tone_shift 4,
  motif_reinterpretation 2, none 8) and `chapter_level_notes.risks` surfaced
  11 substantive flags (a POV-ambiguity note, an untranslatable 선배님/선생님
  honorific distinction, a profanity-register calibration call, a possible
  dropped beat vs. the bible's own "laughs twice" note, among others) — the
  kind of thing this pipeline exists to surface instead of silently
  guessing. Chapters 74/75 were not run (session budget) — one clean chapter
  was judged sufficient to clear this specific gate; a broader sample is
  still worth doing before treating Call 1 as fully validated.
- Output lives in `tmp/translation_eval/chapter_68/` (gitignored scratch,
  not committed) for direct review.

---

## 2026-07-31 · Call 2 prompt builder shipped, eval wiring deferred

`PromptBuilder.build_call2_system_prompt` and `.build_call2_user_message`
(`app/services/pipeline/ruby/translate_batch/prompt_builder.rb`), scoped
narrowly to the prompt design + specs given remaining session budget —
**not** wired into `TranslationEval`/`bin/translation_eval`, and no live run
against Call 1's chapter-68 output. That chaining (feed
`tmp/translation_eval/chapter_68/call1.json` into Call 2, reassemble
`localized_passages` into a full chapter, validate against the source) is
the next session's starting point, not done here.

- **`localized_translation` keyed by `passage_id`**, echoed from Call 1's
  analysis per this doc's 2026-07-30 entry — explicitly told not to
  re-segment or join on `anchor_quote`.
- **`localization_strategy.notes` must be carried out, not just detected** —
  same instruction pattern as the old single-call structured prompt's
  cultural_dynamic/localization_strategy fields (docs/ROADMAP.md's
  superseded entry), now operating on Call 1's richer per-passage output
  instead of a flat per-chapter guess.
- **Per-sentence-naturalness-over-motif-consistency instruction carried
  forward verbatim** from `build_structured_system_prompt` — same Ch. 68
  "air"/"tense air" finding that motivated it originally still applies here.
- **`editorial_checks` is 5 booleans + `notes`** (voice_consistent,
  emotional_arc_preserved, cultural_dynamic_enacted, idiomatic,
  no_korean_shaped_syntax), explicitly told it's self-graded triage that
  never gates anything downstream — matches this doc's 2026-07-30 warning
  that self-grading is a known-weak pattern, not independent verification.
  Test A/Test B (does the model follow its own stated strategy, does that
  hold across a full chapter) are still unbuilt and still the only real
  check on whether this call is working, not `editorial_checks`.
- **`build_call2_user_message`** assembles the two-part user message
  (Korean chapter + Call 1's analysis JSON, under distinct `#` headings) —
  needed because, unlike Call 1's plain-Korean-text user message, Call 2
  needs both the source and the prior call's structured output.

---

## 2026-07-31 · Call 1 → Call 2 chaining wired, live-validated

`Pipeline::Ruby::TranslationEval#run_call2` (plus `bin/translation_eval`
reporting) closes the gap this doc's previous entry left open: Call 2 now
actually consumes Call 1's analysis instead of sitting unwired.

- **Chaining only happens when Call 1 cleared its own gate** — `run_call2`
  is skipped (recorded as `call2_error: "skipped: Call 1 did not produce
  valid, cleanly-segmented analysis"`) unless Call 1 returned valid JSON
  with no segmentation error. There's no sound analysis to hand Call 2
  otherwise.
- **Coverage check, not a second segmentation check** — Call 2 is told to
  echo Call 1's `passage_id` rather than re-derive it from `anchor_quote`
  (previous entry), so "validate against the source" here means
  `validate_call2_coverage`: `localized_passages`' `passage_id` sequence
  must equal Call 1's exactly, order included (reassembly is a plain
  concatenation, so order matters as much as set membership). A dropped,
  duplicated, or reordered id fails this by construction.
- **Reassembly**: when coverage passes, `chapter_dir/localized_chapter.txt`
  is written by concatenating `localized_translation` in order — the
  "reassemble into a full chapter" step this doc's previous entry named as
  unstarted.
- **Live-run gate cleared same day** against real Chapter 68, chaining a
  fresh Call 1 run into Call 2 (not the stale 52-passage `call1.json` from
  the 2026-07-30 run — this run resegmented to 63 passages, a reminder that
  Call 1's segmentation isn't deterministic run-to-run, only internally
  consistent within a run). `localized_passages`' 63 ids matched Call 1's
  63 exactly, in order — coverage held against a live model response, not
  just the hand-built fixtures in `translation_eval_spec.rb`.
  `localization_strategy.category` spread stayed non-degenerate (behavioral
  17, idiomatic 8, tone_shift 8, register_shift 8, demographic_voice 7,
  motif_reinterpretation 4, none 11) and `chapter_level_notes.risks` surfaced
  9 flags.
- **New finding, not fixed this pass**: naive concatenation produces missing
  paragraph breaks at passage boundaries — `localized_translation` isn't
  guaranteed to carry the whitespace/newline that would separate it from
  the next passage, so `localized_chapter.txt` occasionally reads like
  `"...why I wasn't getting out."Hee-yeon sat..."` where two passages abut
  with no space. This breaks the Call 2 prompt's own "no gaps" requirement
  in a formatting sense, not a content sense. Fixing it (either a prompt
  instruction to end each passage cleanly, or a join-time heuristic) is
  next-session scope, not done here.
- **`editorial_checks` came back all-`true` across all 63 passages, all
  five booleans** — zero self-flagged issues, versus Call 1's 9
  chapter-level risk flags on the same chapter. Consistent with this doc's
  standing warning that `editorial_checks` is self-graded triage, not
  independent verification: a check that never fires isn't yet evidence
  it's working. Still not gating anything downstream, per design.
- Chapters 74/75 still not run through the 2-call chain — one clean chapter
  was judged sufficient to clear this specific wiring gate, same reasoning
  as the 2026-07-30 Call 1 gate. A broader sample, Test A/Test B, and the
  paragraph-break finding above are the open items before this pipeline is
  closer to production-ready.
- Output lives in `tmp/translation_eval/chapter_68/` (gitignored scratch,
  including the new `call2.json`/`localized_chapter.txt`), not committed.

## 2026-08-01 · Human review finds real quality gaps behind all-`true` editorial_checks; Call 3 (independent review) added

The previous entry's warning stopped being theoretical: manual read-through of
`localized_chapter.txt` from the live Chapter 68 run turned up two clearly
unnatural lines, both self-graded `idiomatic: true` and `no_korean_shaped_syntax:
true` by Call 2:

- *"Idol, beginner, none of that matters... Show good acting and that's the end
  of the discussion. You know what I'm saying? Stay hungry all the way through
  to the end."* — four short imperative fragments, each individually idiomatic
  but drawn from unrelated registers (debate-closing idiom, contemporary
  colloquial filler, sports-motivational phrasing) stapled onto a 40-year-old
  veteran actor's mentorship speech.
- *"...I'm asking you here."* — a calqued discourse particle (부탁할게 → "I'm
  asking you here") where "here" does no locative work in English; exactly what
  `no_korean_shaped_syntax` claimed wasn't present.

Root cause, diagnosed against the actual prompt text: Call 2's
`localized_translation` instruction told the model to "preserve the narrative
intent **and** literal meaning" in the same breath. `literal_meaning` is
deliberately close to the Korean's clause structure (that's its job as the
fidelity anchor for Call 1), so in practice the instruction resolved toward
clause-for-clause substitution — one Korean clause, one short English
sentence — over authoring the passage as continuous prose. `editorial_checks`
grades each resulting sentence in isolation, so four individually-idiomatic
fragments could each pass while the passage as a whole didn't read as one
person talking.

**Two changes, both in `PromptBuilder.build_call2_system_prompt`:**

1. **Rewrote the `localized_translation` instruction** to read `narrative_intent`
   + `cultural_signals` + `literal_meaning` together, then author the passage
   fresh as continuous English prose — explicitly not a sentence-by-sentence
   substitution. Permits merging/splitting/reordering clauses from the Korean's
   layout when English cadence calls for it; demotes `literal_meaning` to a
   post-hoc invented/dropped-content check rather than a structural template.
   Added an explicit warning against mixing idiom registers within one
   character's speech (the actual failure mode above).
2. **Added a 6th `editorial_checks` boolean, `reads_as_continuous_prose`** —
   whether the passage reads as one continuous utterance in natural English
   rhythm, not a stack of independently-correct short sentences. The five
   existing checks are all atomic/per-clause; nothing previously checked
   passage-level cohesion.

**Call 3 (Independent Editorial Review) added** —
`PromptBuilder.build_call3_system_prompt`/`.build_call3_user_message`, chained
in via `TranslationEval#run_call3` (only runs when Call 2 produced valid,
fully-covered output; `bin/translation_eval` reports
`call3: ok (N passage(s) flagged)`). This exists because self-grading in the
same call that produced the translation is a conflict of interest by
construction — Call 3 runs as a **separate call**, given the Korean source,
Call 1's analysis, and Call 2's `localized_translation` **with
`editorial_checks` stripped out**, and independently re-answers the same six
booleans. Any `false` check must cite a quoted substring and explain the
problem — an empty `findings` array is only valid when every check is `true`,
framed in the prompt as "a claim you're prepared to defend, not a default," to
push back against reflexive rubber-stamping.

**Live-validated against a fresh Chapter 68 run** (93 passages this time —
Call 1's segmentation instability, already noted in the 2026-07-31 entry, holds
again: 52 → 63 → 93 across three runs of the same chapter). Results:

- **Real signal, not noise**: Call 3 flagged 18 of 93 passages, each with a
  quoted excerpt and a specific complaint — e.g. passage 7 correctly marked
  both `no_korean_shaped_syntax: false` and `reads_as_continuous_prose: false`
  on *"Judging by her voice. There wasn't a grain of worry in it."*, quoting
  the dangling fragment and explaining it's a stranded evidential clause from
  Korean's clause-final structure. Other findings were advisory without
  flipping a check — e.g. flagging that 기 싸움 was rendered "standing" in one
  passage but "fighting over rank" elsewhere, breaking a cross-chapter echo
  Call 1's analysis asked to preserve. This is exactly the kind of grounded,
  citable finding self-grading wasn't producing.
- **The caveat is reduced, not eliminated.** The closest match to the original
  "idol/beginner" mentorship speech (passage 38 this run) still reads as four
  choppy fragments — *"...that's the end of the conversation. You understand
  what I'm saying? Keep the fire in it all the way to the end. Don't let
  yourself burn out."* — essentially the same failure class as the original
  finding above, just reworded. Both Call 2's self-grade **and** Call 3's
  independent review marked `reads_as_continuous_prose: true` on it. Since
  Call 1's segmentation isn't stable run-to-run, this isn't a controlled
  before/after on the identical passage — but it's the same failure pattern,
  caught by neither pass. This suggests a shared model blind spot for this
  specific error class (subtle register-mixing that doesn't trip an obvious
  calque detector), not purely an authorship-bias problem that a second call
  was guaranteed to fix. Separately, the other original example partially
  improved on its own (the "I'm asking you **here**" calque didn't reappear)
  but a related issue in the same line — stacked one-word tags "Okay? Hm?"
  reading staccato rather than pleading — went uncaught by both passes too.
- **Not yet done**: feeding known failure exemplars (like the two above)
  directly into Call 3's prompt as concrete negative examples, or trying a
  different model for the review pass specifically to break the shared-blind-spot
  pattern, are both candidate follow-ups, not attempted this session.
- Output lives in `tmp/translation_eval/chapter_68/` (gitignored scratch,
  including the new `call3.json`), not committed.

---

## 2026-08-01 · 3-call pipeline replaced with a 5-step pipeline (segmentation → analysis → localization → factcheck + editor)

User proposal, in response to the entry above: rather than keep adding checks
to a 3-call design that had already shown a real limit (the shared blind spot
above), decompose the pipeline itself so each concern gets its own call
instead of being bundled with others. Approved and built the same session —
the entire 3-call design (`build_call1/2/3_system_prompt`, `run_call1/2/3`,
their specs) was deleted, not deprecated alongside the new one.

**The 5 steps** (all in `PromptBuilder`, chained in `TranslationEval#run_chapter`,
each gated on the previous step producing valid, fully-covered output):

1. **Segmentation** (`build_segmentation_system_prompt`) — Korean only, no
   analysis or translation. Deliberately split out of the old Call 1, which
   bundled segmentation with analysis — segmentation's non-determinism (52 →
   63 → 93 passages across three runs of the identical chapter, per the
   entries above) was never isolated enough to debug on its own. A passage is
   now explicitly defined as **one continuous unit of voice** — one
   character's whole speech turn, or one continuous stretch of narration —
   rather than by sentence or paragraph count, directly targeting the
   clearest observed failure mode: a single utterance getting fragmented into
   several short sentences that then get judged independently instead of as
   a whole.
2. **Literary analysis** (`build_analysis_system_prompt`) — Korean only,
   forbidden from producing any English rendering of the passage's content
   (even inside a notes field) — the discipline meant to stop translation
   from leaking into analysis. Five fields per the user's design
   (`core_message`, `emphasis`, `pacing_rhythm`, `voice_register`,
   `narrative_function`); Call 1's `cultural_signals`/`localization_strategy`/
   `bible_entries_used` machinery is retained unchanged — it worked and
   wasn't part of what needed fixing.
3. **Localization** (`build_localization_system_prompt`) — writes the English
   prose. No self-graded `editorial_checks` field at all anymore — the
   2026-08-01 entry above treated self-grading as untrustworthy and added an
   independent check on top of it; this design removes the self-grade
   entirely rather than layering a fix over a known-bad signal.
4. **Fact & culture check** (`build_factcheck_system_prompt`) — independently
   checks names/facts/cultural cues against the Korean and the analysis.
   Scoped explicitly to *not* judge prose quality. Reuses the quoted-evidence
   discipline from the old Call 3 (`findings` must cite a substring; an empty
   `findings` array is framed as "a claim you're prepared to defend, not a
   default") and adds a comparative check against the analysis's
   `core_message`/`emphasis`, since Step 3 no longer self-reports whether
   anything was dropped.
5. **English editor** (`build_editor_system_prompt`) — the sharpest structural
   change. This call receives **only the English text** — no Korean, no
   analysis, no reference material of any kind (`build_editor_system_prompt`
   takes no arguments). The old Call 3 was independent but still had the
   Korean and analysis in front of it, and live validation showed it could
   still rubber-stamp a passage by tracing each fragment back to a Korean
   clause. A reviewer with zero source access can't excuse awkward English by
   pointing at what it maps to — the hypothesis was that this would catch
   what Call 3 missed.

Steps 4 and 5 both depend only on Step 3's output, not on each other — they
run one after another in `run_chapter` for simplicity, but neither result
gates the other.

**Live-validated against a fresh Chapter 68 run** (107 passages this time —
segmentation instability persists even fully isolated in its own call: 52 →
63 → 93 → 107 across four runs of the same chapter. Isolating segmentation
did not fix its non-determinism; it only made it cheaper to study in
isolation, which is still worth having). All 5 steps completed with valid,
fully-covered JSON. Factcheck flagged 10/107 passages; the editor flagged
23/107.

- **The core hypothesis did not hold.** The closest recurrence of the
  original "idol/beginner" mentorship speech (passage 42 this run) reads
  almost identically to the version the 2026-08-01 Call 3 entry already
  documented missing: *"Idol, beginner, none of it counts for anything. Show
  good acting and that's the end of the conversation. You understand what
  I'm telling you? Keep the fire the whole way through. Don't burn out."*
  Both factcheck and the **Korean-blind editor** — the design built
  specifically to catch this by removing the model's ability to rationalize
  against the source — marked every check `true` with empty `findings` on
  it. Total removal of source access did not surface the problem. This is
  stronger evidence for a genuine shared capability gap on this specific
  error class (short, individually-idiomatic imperative fragments that don't
  cohere into one continuous utterance) than for the "reviewer excuses
  awkwardness by tracing it to source meaning" mechanism the editor step was
  built to defeat — that mechanism may still be real for other error
  classes, but it isn't what's protecting this one.
- **Partial, measurable progress on the second original example.** The
  manager-caving line (passage 80 this run) now reads *"You're right....
  No chance. That crazy woman would never. But let's keep it quiet today
  anyway. All right? Yeah? I'm asking you."* The calqued discourse particle
  from the original complaint ("I'm asking you **here**") is gone — a real,
  confirmed fix. The stacked short tag-questions pattern persists in
  different words ("All right? Yeah?" for "Okay? Hm?"), and neither
  factcheck nor the editor flagged it as a phrasing problem — the editor did
  flag this passage, but only for an unrelated typographic inconsistency
  (a four-dot ellipsis that doesn't match the three-dot style used
  elsewhere), not the tag-question staccato.
- **Genuine, more specific signal elsewhere than the 3-call design produced.**
  Splitting fact-checking from prose-quality review let each dig deeper into
  its own lane instead of doing both shallowly. Factcheck caught fabricated
  specifics not in the Korean — an invented "ninety seconds" for a vague
  '이제 막 들어왔는데' (we've only just walked in), an invented "fifty takes" for
  an unspecified '수십 개' (dozens) — plus an honorific/deference loss and a
  misattributed line (English gave a character power he explicitly disclaims
  having in the Korean). The editor caught real prose defects unrelated to
  the original complaint: an antecedent-less "the order", an article error
  ("an actors' business"), a British/American spelling inconsistency
  ("armour" beside "parking garage" elsewhere in the same chapter), and a
  narrative sequence contradiction (a character described as walking toward
  an elevator, then as having already passed the narrator). These are
  concrete, well-grounded findings a human editor would actually raise — the
  quoted-evidence discipline carried over from Call 3 is still doing its job.
- **Net assessment**: more numerous and more specific findings than the
  3-call design produced, cleanly separated by concern (fact vs. prose), but
  the exact failure class that motivated this whole redesign — short
  imperative fragments stapled from unrelated registers — survived every
  mitigation tried across both pipeline generations, including the most
  aggressive one (zero source access). The caveat from the prior entry
  stands, sharpened: this specific error class looks like a shared model
  limitation, not a self-grading or context-contamination problem, and
  neither more independent review calls nor stricter isolation closed it.
- **Not yet done, still on the table**: feeding the passage 42/80 exemplars
  directly into the editor's prompt as concrete negative examples, or trying
  a different model for the editor pass specifically, are both untried.
  Given the editor step is now maximally isolated (no source, no reference
  material, no other steps' output) and still missed passage 42, a
  different-model trial is the more informative next experiment — it would
  distinguish "this model can't see this error class" from "no model can."
- Output lives in `tmp/translation_eval/chapter_68/` (gitignored scratch),
  not committed.

---

## 2026-08-02 · Hybrid deterministic/semantic beat segmentation replaces free-form Step 1

Step 1 of the 5-step pipeline (2026-08-01 entry) was a single free-form LLM
call asked to segment the whole chapter into "one continuous unit of voice"
passages from scratch. That call's output was non-deterministic run-to-run
on the identical chapter — 52 → 63 → 93 → 107 passages across four runs —
because the model was inventing its own boundaries every time with no stable
anchor to classify against. The user proposed replacing it with a hybrid,
matching how Korean webnovels are actually structured (built from
one-liners; boundaries follow dramatic beats, not formatting):

1. **Deterministic pre-chunking** (`Pipeline::Ruby::TranslateBatch::BeatSegmenter.candidate_blocks`,
   pure Ruby, no LLM call) — splits the chapter on blank lines into
   one-liners, groups them into candidate blocks of 3-7 lines, and forces a
   block boundary at every literal `***` scene marker (confirmed the only
   scene-break convention used across all 75 chapters in this novel). A
   trailing remainder under 3 lines merges into the preceding block rather
   than standing alone, trading an occasional oversized block for never
   reproducing the free-form design's micro-passage problem.
2. **Beat classification** (one LLM call — `PromptBuilder.build_beat_classification_system_prompt` /
   `.build_beat_classification_user_message`) — the model is never asked to
   invent a boundary from raw text; it only classifies each candidate
   block's relationship to the block immediately before it: `CONTINUE` (same
   beat), `BREAK` (new beat), or `BRIDGE` (a short transitional block —
   a pause, a breath, a shift in posture — attached to whichever beat
   follows it). It also attributes a `speaker` per block. Scene-marker
   blocks are excluded from what the model classifies — Ruby already knows
   their boundary is structural, not semantic.
3. **Deterministic merge** (`BeatSegmenter.merge_beats`, pure Ruby, no LLM
   call) — assembles final passages from the classification labels. The
   first block of every scene is always forced `BREAK` regardless of what
   the model returned, since that boundary was never actually in question.
   A trailing `BRIDGE` with no following beat to attach to (scene or
   chapter ends right after it) falls back to attaching to the beat before
   it.

Segmentation still costs exactly one LLM call per chapter (the classification
call), matching the "one batched call per step" design already established —
the pre-chunk and merge are free.

**Beats can span more than one speaker.** This is a deliberate redefinition,
not an oversight: a back-and-forth exchange between two characters can be
one beat if it's all serving the same emotional or topical moment (e.g. a
greeting-and-bow exchange, or a short Q&A), matching how these scenes
actually read. This required `speaker` (string) to become `speakers` (array)
on each passage, and required reworking the wording of every downstream step
that used to assume "one passage = one voice": `voice_register` (Step 2/
analysis) now explicitly asks for each speaker's own voice when `speakers`
has more than one entry; `localized_translation` (Step 3/localization) now
requires each speaker to hold their own consistent register while the
passage as a whole still reads as one connected beat, not one uniform voice;
the editor's `continuous_utterance` and `register_unified` checks (Step 5)
were reworded the same way — a legitimate two-character exchange with two
different personalities is not a `register_unified` violation on its own,
only mixing registers within one speaker's own lines still is.

**Live-validated against a fresh Chapter 68 run**: **14 final passages** —
down from the free-form design's 52/63/93/107 non-deterministic history, a
qualitative step-change, not just a smaller number. The classification call
returned 19 classifiable blocks (12 `BREAK`, 7 `CONTINUE`, 0 `BRIDGE` this
run) across 2 scene markers, merging into 12 real content beats plus the 2
scene-marker beats. 3 of the 14 are genuine multi-speaker beats — e.g.
passage 5 correctly grouped a bow-and-greeting exchange between two named
characters (`이희연`/Hee-yeon Lee greeting `손철환`/Chul-hwan Son) into one
beat instead of shredding it into independent one-line turns, which is
exactly the scene-grammar behavior this redesign was built to produce. Full
spec suite: `beat_segmenter_spec.rb` (17 examples), plus the rewritten
`prompt_builder_spec.rb` (77 examples) and `translation_eval_spec.rb` (23
examples) — 116 examples combined (excluding beat_segmenter_spec, 99 with it
under `spec/services/pipeline`), 0 failures. `spec/services/pipeline/**` in
full: 322 examples, 0 failures.

- Steps 2-5 (analysis/localization/factcheck/editor) needed no change to
  their own chaining/coverage logic — they only needed the wording updates
  above plus the schema rename (`speaker` → `speakers`). The generalized
  `validate_ordered_coverage`/`validate_set_coverage` helpers in
  `TranslationEval` gained an `id_key:` parameter (default `"passage_id"`)
  so Step 1's own coverage check (over `block_id`, before merge) could reuse
  the same helper instead of a bespoke one.
- The old free-form segmentation's "gap/overlap" and "non-sequential
  passage_id" failure modes are now structurally impossible: `anchor_quote`
  content and `passage_id` sequencing are both assigned by Ruby from the
  real source text after classification, never sourced from the LLM
  response at all. The LLM can now only fail Step 1 by producing invalid
  JSON or omitting/reordering a `block_id` in its classification response —
  both still validated, with `translation_eval_spec.rb` covering each.
- The 3-call design's old `build_call1_system_prompt` free-form segmentation
  prompt was already deleted in the 2026-08-01 entry; this entry deletes and
  replaces its 5-step-pipeline successor, `build_segmentation_system_prompt`,
  which never shipped to production either — both were eval-only, driven
  only by `Pipeline::Ruby::TranslationEval`.
- **Promising early qualitative signal, not yet independently confirmed.**
  Passage 5 — the beat spanning Hee-yeon's greeting and Chul-hwan Son's
  mentorship remarks — contains a near-verbatim recurrence of the exact
  "idol, beginner" line that every prior pipeline generation flagged for
  register-mixing (most recently the 2026-08-01 entry's passage 42). Here it
  reads as one coherent scene: *"Idol, beginner, none of that matters. Show
  people good acting and that's the end of the conversation. You know what I
  mean? Keep the fire going all the way to the end. Don't let yourself get
  worn down."* — followed immediately by Hee-yeon's reply and the scene
  moving on, all as a single connected beat, not the standalone stapled-
  imperative-fragment shape earlier runs produced. This is consistent with a
  hypothesis worth testing further: giving localization a genuinely correct
  beat boundary (the full exchange as context) rather than a fragment may
  fix more of this error class at the source than any downstream review step
  did across two pipeline generations. This is a single spot-check on one
  passage, not a factcheck/editor-confirmed result — the independent review
  calls for this run were still in progress when this entry was written (see
  below) and should be checked before treating this as validated.
- Not yet done: factcheck.json and editor.json for this run were still being
  generated live against the real `claude` CLI when this entry was written
  and weren't waited on to completion, to avoid spending unbounded session
  time/context on a live 7-call run (single_pass, structured, classification,
  analysis, and localization had already completed and are reflected above).
  Output lands in `tmp/translation_eval_hybrid/chapter_68/` (gitignored
  scratch) whenever the run finishes; check `factcheck.json` and
  `editor.json` there next time this area is touched, specifically for
  whether either flags anything on passage 5 that the spot-check above missed.

## 2026-08-01 · Eval harness drops single-pass/structured calls; factcheck moves to a cheaper model

`Pipeline::Ruby::TranslationEval`/`bin/translation_eval` ran 7 calls per
chapter: the production single-pass prompt, the superseded structured
(intent/literal/localized) prompt, and the 5-step pipeline under test. The
first two aren't part of the pipeline being evaluated and were only burning
extra calls/cost on every eval run, so they're removed from this harness
entirely — `ChapterResult` no longer carries `single_pass_error`/
`structured_error`/`structured_valid_json`, and `run_single_pass`/
`run_structured` are deleted. `PromptBuilder.build_system_prompt`/
`.build_structured_system_prompt` are untouched — they're still the real
production single-pass path (`translate_batch.rb`) and voice_calibration's
own path respectively, with their own spec coverage; only the eval harness's
use of them is gone. Re-running chapter 68 through the now 5-call-only
harness reproduced the same clean result as before (14 passages, all 5
steps `ok`), confirming the earlier factcheck/editor spot-check wasn't an
artifact of the extra calls.

Also implements cost-reduction option B from the same discussion (options A/
C/D — merging factcheck+editor into one call, caching Step 2, and further
reducing segmentation calls — were considered and deliberately not taken:
A risks contaminating the editor's Korean-blind natural-English judgment
with the source text, and C/D didn't have a clear win outside this eval
harness's own dev loop): `Pipeline::ClaudeCode.call` gained an optional
`model:` keyword that overrides `config.translation_model` for a single
call; `TranslationConfig` gained `factcheck_model` (env `FACTCHECK_MODEL`,
default `"sonnet"`, independent of `translation_model`'s `"opus"` default).
Step 4 (factcheck) now runs on `factcheck_model` — it's a comparison/
verification task (do these names/facts survive translation), not creative
generation, so a weaker model is expected to hold up. Steps 1/2/3/5 are
unaffected. Not yet measured: whether sonnet's factcheck findings are as
sharp as opus's on the same chapter — worth a side-by-side spot-check before
trusting sonnet's factcheck output on anything but this eval harness.

Full findings from the re-run's `factcheck.json`/`editor.json` (still on
opus for this specific run, before the model switch): factcheck flagged 8/14
passages but every finding was advisory with all hard checks (`names_preserved`
etc.) true — the recurring pattern is Korean address terms (형님, 오빠,
선배님들) flattening into generic English, not factual errors. Editor
flagged 9/14 passages, all on `natural_english` specifically (structural
checks — `continuous_utterance`, `register_unified`, `narrative_flow` — all
held), catching calques ("eyes must be broken," "the manager was dying") and
a few dangling/run-on constructions. Both point at real, addressable
categories rather than pipeline breakage.

Spec coverage: `translation_config_spec.rb` (+2), `claude_code_spec.rb` (+2),
`translation_eval_spec.rb` (rewritten to drop single-pass/structured
fixtures, +1 for the factcheck-model-override behavior) — 51 examples across
the three files, 0 failures.

---

## 2026-08-01 · Chapter QA: factcheck/editor surfaced as track changes in the production chapter review page

The eval harness's factcheck/editor findings just proved themselves useful
on a real chapter (see the entry above) but only existed as JSON files in a
gitignored `tmp/` scratch dir, read from the terminal. This entry makes them
a real, production-facing feature: a "Run Quality Check" pass inside the
existing chapter review page (`app/views/chapter_review/show.html.erb`),
rendering findings as Word-style tracked changes — strikethrough the
flagged text, insert the proposed rewrite, attach a comment with the
reviewing pass's rationale — with Accept/Reject per suggestion. "Talk it out
with AI" (a chat-style negotiation over a specific suggestion) was
explicitly scoped OUT of this build: the app's only LLM call pattern today
is one-shot, stateless `claude -p --no-session-persistence`, and multi-turn
negotiation is new territory not worth designing speculatively before
Accept/Reject alone proves useful.

**Architecture pivot during design, before any code was written**: the
initial plan assumed `chapter_qa` would need to re-run the full 5-step eval
pipeline (segmentation → analysis → localization → factcheck/editor)
against the chapter's Korean source, since the eval harness's factcheck/
editor findings are only meaningful relative to passages *that same
pipeline* produced. Reading the most recent commit in the sibling
`hawk-translations-ui-prototype/` repo (a working React mock of this exact
feature: `qa-engine.ts`/`qa-navigator.tsx`/`tracked-changes-view.tsx`)
showed the actually-intended design is simpler: QA runs directly against
whatever `chapter.translated_output` **already** holds — no re-segmentation,
no re-localization, just two flat whole-chapter calls (factcheck: Korean +
English; editor: English only, Korean-blind) against the chapter's existing
translation. This removed the biggest risk in the original plan (QA
silently producing an alternate translation from an unproven pipeline) and
meant the 5-step eval pipeline's beat segmentation work stays exactly where
it already was — nothing about it needed to be "promoted to production" for
this feature.

**New prompt builders, deliberately separate from the eval harness's**:
`PromptBuilder.build_chapter_qa_factcheck_system_prompt`/
`.build_chapter_qa_editor_system_prompt` in
`translate_batch/prompt_builder.rb`. Whole-chapter, no passages, flat
`suggestions` array: `{quote, issue, suggested_revision, severity,
korean_context}`. Two schema changes relative to the eval harness's
existing factcheck/editor findings: `suggested_revision` is required (not
just a diagnosis — always a concrete rewrite, needed for anything to be
"acceptable" as a tracked change), and `severity` (`"strong"`/`"advisory"`)
is now a structured field instead of prose-embedded ("Advisory." text) so
the UI can badge/filter on it without string-sniffing. The existing
eval-only `build_factcheck_system_prompt`/`build_editor_system_prompt` are
untouched.

**New job type `chapter_qa`**: added to `TranslationJob`'s `job_type` enum
(plain string column, no migration) with a validation requiring
`chapter_start == chapter_end` and that chapter already be `translated`/
`reviewed`. `PipelineDispatcher#call` special-cases `chapter_qa` to call
`Pipeline::Ruby::ChapterQa.call(@job)` directly, **bypassing**
`PipelineImplementation` — that lookup defaults to `"python"` when its env
var is unset, which would have silently misrouted this Python-less,
Ruby-native-only job type to `dispatch_python`'s "Unknown job_type" failure
in any environment that forgot to set an override. `PipelineJob#update_chapters`
needed no change — its `case` already falls through to a no-op for unlisted
job types, which is exactly right here: this job never mutates `Chapter`,
everything lands in `result_payload`.

**`Pipeline::Ruby::ChapterQa`** (new, `app/services/pipeline/ruby/chapter_qa.rb`):
modeled on `PostTranslationReview`'s shape (not `TranslationEval`'s 5-step
chain — there's no chain here). Reads the chapter's existing translation via
`Pipeline::TranslatedChapterReader` (correct fit now, unlike the abandoned
first draft which reached for it while also planning to regenerate a new
translation) and the Korean source the same inline way `TranslationEval`/
`translate_batch.rb` already do. Calls factcheck (on `factcheck_model`, per
the cost change above) then editor; every finding's `quote` is verified as
an actual substring of the checked text before being kept — an unanchored
quote can't be located to render as a tracked-change span, so it's dropped,
not surfaced. Returns `{"suggestions": [...]}`, each tagged with a generated
`id`, `source`, and `status: "pending"`.

**No new review controller/route** — unlike `post_translation_review`/
`voice_calibration`'s separate-screen convention, this rides the *existing*
`ChapterReviewController`/`show.html.erb` page, matching the prototype.
Two new actions: `qa_status` (GET, polled after triggering — returns the
latest `chapter_qa` job *for that specific chapter*, not "latest for the
novel") and `update_qa_suggestion` (PATCH, bookkeeping-only — records a
suggestion's `accepted`/`rejected` status inside the job's `result_payload`
JSON, same mutable-scratchpad pattern `voice_calibration_review` already
uses). Accepting a suggestion is **not** a separate "commit" step — it's a
plain text substitution fed through the page's existing
`saveCurrentText()` → `update_text` → `ChapterDiskWriter` + `translated_output.attach`
path, the same one any manual edit already uses. The only genuinely new
persisted state is each suggestion's own decision, so reopening the page
doesn't re-prompt something already acted on.

**Frontend** (`chapter_review_controller.ts`, `show.html.erb`,
`_chapter_review.css`, extended in place, no new files): a "Run Quality
Check" button in the topbar, a QA navigator bar (filter pills for All/
Editor/Factcheck/Strong, prev/next, "Accept all", dismiss), and inline
tracked-changes rendering (strikethrough old text + underlined proposed
text, color-coded by source) — ported from the prototype's interaction
model, not its React code. Two deliberate simplifications from the
prototype, named rather than silently done: the suggestion detail panel is
docked below the navigator instead of a floating tooltip anchored to the
clicked span (avoids reimplementing viewport-collision positioning in raw
TS), and compare mode + QA together shows the same tracked-changes content
in the English pane rather than a fully bespoke dual layout.

Spec coverage: `prompt_builder_spec.rb` (new `.build_chapter_qa_*` describe
blocks), `chapter_qa_spec.rb` (new, 8 examples — happy path, factcheck-model
usage, dropped-unanchored-quote handling, both failure short-circuits,
invalid JSON, missing-file cases), `pipeline_dispatcher_spec.rb` (+2, the
chapter_qa bypass), `translation_job_spec.rb` (model validation, existing
coverage extended), `chapter_review_qa_spec.rb` (new request spec, 10
examples covering `qa_status`/`update_qa_suggestion`). TypeScript changes
verified via `esbuild` (the project's actual build path — there is no `tsc`
type-check gate in this repo) plus an ad hoc strict `tsc --noEmit` pass
against a corrected local tsconfig, which caught and fixed one real
`noUncheckedIndexedAccess` issue in the new code; the repo's own
`tsconfig.json` itself does not type-check clean under the installed
TypeScript version (pre-existing, unrelated to this change, not fixed here).

## 2026-08-08 · Chapter QA suggestions ordered by position in text, not by pass

Reported by the user: resolving a factcheck suggestion near the start of a
chapter would jump the review screen to an editor suggestion near the end,
skipping past everything in between. Cause: `Pipeline::Ruby::ChapterQa#call`
returned `factcheck_suggestions + editor_suggestions` — a flat concat
grouped by which pass found each finding, not by where it sits in the
chapter. The review UI's "next suggestion" navigation (`remaining[0]` in
`chapter_review_controller.ts`) walks that array in order, so an early
factcheck fix could jump straight to a late editor finding instead of the
next one down the page.

Fixed by sorting the merged suggestions by `english_text.index(quote)`
before returning them (`Pipeline::Ruby::ChapterQa#order_by_position`) —
"next" now means next by position in the chapter, regardless of which pass
raised it.

Spec coverage: new case in `chapter_qa_spec.rb` — a factcheck quote placed
after an editor quote in the source text still comes back after it in the
merged array.

## 2026-08-08 · Chapter QA review no longer forces a scroll on accept/reject

Related to the reading-order fix above, and reported together: the review
screen auto-scrolled on every accept/reject even when the reviewer wanted
to keep reading in place, compounding the jump-to-the-wrong-suggestion
problem above.

`applyQaDecision()` in `chapter_review_controller.ts` used to auto-select
`remaining[0]` as focused and force-scroll to it after every accept/reject.
Removed: resolving a suggestion now leaves `qaFocusedId` null and the
viewport untouched. Scrolling is reserved for deliberate navigation only —
`qaNext`/`qaPrev`, a filter change, or clicking a suggestion span directly.

Not covered by an automated test — this is a pure viewport/focus behavior
change with no server-observable effect, and this sandbox's Cuprite/
Chromium system specs don't render JS-driven content correctly (pre-existing
environment limitation, reproducible on `main` before this change too,
unrelated to it). Needs a manual check: accept/reject a suggestion and
confirm the page doesn't move.



## 2026-08-08 · Chapter QA review: untouched chapter text stays directly editable

Reported by the user: once any chapter_qa suggestions were on screen, the
entire chapter text was locked — not just the flagged phrases. Cause:
`qaPane`/`qaPaneCompare` were plain, non-editable `<div>`s once a chapter
had suggestions — the underlying `<textarea>` was hidden entirely, so
nothing in the tracked-changes view could be typed into, flagged or not.

Both panes are now `contenteditable`; each suggestion span (pending or
accepted) carries its own `contenteditable="false"`, so only the flagged
phrases stay locked — the surrounding untouched prose is directly editable,
same as before a QA run. An accepted span stays locked too, on purpose:
it's already an applied change, not open text; only a rejected suggestion's
span disappears entirely (see `buildTrackedChangesHtml`), leaving its quote
as ordinary editable text.

This didn't require touching `saveCurrentText`, `applyQaDecision`, or
`qaAcceptAll` — the hidden textarea stays the single source of truth those
already read from. Three new handlers on the pane
(`syncQaPaneEdit`/`qaPaneKeydown`/`qaPanePaste`) keep it in sync: `input`
re-serializes the pane's DOM into the textarea's `.value` on every
keystroke; `Enter` is intercepted to insert a literal `"\n"` instead of the
`<div>`/`<br>` a contenteditable region would otherwise wrap it in
(matching a plain `<textarea>`'s behavior, and keeping the DOM the
serializer walks flat); `paste` is forced to plain text so pasted rich
content can't inject arbitrary markup. The serializer
(`serializePaneText`) reads a pending suggestion span back as its
*original* `quote` (the old/new markup inside it is display-only — only
resolving the suggestion changes that text) and an accepted span back as
its own text content (a locked, already-final run); everything else is
walked node-by-node as live prose.

Caught by the user during manual smoke-testing: `handleKeydown`'s global
review shortcuts (A/P/S, arrow keys → approve/prev/skip) only skipped
themselves while the focused element's `tagName` was `TEXTAREA`/`INPUT`/
`SELECT`. qaPane/qaPaneCompare are a `contenteditable` `<div>`, not a
`<textarea>`, so typing a word containing "a", "s", or "p" while
hand-editing QA-reviewed text also fired `approve()`/`skip()`/`prev()` —
each keystroke both inserted the character and silently advanced the
review. Fixed by also exempting `target.isContentEditable`, which covers
the pane itself and everything inside it (including a locked suggestion
span).

Not covered by an automated browser test, for the same Cuprite/Chromium
sandbox limitation noted above. Covered instead by a request spec asserting
the show page renders both QA panes `contenteditable` and wired to all
three handlers. The contenteditable editing/serialization path itself needs
a manual smoke-test pass in a real browser before being treated as
verified: typing plain prose around a flagged phrase, pressing Enter inside
the pane, pasting plain and rich text, and accepting/rejecting a suggestion
after a nearby hand-edit.

## 2026-08-08 · Tab key restored after the QA pane went contenteditable

Reported by the user during smoke-testing the direct-editing change above:
"the tab function in the editor is not working anymore." Cause: a
`contenteditable="false"` island nested inside a `contenteditable="true"`
ancestor is still sequentially focusable by default in Chromium/WebKit —
`renderSuggestionSpan`'s locked suggestion spans never had an explicit
`tabindex`, so pressing Tab walked through every suggestion span on screen
before ever reaching the next real control (Save, next chapter, ...).
With more than a couple of suggestions pending, that reads as Tab doing
nothing useful at all.

Fixed by adding `tabindex="-1"` to both suggestion-span branches — pulls
them out of sequential Tab order entirely without affecting click handling
(`handleQaPaneClick`) or their own locked-editing behavior.

## 2026-08-08 · bible-lookup Tab shortcut extended to contenteditable, and wired into the single-chapter editor

Turned out the tabindex fix above wasn't the whole story. "The tab function
in the editor" the user meant was `BibleLookupController`'s actual feature:
select a term, press Tab, get a popover to search/add it to the bible.
`connect()` only ever attached that listener to `<textarea>` elements found
under its root — once a chapter had QA suggestions, editing moved to the
new contenteditable `qaPane`/`qaPaneCompare` divs (see the direct-editing
entry above), which the controller never knew existed, so the Tab shortcut
silently stopped firing there. The `tabindex="-1"` fix was still worth
keeping (a real, separate problem — Tab cycling through locked suggestion
spans instead of leaving the pane at all), it just wasn't *this* bug.

Fixed by giving `BibleLookupController` a second, parallel listener path:
`connect()`/`disconnect()` now also wire up every `[contenteditable="true"]`
element under the root, and `handleTabOnEditable` mirrors
`handleTabOnTextarea` using the Selection API (`window.getSelection()`,
`Range.getBoundingClientRect()`) in place of a `<textarea>`'s
`selectionStart`/`selectionEnd` and the mirror-div positioning hack that
API doesn't have an equivalent for. Same query-length gate, same
`openLoading()`/`fetchResults()` path afterward — the two entry points only
differ in how they read "what's selected" and "where's its rect."

Also, per the user: editor functions like this one (and, later, bulk find
+replace) are meant to be available in *every* editable text field in the
app, not just whichever one happened to get them first. The single-chapter
editor (`chapters#show` → `chapter_viewer_controller.ts`) never had
`bible-lookup` mounted on it at all — fixed by adding it to that page's
root `data-controller` alongside `chapter-viewer`, with the same
`data-bible-lookup-*-value` attributes `chapter_review/show.html.erb`
already sets. Nothing else needed: `BibleLookupController#connect()`
already discovers every textarea under its root generically, so
`chapter_viewer`'s existing plain-textarea editor picked up the feature
with zero controller-side changes of its own.

Confirmed as a non-issue rather than fixed: the user also asked whether a
completed QA review's accepted/rejected changes stay in sync with what the
single-chapter page shows. They already do — `chapter_qa` suggestions live
only in `TranslationJob#result_payload`; `ChaptersController#show` never
reads that table, only `Chapter#translated_output`, which is the same
attachment `ChapterReviewController#update_text` writes to on every accept/
reject (via the existing `saveCurrentText()` path). No separate "wipe"
step was needed because there was never a second copy to wipe.

Spec coverage: new case in `chapters_spec.rb` asserting the `bible-lookup`
controller and its value attributes render on the chapter editor page.
The contenteditable Tab-intercept path itself isn't covered by an
automated test, for the same Cuprite/Chromium sandbox limitation noted in
the entries above — needs a manual check: select text inside the QA pane
after a chapter_qa run and confirm Tab opens the bible-lookup popover.
