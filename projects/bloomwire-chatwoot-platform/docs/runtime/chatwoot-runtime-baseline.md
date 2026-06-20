# Chatwoot Runtime Baseline (Slice 0)

Proof that a runnable Chatwoot Community Edition baseline exists in this repo and
boots locally, so Bloomwire can be built on top of it for fast client testing.

> Status: **COMPLETE — Backend + frontend boot verified. Authenticated login
> verified. Dashboard + inbox + conversation screen verified with real data.**

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
- **Authenticated login: VERIFIED.**
- **Dashboard: VERIFIED** — redirected to `/app/accounts/1/dashboard` after login.
- **Inbox + conversation screen: VERIFIED** — inbox "Acme Support" (web widget)
  and conversation `#1` open with the full message thread rendered.

### Login method used

- A **local-only development admin** was created via Rails console (not a
  production secret; credentials are local-dev only and are **not** committed).
  - Email: `dev-admin@bloomwire.local` (a `.local` dev address).
  - Password: a throwaway local dev value, **not** recorded in this repo.
  - Linked as `administrator` on account `1` ("Acme Inc"), `confirmed_at` set.
- The 2 pre-existing users were **not** modified and their PII was **not**
  inspected (only structural counts were read).
- No application code was changed to enable login — only a dev user row was added
  via console, which is local dev data, not a Bloomwire feature or schema change.

### Authenticated runtime proof

- Post-login URL: `http://127.0.0.1:3000/app/accounts/1/dashboard`.
- Conversation opened: `http://127.0.0.1:3000/app/accounts/1/conversations/1`
  (contact "jane", web-widget inbox, full message thread visible).
- **Console: no errors.**
- **Network: all 25 core API requests returned HTTP 200**, including:
  - `GET /auth/validate_token` (200)
  - `GET /api/v1/accounts/1/` (200)
  - `GET /api/v1/accounts/1/conversations?status=open&assignee_type=me...` (200)
  - `GET /api/v1/accounts/1/conversations/1` (200)
  - `GET /api/v1/accounts/1/conversations/1/messages?before=8` (200)
  - `agents`, `teams`, `labels`, `assignable_agents`, `attachments` (all 200)
  - `POST /api/v1/accounts/1/conversations/1/update_last_seen` (200)

## Console / network issues checked

- Browser console on the login page: **no errors, no warnings**.

## Known limitations

- Docker is not installed on this machine; the baseline was booted **natively**
  (this is fine and maintainable). A Docker path can be added later if needed.
- Node default on bare PATH is v10; you must `nvm use 24.15.0` before booting.
- Login was verified with a **local dev admin** created via console; production
  credential provisioning is a separate concern handled later.
- Only the existing seed dataset (1 account/inbox/conversation under "Acme Inc")
  was available to verify the inbox screen.

## What was NOT implemented (per Slice 0 constraints)

- No Bloomwire SaaS features: no business-profile tables, no roles/permissions
  engine, no audit logs, no usage analytics, no dashboards, no billing/plans,
  no industry-preset implementation, no custom WhatsApp provider logic.
- No Chatwoot Enterprise code used or enabled.
- No duplication of Chatwoot conversation/message/contact data.
- No new source import or source dump.

## Next recommended action

- Slice 0 is **complete**: the Chatwoot CE baseline boots and a full authenticated
  session (dashboard + inbox + conversation) is verified with real data.
- When the branch owner is ready, open a PR from `feature/platform-foundation`
  into `version_1` covering the platform-foundation docs **and** this runtime
  baseline (no PR has been opened yet, per instruction).
- The next product slice remains **"Bloomwire Business Profile + Super Admin
  Business List"** (`docs/product/04-prd-first-slice.md`).

## How to reproduce the authenticated session locally

```bash
# From app/ with Node 24 active (nvm use 24.15.0):
# create/reset a LOCAL dev admin (choose your own throwaway password):
bundle exec rails runner '
  acct = Account.first
  u = User.find_or_initialize_by(email: "dev-admin@bloomwire.local")
  u.name ||= "Bloomwire Dev Admin"
  u.password = ENV.fetch("DEV_PW"); u.password_confirmation = ENV.fetch("DEV_PW")
  u.confirmed_at ||= Time.current; u.save!
  AccountUser.find_or_create_by!(account: acct, user: u){ |x| x.role = :administrator }
'
# then visit http://127.0.0.1:3000/app/login and sign in.
```

> Set `DEV_PW` in your shell only; do not commit it.
