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

---

## Slice: Bloomwire Account Overview (first SaaS UI)

First visible Bloomwire SaaS surface inside the Chatwoot account workspace. The
Chatwoot inbox/conversations UI is unchanged; this only **adds** a page.

- **Route:** `/app/accounts/:accountId/bloomwire/overview` (name
  `bloomwire_overview`).
- **Sidebar:** new top item **"Bloomwire Overview"**.
- **Files:** `dashboard/routes/dashboard/bloomwire/Overview.vue` +
  `bloomwire.routes.js`; menu item in `components-next/sidebar/Sidebar.vue`;
  route wired in `dashboard.routes.js`; i18n in `i18n/locale/en/bloomwire.json`
  (+ `SIDEBAR.BLOOMWIRE_OVERVIEW` in `settings.json`, registered in
  `i18n/locale/en/index.js`).
- **Data (read-only, reuses existing Chatwoot APIs, no new backend):** account
  name from the accounts store; channels from `inboxes/getInboxes`; open & total
  conversations from `GET conversations/meta?status=...`; contacts from
  `GET contacts` meta count. No Chatwoot data is duplicated; no raw
  phone/token/vendor/internal IDs are surfaced.

### Verify
1. Boot services (see above) and sign in as the local dev admin.
2. Visit `/app/accounts/1/bloomwire/overview`.
3. Expect: header + "Runtime connected" badge, 5 summary cards, channel list,
   "How Bloomwire works" block, and an **Open Inbox** button that returns to the
   Chatwoot conversations workspace.

### Runtime proof captured
- Page renders; sidebar item appears; account name + 5 cards + channel list
  render. **Console: no errors.** Core API calls (`conversations/meta` x4,
  `contacts`, account) all **HTTP 200**. **Open Inbox** navigates to
  `/app/accounts/1/dashboard`; the existing conversations page still works.
- `pnpm eslint` on all touched files: **clean**.

---

## Slice: Bloomwire Business Profiles + Super Admin Businesses List

First Bloomwire SaaS **tenant metadata** layer. One Chatwoot `account` = one
Bloomwire business tenant. We add metadata **around** accounts — we do not
duplicate Chatwoot conversation/contact/message data. The existing Super Admin
Console (Accounts, Users, etc.) is unchanged; this only **adds** a page.

- **DB:** `bloomwire_business_profiles` (`account_id` unique FK → `accounts`,
  `industry`, `plan_name`, `status` default `setup_pending`, `onboarding_status`
  default `not_started`). Indexes: unique `account_id`, `status`,
  `onboarding_status`. Migration `20260620150000_create_bloomwire_business_profiles.rb`.
- **Model:** `BloomwireBusinessProfile` — `belongs_to :account`; validates
  `account_id` presence + uniqueness, `status` / `onboarding_status` inclusion;
  scopes `active`, `setup_pending`. `Account has_one :bloomwire_business_profile`.
- **Super Admin (administrate gem):** route
  `resources :bloomwire_business_profiles, only: [:index, :show], path: 'bloomwire/businesses'`;
  controller `super_admin/bloomwire_business_profiles_controller.rb` (list/show
  only, no create/edit/delete); `bloomwire_business_profile_dashboard.rb`; sidebar
  item **"Bloomwire Businesses"** in `super_admin/application/_navigation.html.erb`.
  The `account` column links to the existing Super Admin account page.

### Seed a demo profile (local dev)
```bash
bundle exec rails runner '
  a = Account.find(1)
  p = BloomwireBusinessProfile.find_or_initialize_by(account_id: a.id)
  p.update!(industry: "Retail / E-commerce", plan_name: "Pro",
            status: "active", onboarding_status: "completed")
'
```

### Verify
1. Boot services; sign in to Super Admin at `/super_admin/sign_in`
   (`john@acme.inc` / `Password1!`).
2. Visit `/super_admin/bloomwire/businesses`.
3. Expect: **"Bloomwire Businesses"** sidebar item; table columns Id, Account,
   Industry, Plan Name, Status, Onboarding Status, Created At; a row for the seed
   account linking to its Super Admin account page.

### Runtime proof captured
- `db:migrate` ran clean. Profile created (account "Acme Inc", `active`,
  `completed`). `/super_admin/bloomwire/businesses` renders (**HTTP 200**) with
  nav item, 7 columns, and the row; the `account` cell links to
  `/super_admin/accounts/1`. Show page renders. Existing `/super_admin/accounts`
  (2 rows) and `/super_admin/users` (3 rows) still work. The only console errors
  (`mini-profiler` 500, legacy `packs/js/sdk.js` 404) are **pre-existing** on all
  Super Admin pages, not from this slice.
- Specs: model + request specs **12 examples, 0 failures**.
