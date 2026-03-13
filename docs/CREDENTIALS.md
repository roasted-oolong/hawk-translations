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
  Credentials are environment-agnostic; this value is not.
- `ANTHROPIC_API_KEY` is currently read directly by the Python pipeline via `os.environ`.
  Moving it to Rails credentials would require the Rails job runner to inject it back
  into the subprocess environment — extra complexity with no current benefit.
  Revisit at Milestone 10 when job invocation is wired up.

## Future keys (not yet required)

```yaml
# Milestone 11 (Deployment) — production-specific credentials file will hold:
#   secret_key_base, database password, Oracle Object Storage keys (when needed)
#   ANTHROPIC_API_KEY may move here once Milestone 10 job invocation is designed
```
