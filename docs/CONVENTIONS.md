# Hawk Translations — Conventions

Project-specific Rails conventions. When in doubt, check here before writing code.

---

## Rails App

- Generated at repo root (not a `rails/` subdirectory)
- App name: `hawk`
- Ruby 3.4.2 (`.ruby-version`), Rails 8.1

### Generation flags used
```
rails new . -n hawk --database=postgresql --skip-test --skip-action-mailbox --skip-action-mailer --skip-action-cable
```
- `--skip-test` — RSpec used instead of Minitest
- `--skip-action-mailbox`, `--skip-action-mailer` — no email in MVP
- `--skip-action-cable` — no WebSockets in MVP (Solid Queue + polling for job status)

---

## Testing

- Framework: RSpec (`rspec-rails`)
- Factory tool: FactoryBot (`factory_bot_rails`)
- Tests written before implementation — no exceptions
- Spec structure mirrors `app/` structure: `spec/models/`, `spec/requests/`, `spec/system/`
- System specs use Capybara + a JavaScript-capable driver (decision at M13 — Playwright via `capybara-playwright-driver` or Selenium/Cuprite)

---

### Development Server

After M13 (jsbundling migration), the development server requires two processes running
simultaneously. Start with:

```bash
foreman start -f Procfile.dev
# or, if overmind is installed:
overmind start -f Procfile.dev
```

`Procfile.dev` defines:
- `web: rails server -p 3000`
- `js: yarn build --watch`

Do not run `rails server` alone after M13 — the JS bundle will not rebuild on changes.

### spec/support/ Auto-loading

`spec/rails_helper.rb` already contains an active glob that auto-loads all files
under `spec/support/**/*.rb`:

```ruby
Rails.root.glob('spec/support/**/*.rb').sort_by(&:to_s).each { |f| require f }
```

Any new support file (e.g. `spec/support/system_spec_helper.rb`) is automatically
required — no manual require needed. `spec/support/omniauth_helpers.rb` already
includes `type: :system` so the `sign_in` helper is available in system specs
without any changes.

### System Spec Strategy (Phase 2)

System specs are written for every UI milestone to catch regressions during incremental
build-out. The goal is a reliable suite that can be run before each deploy.

Coverage target per milestone:
- M13: smoke test — app boots, login page renders, OAuth flow completes
- M14: login flow, nav renders, sign-out
- M15: dashboard loads, novel index renders, novel show renders
- M16: chapter list, file upload form, job trigger form, job status display
- M17: bible index/show per category, search bar interaction
- M18: novel create/edit form, empty state rendering

JS driver setup is a dedicated step within M13 before any view specs are written.
Playwright is preferred over Selenium for reliability and speed; Cuprite (CDP-based)
is a lighter alternative. Decision recorded in DECISIONS.md at M13.

---

## Database

