# Bloomwire — Session Log & Agent Continuity Journal

> **New chat / new agent? Start here.** This file is the fast catch-up so context is never lost
> between sessions. It complements (does **not** duplicate) the formal phase history.
>
> **Read order for a fresh session:**
> 1. `AGENTS.md` + `CLAUDE.md` (root) and `app/AGENTS.md` + `app/CLAUDE.md` — operating rules.
> 2. **`docs/bloomwire/PROJECT-CONTEXT.md`** — what the project **is** (managed business messaging SaaS on the Chatwoot engine; WhatsApp-first to market) + durable identity/data/ops rules.
> 3. The **graphify** code graph (`app/graphify-out/graph.json`) — graph-first, auto-refreshed by git hooks.
> 4. **This file** — §A Current State, §B How we work, §C Session journal.
> 5. `docs/bloomwire/implementation-ledger.md` (+ `.html`) and `change-log.md` — full per-phase history.
> 6. `docs/bloomwire/deployment-runbook.md` — deploy/ops detail. `projects/bloomwire-chatwoot-platform/CONTEXT.md` — project contracts.
>
> **Maintenance rule (every agent):** when you finish a slice/phase, **update §A Current State** and
> **prepend a §C journal entry**. Keep §B stable. Don't paste secrets. This is the single living
> "what's happening now" doc.

---

## A. Current State  *(keep this live — update at the end of every session)*

