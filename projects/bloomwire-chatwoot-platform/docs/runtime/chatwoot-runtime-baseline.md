# Chatwoot Runtime Baseline (Slice 0)

Proof that a runnable Chatwoot Community Edition baseline exists in this repo and
boots locally, so Bloomwire can be built on top of it for fast client testing.

> Status: **Backend + frontend boot verified. Login screen verified. Authenticated
> login pending valid credentials.**

---

## Source strategy chosen

- **Use the existing Chatwoot CE source already in this repo** (`app/`).
- No new source import, no source dump, no drag/drop. The source was already
  present; we boot it as-is.
- **Chatwoot CE version: 4.15.1** (from `app/package.json`). Rails 7.1.5.2.
- Enterprise code is **not** used or enabled.

## Does Chatwoot source exist in this repo?

- **Yes.** Runnable Chatwoot CE source lives under `app/`.
- Markers found: `app/Gemfile`, `app/package.json`, `app/config.ru`,
  `app/Rakefile`, `app/docker-compose.yaml`, `app/.env.example`, and full
  `app/app`, `app/config`, `app/db`, `app/lib`, `app/public`, `app/spec` trees.
- This repo is **not** docs-only.

## Where the runtime lives

- Application root: `app/` (the Chatwoot CE app).
- Local config: `app/.env` (already present and configured; gitignored).

## Environment / prerequisites (observed on this machine)

| Requirement | Required | Found | Status |
|---|---|---|---|
| Ruby | 3.4.4 (`.ruby-version`) | 3.4.4 | OK |
| Bundler | — | 2.6.7 | OK |
| Gems | Gemfile | `bundle check` = satisfied | OK |
| Node | 24.x (`.nvmrc` 24.13.0) | 24.15.0 via nvm | OK |
| pnpm | 10.x | 10.2.0 via corepack | OK |
| PostgreSQL | running | accepting on :5432 | OK |
| Redis | running | PONG (redis 7.0.15) | OK |
| Docker | optional | not installed | N/A (native boot used) |

- Bare `node -v` returns v10 on PATH; the correct Node 24 is provided by **nvm**
  (`nvm use 24.15.0`) and pnpm via `corepack prepare pnpm@10.2.0 --activate`.
- `node_modules/` already installed (~628 MB, pnpm).
- Database already exists and is **schema up to date** (no migration needed).

## Required services

- **PostgreSQL** — running (localhost:5432).
- **Redis** — running (localhost:6379).
- **Rails web (Puma)** — port 3000.
- **Sidekiq worker** — uses `config/sidekiq.yml`, needs Redis.
- **Vite dev server** — port 3036 (serves frontend assets in development).

## Required environment variables / files

- `app/.env` (already present). Non-secret values observed:
  `POSTGRES_HOST=localhost`, `POSTGRES_USERNAME=postgres`,
  `REDIS_URL=redis://localhost:6379`, `RAILS_ENV=development`.
- Secrets in `.env` are not reproduced here.

## Exact commands used

```bash
# 1. Activate the correct toolchain (run from repo root)
export NVM_DIR="$HOME/.nvm"; . "$NVM_DIR/nvm.sh"
nvm use 24.15.0
corepack prepare pnpm@10.2.0 --activate   # provides pnpm 10.2.0

# 2. Confirm prerequisites (run from app/)
bundle check                              # => dependencies satisfied
redis-cli ping                            # => PONG
pg_isready                                # => accepting connections

# 3. Start the three processes (run from app/)
bin/vite dev                              # frontend assets (port 3036)
bin/rails s -p 3000 -b 127.0.0.1         # backend (port 3000)
bundle exec sidekiq -C config/sidekiq.yml # worker
# (equivalent to the three lines in app/Procfile.dev)
```

## App URL used

- `http://127.0.0.1:3000` (login: `http://127.0.0.1:3000/app/login`).
- Vite dev: `http://localhost:3036/vite-dev/`.

## Results / runtime proof

- **Puma** booted: `Listening on http://127.0.0.1:3000` (Rails 7.1.5.2, dev).
- **Sidekiq** booted and processed jobs (e.g. `Inboxes::FetchImapEmailInboxesJob`).
- **Vite** ready: `VITE v6.4.2 ready` on `:3036`.
- `GET /` -> **HTTP 200**; `GET /app/login` -> **HTTP 200** (~8.5 KB, Vite asset
  refs present).
- **Login UI rendered** in a real browser: heading "Login to Chatwoot", Email +
  Password fields, Login button. **Zero console errors/warnings.**
- Database connectivity confirmed via `rails runner`: 2 users, 2 accounts,
  1 inbox, 1 conversation present (counts only; no PII inspected).

## Login / basic UI result

- **Login screen: VERIFIED** (renders, no console errors).
- **Authenticated login: NOT YET VERIFIED** — valid credentials for the 2
  existing users are not known to the agent. Passwords were **not** guessed and
  PII was **not** inspected.
- **Inbox/conversation screen: NOT YET VERIFIED** — gated behind authentication.

## Console / network issues checked

- Browser console on the login page: **no errors, no warnings**.

## Known limitations

- Docker is not installed on this machine; the baseline was booted **natively**
  (this is fine and maintainable). A Docker path can be added later if needed.
- Node default on bare PATH is v10; you must `nvm use 24.15.0` before booting.
- Authenticated/inbox verification is blocked only by missing credentials.

## What was NOT implemented (per Slice 0 constraints)

- No Bloomwire SaaS features: no business-profile tables, no roles/permissions
  engine, no audit logs, no usage analytics, no dashboards, no billing/plans,
  no industry-preset implementation, no custom WhatsApp provider logic.
- No Chatwoot Enterprise code used or enabled.
- No duplication of Chatwoot conversation/message/contact data.
- No new source import or source dump.

## Next recommended action

1. To verify authenticated login + inbox, use a known set of credentials. Fastest
   maintainable options (developer choice, run from `app/` with Node 24 active):
   - Reset a password for an existing user via `bin/rails console`, **or**
   - Create a dev admin via Chatwoot's seed (`bundle exec rails db:seed`) if the
     environment is intended to be seedable.
2. Then load `http://127.0.0.1:3000/app/login`, sign in, and confirm the inbox /
   conversation screen renders (capture a screenshot).
3. After authenticated proof, this Slice 0 baseline is complete and a PR into
   `version_1` can be opened.