- PostgreSQL
- pgvector extension enabled from Milestone 5 (even though used in Milestone 12)
- All foreign keys explicit in migrations
- All indexes explicit in migrations (don't rely on Rails defaults)
- Enums stored as strings, not integers — easier to debug, safer to extend

---

## Models

- Enums defined with `enum :column, { value: "value" }` (string-backed)
- Scopes preferred over class methods for query logic
- No raw SQL in models — use Arel or ActiveRecord query interface
- Validations present on every model with constrained columns

---

## Frontend

See docs/UI.md for the full frontend specification. Summary:

- Hotwire (Turbo + Stimulus) — no React, no Vue, no separate JS framework
- TypeScript via `jsbundling-rails` + esbuild — replaces importmaps
- All Stimulus controllers in `app/javascript/controllers/`, named `*_controller.ts`
- Hand-rolled CSS — no Tailwind, no Bootstrap
- CSS custom properties for all design tokens — defined in `app/assets/stylesheets/application.css`
- Reusable view components (partials) in `app/views/components/` — registered via `prepend_view_path` in `ApplicationController`
- `yarn build --watch` + `rails server` run together via Foreman (`Procfile.dev`)

---

## File Storage

- Active Storage, local disk in development and initial production
- Oracle Object Storage (S3-compatible) swap is a config change only — no app code changes
- File paths structured for multi-tenant isolation: `org_id/novel_id/chapter_id/filename`

---

## Background Jobs

- Solid Queue (Rails 8 built-in) — no Redis
- Job classes in `app/jobs/`
- Python pipeline invoked via `Open3.capture3` — not `system()` or backticks
- Never shell out with user-supplied strings unescaped

---

## Secrets & Environment

- All secrets in Rails encrypted credentials (`rails credentials:edit`)
- Environment-specific credentials: `config/credentials/production.yml.enc`
- `HAWK_PROJECT_ROOT` env var points to repo root — used by `config.py`
- No `.env` files committed; `.env` is gitignored

---

## Naming

- Bible tables: `bible_characters`, `bible_locations`, `bible_terminology`, `bible_cultural_phrases`, `bible_story_entries`
- Job model: `TranslationJob` (table: `translation_jobs`) — avoids collision with ActiveJob base class naming
- Permission levels: `viewer`, `editor`, `translator`, `admin` (string enum on `NovelTeamAssignment`)
- Chapter status: `untranslated`, `translated`, `reviewed` (string enum on `Chapter`)

---

## Deployment

- Kamal (Rails 8 built-in) run from local machine
- Target: Oracle Cloud AMD E2 micro (x86_64, Ubuntu 22.04) — ARM64 migration path documented in DECISIONS.md
- Dockerfile targets `linux/amd64`
- kamal-proxy handles SSL directly on ports 80 and 443 — Nginx is not used in production
- Cloudflare proxies all traffic; SSL/TLS mode: Full (strict)
- kamal network gateway (`172.18.0.1`) used for container→PostgreSQL connections
- iptables rule `172.16.0.0/12 ACCEPT` covers all Docker bridge networks permanently

### Dockerfile — Node.js layer (added at M13)

The jsbundling + esbuild pipeline requires Node.js in the Docker image.
Added at M13 as a layer before the Ruby/Rails layer:

- Use the official `nodesource` apt repository or the Dockerfile `FROM` base image's
  package manager — do not use nvm (not suitable for Docker)
- Node version: LTS (20.x or 22.x — decision at M13, record in DECISIONS.md)
- `yarn` installed via `npm install -g yarn` after Node install
- `yarn build` run during image build to compile assets before container starts
- `.dockerignore` already excludes `node_modules` — verify at M13

---

## Version Control

### Commit Convention

This project follows the [Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/)
specification. Every commit message must have the form:

```
<type>(<scope>): <description>

[optional body]

[optional footer]
```

**Types**

| Type       | When to use                                                          |
|------------|----------------------------------------------------------------------|
| `feat`     | A new feature or user-visible behaviour                              |
| `fix`      | A bug fix                                                            |
| `test`     | Adding or correcting tests — no production code changes              |
| `refactor` | Code change that neither fixes a bug nor adds a feature              |
| `style`    | CSS / visual changes only — no logic changes                         |
| `chore`    | Tooling, config, dependencies, CI — nothing the app ships            |
| `docs`     | Documentation only (`/docs`, README, inline comments)                |
| `db`       | Migrations and schema changes                                        |

**Scopes** (optional but encouraged)

Use the area of the app being changed, e.g.: `novels`, `chapters`, `bible`,
`jobs`, `auth`, `dashboard`, `uploads`, `sidebar`, `tabs`, `api`.

**Examples**

```
feat(chapters): add chapter status badge to chapter list row
fix(jobs): prevent duplicate job submission on double-click
test(novels): add request specs for NovelsController#create
refactor(auth): extract ProvisionWorkspace call into SessionsController concern
style(sidebar): adjust user widget avatar spacing for narrow viewports
chore: add esbuild watch script to Procfile.dev
docs: document Conventional Commits convention in CONVENTIONS.md
db: add pgvector extension to initial migration
```

---

### Atomic Commits

Each commit must represent **one logical change**. That means:

- A migration and its corresponding model change belong together in one commit.
- A new feature and its tests belong together in one commit — or tests first in
  a `test:` commit if you are working TDD and want a visible red→green record.
- A refactor must not be bundled with a behaviour change. Split them.
- CSS changes that are purely cosmetic belong in their own `style:` commit,
  separate from Stimulus or template logic changes.

**Signs a commit needs to be split:**

- The description requires "and" to be accurate.
- The diff touches unrelated files (e.g. a migration + a CSS tweak).
- The commit would be hard to revert without affecting unrelated work.

---

### Commit Body

The body is optional. Use it when the *why* is not obvious from the description
alone — e.g. a non-obvious architectural decision, a constraint from an external
API, or why a simpler approach was rejected. Keep the description line ≤ 72
characters. The body is free-form prose.

---

### CHANGELOG

`docs/CHANGELOG.md` is updated **per milestone**, not per commit. It summarises
what shipped at the milestone level for human readers. Commit messages are the
authoritative per-change record.