- **`version_1` tip:** `5a8952b`  (PR #99 merged — 17B docs stamp; 17B code merged at `6eac9fa`)
- **Dev deployed SHA:** `9b09f9e`  (public: https://dev.unecast.com · health `/health`) — dev unchanged since the 16C deploy; 17A/17B/17C.1 not deployed.
- **Latest completed / merged:** **PR #98** — Phase **17B** SuperAdmin **"Global WhatsApp Config"** page (read-only), merged into `version_1` (`6eac9faf2cf50bf9910da4ae62179c73cfb96957`). `Bloomwire::GlobalWhatsappConfig` (secret-free) drives the setups `index`: webhook callback URL · Meta App ID (public; **required readiness prerequisite** — missing `WHATSAPP_APP_ID` blocks `platform_ready`) · **App Secret / verify token = Present/Missing only** · router on/off · platform readiness + blockers · "Last webhook received: Not tracked yet" · read-only connected-inbox list. No migration · no store · no secrets · no Meta/WhatsApp · no deploy. Before it: PR #97 (17A removal, `8719de2`); PR #96 (16C docs stamp, `1df6799`).
- **In-flight / open (NOT merged):** **Phase 17C.1** — backend foundation for customer WhatsApp Embedded Signup. **PR #100** (branch `feature/bloomwire-phase-17c1-embedded-signup-foundation`) — **open; review fixes applied.** New capability `canSelfServeManagedWhatsapp` = admin + native WhatsApp restricted + **`managed_whatsapp_onboarding`** feature (master-gated + privacy-dependent) — Review Blocker 1 · new `Bloomwire::WhatsappSetupCreator` (non-secret router-mapping create/update for an existing channel+inbox; idempotent; cross-account-safe; **enforces router handoff-safety when `ready_for_webhook`** — Cloud provider + provider_config pnid match + normalized display, Review Blocker 2; **no secrets/provider_config**) · `WHATSAPP_CONFIGURATION_ID` presence-only readiness prerequisite in `GlobalWhatsappConfig`. **No endpoint/token-exchange/Meta-client/wizard/channel-inbox-creation** (later slices). Full Bloomwire scope **683 ex, 0 fail**.
- **17B secret-storage decision (owner-approved):** no encrypted global-secret store exists (InstallationConfig is plaintext; App Secret + verify token are **ENV/ops-managed**, read via `GlobalConfigService`). PR B is **read-only presence-only** — never displays/saves secret values; **no plaintext storage, no migration, no new store**. Editable secrets = parked (future encrypted `Bloomwire::PlatformConfig` design/ADR).
- **Architecture (ADR-0008):** SuperAdmin WhatsApp = **Global WhatsApp Platform Config only** (17B builds it); account/user creation stays **native**; customers set up WhatsApp via **Account Settings → Inboxes → Add Inbox** (PR C, Embedded Signup first); the internal mapping is created by the wizard, not Ops UI. `Bloomwire::WhatsappSetupRequest` **deprecated/parked** (removed after PR C).
- **Working tree:** clean.
- **Next up (not started — pick with owner):**
  1. **PR 17C.2** — dedicated Bloomwire embedded-signup **endpoint + service** (token exchange + phone info + channel[`source:bloomwire_managed`]+inbox + **app-to-WABA subscription at the GLOBAL callback** + `WhatsappSetupCreator`), Meta calls **stubbed** in specs. Then **17C.3** frontend wizard (`ChannelFactory.vue` + `useBloomwireCapabilities` + new `canSelfServeManagedWhatsapp`) + **17C.4** verify/go-live; then remove the parked `WhatsappSetupRequest`. **Owner decisions still needed:** dedicated endpoint vs native carve-out (recommend dedicated); Meta app config (incl. `WHATSAPP_CONFIGURATION_ID`) + AR encryption keys enabled before real customer tokens are stored.
  2. **Deferred observability:** last-webhook-received telemetry (non-secret Redis/InstallationConfig timestamp) → surface it on the Global Config page (currently "Not tracked yet").
  3. **Prod SMTP parity (important):** populate the **production** global `SMTP_*` env — the same empty-env root cause would block prod activation/reset/invite emails (dev-only fix so far).
  4. Owner-assisted before/after screenshots for 15F.6 + 15F.UI; **Phase 15F.5** (POST preview hardening); **Phase 15F.4** (prod email deliverability, PR #87).

---

## B. How we work  *(stable conventions for this stream)*

**Branch & PR**
- One branch **per phase off `version_1`** → PR **into `version_1`**. **Never push directly** to `version_1` / `main`.
- Open PR, report URL + CI + mergeable, then **stop**. **Do not self-merge.**

**Review → merge → deploy gate**
- Owner runs an external **"GPT-5.5" review**; they relay *"APPROVED at exact SHA <sha>"*.
- **Verify head == approved SHA before merging.** If a rebase changes the head SHA, it needs a **fresh** GPT-5.5 re-review of the new SHA.
- Merge only on explicit owner approval: `gh pr merge <n> --merge --admin` (branch protection requires admin override). Docs-only PRs: same gate.

**Deploy dev** (only after merge, on owner go — see `deployment-runbook.md` for detail)
- `gh workflow run deploy-dev.yml --ref version_1 -f environment=dev -f ref=version_1 -f run_migrations=true -f skip_smoke=false -f prune=false`
- **Never:** production deploy · volume prune · DNS / SMTP-credential / WhatsApp / Meta changes · printing secrets.
- **Post-deploy verify:** `/app/.git_sha` (rails+sidekiq) == version_1 SHA · UI footer SHA matches · health 200 local+public · no pending migrations · rails+sidekiq recreated · postgres/redis preserved · 0×5xx · SMTP unchanged.

**Runtime QA (server-side, password-safe)**
- Need an authenticated owner action via HTTP → create a **temp QA owner** with `rails runner` on the server; write its password to a file **inside the container** (`chmod 600`) and **never print it**; drive with `curl` cookie-jar login. Sanctioned for HTTP QA only.
- **Cleanup after:** delete QA-created templates + delivery logs **by the temp actor's `actor_id`**, then the temp owner + its `Bloomwire::PlatformAdmin` grant (only if another active owner remains). **Preserve** audit rows, the 6 system templates, and the real owner. `shred -u` temp files.
- **Screenshots:** **owner-assisted only.** The MCP/Chrome-DevTools browser has no authenticated owner session (redirects to `/super_admin/sign_in`). **Do NOT** create a throwaway owner or handle passwords/cookies for screenshots.

**Docs governance (mandatory)** — every behavior-changing Bloomwire PR updates `change-log.md` + `implementation-ledger.md` + `.html` in the same PR; after merge, stamp the exact merge SHA + DEV PASS via a docs-only PR. Keep phase numbering consistent.

**Gotchas learned**
- `docker exec -i … rails runner -` **consumes the SSH heredoc stdin** — later commands in the same heredoc won't run. Use `docker exec … rails runner '<script>'` (no `-i`, script as arg) when more commands follow, or put the `-i` form last.
- `curl` treats `[ ]` as URL globbing → use **`curl -g`** for URLs with `compose[...]` params.
- **Two SMTP paths (don't confuse them):** (1) **global Devise/transactional** mail (password reset, 16C activation, platform-admin invite) uses **ENV `SMTP_*`** via `config/initializers/mailer.rb` — if `SMTP_ADDRESS` is blank it silently falls back to `:sendmail` (no MTA on dev → `Errno::EPIPE`, no delivery); (2) **per-account templated** email (15F) uses the **DB-backed `Bloomwire::EmailSetting`** SMTP. Fixing global mail = populate the global `SMTP_*` env (Gmail: port 587 + STARTTLS) and **recreate rails+sidekiq** (recreate, not restart, to reload `.env`). Verify with `ActionMailer::Base.delivery_method` == `:smtp` (booleans/masked; never print values).

**Infra / key paths**
- Dev SSH alias **`contabo-dev`**; containers `app-rails-1`, `app-sidekiq-1`, `app-postgres-1`, `app-redis-1`.
- `bw-*` design system + responsive grid: `app/app/javascript/dashboard/assets/scss/super_admin/index.scss` (vite entry `app/app/javascript/entrypoints/superadmin.js`; bundle at `/vite/assets/superadmin-*.css`).
- Email Settings views: `app/app/views/super_admin/bloomwire_email_settings/` (`_composer.html.erb` owns `#bw-composer`, `#bw-send-result`, `compose[...]`, `send_email` form).
- Shared branded email partial: `app/app/views/bloomwire/email/_branded_email.html.erb`. Service: `app/app/services/bloomwire/send_template_email_service.rb`. Model: `app/app/models/bloomwire/email_template.rb`.
- Specs (from `app/`): `DISABLE_ENTERPRISE=true bundle exec rspec <paths>`; lint `bundle exec rubocop --force-exclusion <files>`. CI = 8 required checks.

**Invariants** — no `users.type` for business roles · no `BusinessOwner` without design · no duplicate chat/message source of truth · no Enterprise dependency · WhatsApp-first · safe DTOs only · never expose secrets.

---

## C. Session journal  *(newest first — prepend new entries)*

### 2026-07-01 — Phase 17C.1 — Backend foundation for customer WhatsApp Embedded Signup (C1 only)
- **Discovery first (17C.0):** confirmed the seams via 3 parallel read-only explorations — native embedded signup
  registers a **per-channel** webhook (conflicts with the Bloomwire **global** router → a later slice needs a
  dedicated endpoint + `source:'bloomwire_managed'`); both tables already exist (**no migration**); router mapping
  contract = `ready_for_webhook` + `phone_number_id` + `inbox_id` + `channel_whatsapp_id` (+ channel alignment).
- **Built (C1, branch `feature/bloomwire-phase-17c1-embedded-signup-foundation` off `version_1` `5a8952b`):**
  1. capability **`canSelfServeManagedWhatsapp`** = `managed_capability(admin, restrict_native_whatsapp_setup?)`
     — new `managed_capability` helper (positive counterpart of `capability`); mutually-exclusive with
     `canManageNativeWhatsappSetup`; agents/OFF → false; existing caps untouched.
  2. **`Bloomwire::WhatsappSetupCreator`** — non-secret router-mapping create/update for an existing channel+inbox
     (`ready_for_webhook`); rejects api_key/provider_config kwargs; idempotent per `channel_whatsapp_id`; fails
     closed (safe symbols) on cross-account / missing pnid / pnid-claimed-by-another-channel; never touches
     `provider_config`; no account/user/inbox/channel creation; no Meta call.
  3. **`WHATSAPP_CONFIGURATION_ID`** → presence-only Embedded-Signup prerequisite in `GlobalWhatsappConfig`
     (named blocker + gates `platform_ready`; shown Present/Missing on the 17B page; value never rendered).
- **Explicitly NOT done (C1 scope):** no dedicated endpoint, token exchange, Meta client, app-to-WABA
  subscription, frontend wizard, channel/inbox creation, manual fallback, native `/whatsapp/authorization`
  carve-out, or `channel.setup_webhooks`.
- **Validation:** capability + creator + readiness specs; **full Bloomwire scope 683 examples, 0 failures (1
  pre-existing pending)**; RuboCop clean. Regression: Global Config read-only; native auth still blocked; router
  + setup #1 unchanged. No deploy · no production · no secrets printed/stored · no Meta/WhatsApp · no migration.
- **Review fixes (PR #100, GPT-5.5 REQUEST_CHANGES):** (1) `canSelfServeManagedWhatsapp` now also requires the
  existing **`managed_whatsapp_onboarding`** feature (`Features.enabled?` — master-gated + privacy-dependent),
  not just the native restriction; (2) `WhatsappSetupCreator` now enforces **router handoff-safety** before saving
  `ready_for_webhook` (`:unsupported_provider` / `:phone_number_id_mismatch` / `:display_phone_number_mismatch`,
  mirroring `WhatsappRouter.channel_aligned_with_payload?`, safe symbols only). Scope unchanged — no C2/C3 leaked.
- **Gotchas:** Ruby 3 `self.call(**)` anonymous forwarding for the ArgumentsForwarding cop; keyword-arg
  constructor needs an inline `Metrics/ParameterLists` disable; data-driven/`same_account?` refactor to keep
  `validate` under the complexity limit; `aggregate_failures` for multi-expectation examples.

### 2026-07-01 — Phase 17B — SuperAdmin "Global WhatsApp Config" page (read-only, PR B)
- **Discovery first (owner-requested):** mapped where the global WhatsApp config/secrets live before building.
  Findings: `GlobalConfigService.load(key)` = InstallationConfig (DB, **plaintext**) → **ENV fallback**;
  `InstallationConfig` has **no `encrypts`** (plaintext jsonb); the **only** encrypted store is per-channel
  `Channel::Whatsapp#provider_config` (ADR-0006). So the global App Secret + verify token are **ENV/ops-managed**;
  `WhatsappRealHopReadiness#config_present?` already exposes them **presence-only**. Meta App ID (`WHATSAPP_APP_ID`)
  is a public identifier (already in `window.chatwootConfig`). **Last-webhook-received is NOT tracked** (webhook
  controller only logs).
- **Owner decision:** **read-only presence** for secrets (no editable secrets, no encrypted store, no migration,
  no plaintext); **defer** last-webhook telemetry ("Not tracked yet"). Editable secrets → future encrypted
  `Bloomwire::PlatformConfig` design/ADR (parked).
- **Built:** `Bloomwire::GlobalWhatsappConfig` (secret-free read-only summary — presence-only for App Secret /
  verify token, callback URL from `PUBLIC_CALLBACK_HOST`, router state, platform readiness + named blockers,
  connected-inbox count) + rebuilt setups `index` view into **Global WhatsApp Config** (platform section +
  read-only connected-inbox list) + nav "WhatsApp › Global Config". Show/readiness/credentials unchanged.
- **Security:** secret VALUES are never read or rendered (proven by a request spec that stubs real-looking secret
  values and asserts the response body excludes them and shows "Present"). No customer provisioning / manual
  mapping reintroduced; no account/user/inbox creation; no `WhatsappSetup` create/edit.
- **Validation:** service spec (6) + setups request spec (incl. presence-only + master-OFF + non-admin) ·
  **full Bloomwire scope 657 examples, 0 failures (1 pre-existing pending)** · RuboCop clean · router regression
  green. No deploy · no production · no Meta/WhatsApp · no secrets printed · no migration.
- **Gotcha:** `RSpec/MultipleExpectations` (max 7) — split the page-render test into render vs no-CRUD.
- **Review fix (PR #98):** `WHATSAPP_APP_ID` is now a **required readiness prerequisite** — a missing App ID is
  named in `blockers` and sets `platform_ready = false` (Embedded Signup needs it). Still presence-aware only;
  App ID value may be shown (public); no secret storage / migration / telemetry added.
- **Merged:** PR #98 → `version_1` `6eac9faf2cf50bf9910da4ae62179c73cfb96957` (approved head `d2ad78a`). No
  deploy · dev remains `9b09f9e` · no migration / table drop / data deletion · no secrets touched · no Meta/WhatsApp.

### 2026-07-01 — Phase 17A — Remove SuperAdmin provisioning + manual setup-mapping UI (architecture pivot, PR A)
- **Owner decision:** kill the SuperAdmin "Provision new WhatsApp customer" flow and the standalone "New setup
  mapping" CRUD (over-engineered; duplicate Chatwoot account/user/inbox). New model (ADR-0008): SuperAdmin
  WhatsApp = **Global config only**; native SuperAdmin → Accounts/Users for account/user creation; customers set
  up WhatsApp from **Account Settings → Inboxes → Add Inbox** (wizard, PR C); the router mapping stays, created
  by the wizard.
- **Removed (branch `feature/bloomwire-phase-17a-remove-provisioning`, off `version_1` `1df6799`):**
  `bloomwire_customer_provisionings` controller/route/view · `Bloomwire::CustomerProvisioningService` ·
  `bloomwire_whatsapp_setups` `new/create/edit/update` (+ new/edit/_form views) → `only: [:index, :show]` · **16C**
  `send_owner_activation` + `Bloomwire::BusinessOwnerActivator` + "Business owner access" card (owner decision
  6a — redundant now; native Devise invite/reset covers it) · nav "New Provision" + index provision/new-mapping/
  edit links · obsolete specs (provisionings, provisioning service, activator, owner-activation request) ·
  refactored boundary/setups/ops-boundary specs off `CustomerProvisioningService`.
- **Kept (router must-stay):** global webhook + `WhatsappRouter`; `Bloomwire::WhatsappSetup` model+table (router
  resolves `ready_for_webhook.where(phone_number_id:)`); encrypted `Channel::Whatsapp#provider_config` +
  `WhatsappCredentialWriter`; readiness; read-only index/show/readiness/credentials (transitional → PR B).
- **Parked (owner decision 6b):** `Bloomwire::WhatsappSetupRequest` deprecated in docs/routes comments — **not
  removed**, table retained; remove later after PR C.
- **Not dropped:** no migration · **no table drops · no data deleted** — setup #1 / account #1 untouched, router
  still resolves it.
- **Validation:** new routing spec (removed routes absent; observability + parked setup-requests routable) · full
  Bloomwire spec scope **647 examples, 0 failures (1 pre-existing pending)** · router + whatsapp_events_job
  regression green · RuboCop clean. No deploy · no production · no Meta/WhatsApp · no secrets · no DB drops.
- **New ADR-0008** created (architecture pivot); ADR-0004 left focused on the router (short pointer added).
- **Gotcha:** with `resources … only: [:index, :show]`, the path `…/new` is absorbed by the `show` `:id` route
  (id=`'new'`), so assert route-removal of `new` via `route_to(…#show, id: 'new')`, not `not_to be_routable`.

### 2026-07-01 — Phase 16C mailer fix → end-to-end `DEV PASS` (docs stamp amended, PR #96)
- **Root cause of the earlier block:** the dev **global `SMTP_*` env was empty** (`SMTP_ADDRESS`/`SMTP_USERNAME`/
  `SMTP_PASSWORD` blank; `SMTP_PORT`=1025), so stock Chatwoot `config/initializers/mailer.rb` correctly fell back
  to `:sendmail` — which had no working MTA → `Errno::EPIPE`. 15F **templated** emails delivered because they use
  the **DB-backed `Bloomwire::EmailSetting`** SMTP path; Devise/16C use the **global ActionMailer (ENV)** path.
- **Fix (operational, dev only):** populated the dev global `SMTP_*` env from the owner's local
  `#PERSONAL EMAIL SETTINGS` block (parsed locally → piped over SSH stdin, **never printed**; `SMTP_PORT` forced to
  587, STARTTLS on) and **recreated rails + sidekiq** → `delivery_method=:smtp` on both (remote `.env` backed up).
  **No `Bloomwire::EmailSetting` change · no code change · no production deploy · no credential values printed.**
- **End-to-end verified (owner-assisted):** owner opened setup #1, clicked **"Send activation email"** (targets
  real admin `User #2` / `sameen@bloomwire.lk`), **received the email, set a password, logged in, reached the
  native Chatwoot inbox**. Server-side (booleans/masked only): reset consumed (`reset_password_token` cleared;
  `reset_password_sent_at` cleared by Devise post-reset — expected); safe audit row (`send_owner_activation`,
  field-names only); **0** new `PlatformAdmin` grants (User #2's `owner` grant is pre-existing/old); roles
  unchanged (`sameen.android@gmail.com` / `User #50` stayed **agent**/sender, never admin); mail delivered via SMTP
  (`mail_performed`≥1, `epipe=0`); no Meta/WhatsApp calls.
- **`sameen.android@gmail.com` = SMTP sender/dev account** (clarified) — NOT a recipient, NOT an administrator.
- **Carry-forward:** apply the same global `SMTP_*` env population to **production** before relying on prod
  activation/reset/invite emails (dev-only fix so far).
- **Guardrails:** docs-only PR #96; no code/deploy/secrets/credentials/Meta/WhatsApp changes; 16C = `DEV PASS`.

### 2026-06-30 — Phase 16C DEV deploy + runtime QA (`PASS-BUT-BLOCKED`) + docs stamp
- Deployed `version_1 @ 9b09f9e` to dev (run `28461253274` via `gh workflow run deploy-dev.yml`): rails+sidekiq
  `/app/.git_sha` match · health 200 local+public · 0×5xx · postgres/redis volumes preserved · no pending
  migrations · `SMTP_*` env present (unchanged). Deploy = **DEV PASS**.
- **16C action runtime-verified** on dev by driving the real Ops page in-process (with a **temp disposable
  platform-admin**, since removed): "Business owner access" card renders · "Send activation email" → success
  flash · the **administrator's** `reset_password_sent_at` updates while the **agent's** does not · **0** new
  accounts/users/account_users/inboxes/conversations/messages · **no** `PlatformAdmin` grant · roles unchanged ·
  safe audit row (field-names only) · **no** token/password/link in UI or audit.
- **Blocked (owner email + login not exercised):** (1) the only existing setup's admin is the **real owner**
  (`account #1` → real `User #2`); `sameen.android@gmail.com` is an **agent**, not a valid target → button **not
  clicked** on the real owner; (2) dev's **global Devise mailer = `sendmail`, no MTA → `Errno::EPIPE`** (email
  does not deliver). Per owner instruction: stopped, **did not retry**, **never used the real owner email**.
- **Cleanup:** earlier temp QA tenant/users/SA removed; the QA **audit row preserved**; the failed QA mail job
  (token-bearing payload) purged from the Sidekiq retry set; **real `account #1` / `User #2` / setup #1 untouched**.
- **Gotcha learned:** dev's **global Devise/transactional mailer uses `sendmail` with no working MTA** (Errno::EPIPE)
  — distinct from the per-account *Email Settings* SMTP. Devise reset tokens also appear in **Sidekiq job-arg logs**
  for all Devise emails (pre-existing platform behavior). **Unblocker:** point the global ActionMailer at SMTP
  (`SMTP_*` env already present), then re-run the owner-assisted login.
- **Guardrails:** no production deploy · no Meta/WhatsApp calls · no SMTP/mail-config or credential changes · no
  roles changed · no real owner touched. Stamp recorded in change-log + ledger (md/html); 16C = `PASS-BUT-BLOCKED`.

### 2026-06-30 — Product framing correction (docs-only)
- Corrected the misleading "WhatsApp-first SaaS product" wording across the durable docs to the canonical
  framing: **Bloomwire is a managed business messaging SaaS platform built additively on the Chatwoot engine;
  WhatsApp is the first go-to-market managed channel / current priority, NOT the permanent product boundary;
  future channels (SMS, Microsoft, Instagram, Telegram, …) may be added later without replacing the Chatwoot
  foundation.** Chatwoot stays the engine + source of truth; WhatsWay/WhatsAway = inspiration/benchmark only.
- Touched: `PROJECT-CONTEXT.md`, `SESSION-LOG.md`, `AGENTS.md`, `CLAUDE.md`, `implementation-ledger.md` + `.html`,
  `change-log.md`. Preserved invariants (Chatwoot Accounts/Users, business owner = AccountUser administrator,
  staff = agent, no `BusinessOwner`, no duplicate conversations/messages/contacts, no overbuilding multi-channel).
- Docs/process-only — no code, no runtime behavior, no deploy.

### 2026-06-30 — Added durable PROJECT-CONTEXT + corrected base framing
- Added `docs/bloomwire/PROJECT-CONTEXT.md` (what the project is + durable identity/data/ops rules) and
  wired it into the read-order (`AGENTS.md` + `CLAUDE.md`, ahead of this file).
- **Framing correction (evidence-based):** a request to record the base as "WhatsWay/WhatsAway-derived,
  not Chatwoot" was checked against the repo and **does not match** — `app/` is `@chatwoot/chatwoot`
  (~15.6k refs; ADR 0001 = "build additively on Chatwoot"); WhatsWay appears only in docs as
  reference-only. Owner-confirmed wording adopted: **Bloomwire = managed business messaging SaaS platform
  built additively on the Chatwoot engine; Chatwoot = code engine + source of truth; WhatsWay/WhatsAway =
  product inspiration/benchmark only (do not copy their code).** _(Product framing refined later the same day —
  see the newer entry above; WhatsApp = first GTM channel, not the permanent boundary.)_
- Docs/process-only — no code, no deploy.

### 2026-06-30 — Established this continuity journal
- Added `docs/bloomwire/SESSION-LOG.md` (this file) as the single living catch-up for new chats, and
  wired it into the always-on rules (`AGENTS.md` "Read context first" + `CLAUDE.md` "Before you do
  anything") so every agent reads it first and updates it at the end of a slice/phase.
- Reason: the product is long-running and new chats are inevitable; the formal ledger/change-log are
  per-phase, so a lightweight "current state + how-we-work + recent sessions" journal was missing.
- Docs/process-only — no code, no deploy.

### 2026-06-30 — Phase 15F.6 (CTA fix) + 15F.UI (UI polish) + DEV-PASS stamps
- **15F.6 Email CTA Button Rendering Fix** — resolved CTA URL now validated absolute (`http(s)://`); scheme-less link (`www.google.com`) blocked pre-SMTP; email-safe table button; preview == delivered. PR **#89 → `53e3e7b`**, deployed + **DEV PASS** (invalid blocks, valid renders purple button, no `[url]label`, text fallback correct, no secrets).
- **15F.UI Email Templates UI Polish & Responsive Upgrade** — responsive 3→2→1 grid, wrapping toolbar, scrollable list w/ active accent, email-client preview frame, prominent accent-topped composer. CSS + view-wrappers only (no behavior change). PR **#90 → `88e0701`** (rebased onto 15F.6, both touch `_composer.html.erb`), deployed + **DEV PASS** (responsive CSS rules verified live at 1440/1280/1024/768; owner-only gate intact).
- **DEV-PASS stamps:** PR **#88** (15F.3), PR **#91 → `6cf23b4`** (15F.UI).
- Full detail (root cause, files, validation, residual risks) is in `implementation-ledger.md` / `change-log.md` — not duplicated here.
- **Carried forward:** owner-assisted screenshots pending; 15F.5 + production 15F.4 are future.

> _Earlier phases (15F, 15F.1–15F.4, 15G.x, etc.) predate this journal — see `implementation-ledger.md` for their history._
