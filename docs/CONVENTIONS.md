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
- System specs use Capybara

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

- Hotwire (Turbo + Stimulus) — no React, no Vue, no separate JS framework
- No custom CSS framework decision made yet
- Stimulus controllers in `app/javascript/controllers/`

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
