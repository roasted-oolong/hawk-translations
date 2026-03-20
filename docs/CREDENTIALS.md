# Hawk Translations — Credentials

Credentials are stored in Rails encrypted credentials.
Never commit plaintext secrets. Never hardcode keys.

## How to edit

```bash
bin/rails credentials:edit
# or for production-specific:
bin/rails credentials:edit --environment production
```

## Required keys

### google (Milestone 4 — Authentication)

```yaml
google:
  client_id: <from Google Cloud Console OAuth 2.0 credentials>
  client_secret: <from Google Cloud Console OAuth 2.0 credentials>
```

**How to obtain:**
1. Go to https://console.cloud.google.com
2. Create or select a project
3. APIs & Services → Credentials → Create Credentials → OAuth 2.0 Client ID
4. Application type: Web application
5. Authorised redirect URIs:
   - Development: `http://localhost:3000/auth/google_oauth2/callback`
   - Production: `https://<your-domain>/auth/google_oauth2/callback`
6. Copy Client ID and Client Secret into credentials

## Environment variables (not in credentials)

Some values live in `.env` rather than encrypted credentials. `.env` is gitignored
and never committed.

```bash
HAWK_PROJECT_ROOT=/home/jenna/hawk-translations   # filesystem path — changes per environment
ANTHROPIC_API_KEY=sk-ant-...                      # read by Python pipeline directly
```

**Why not in credentials?**
- `HAWK_PROJECT_ROOT` is a filesystem path that differs between dev and production.
  In production it is set as a clear env var in `config/deploy.yml` (`/rails` — the
  container WORKDIR). In development it stays in `.env`.
- `ANTHROPIC_API_KEY` is injected into the container as a secret env var via
  `config/deploy.yml` / `.kamal/secrets`, so the Python pipeline can read it via
  `os.environ["ANTHROPIC_API_KEY"]` without any changes to the pipeline code.

## Production secrets (Milestone 11 — not in credentials, managed via .kamal/secrets)

Production secrets are injected at deploy time by Kamal from `~/.config/hawk/` files
on the local machine. They are never stored in credentials or committed to git.

| Secret | Source file | Used by |
|--------|-------------|---------|
| `RAILS_MASTER_KEY` | `config/master.key` | Rails — decrypts credentials |
| `HAWK_DATABASE_PASSWORD` | `~/.config/hawk/db_password` | PostgreSQL hawk user |
| `ANTHROPIC_API_KEY` | `~/.config/hawk/anthropic_api_key` | Python pipeline subprocesses |
| `GITHUB_TOKEN` | `~/.config/hawk/github_token` | Kamal — push/pull ghcr.io image |

## Production credentials file

Run `bin/rails credentials:edit --environment production` to set:

```yaml
secret_key_base: <run: bin/rails secret>

google:
  client_id: <same client ID as development, or a separate production OAuth app>
  client_secret: <matching secret>
```

The production credentials file is encrypted with `config/credentials/production.key`
(generated automatically on first edit). Add the production callback URL to your
Google Cloud OAuth app: `https://<your-domain>/auth/google_oauth2/callback`.
