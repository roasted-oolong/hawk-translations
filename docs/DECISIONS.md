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