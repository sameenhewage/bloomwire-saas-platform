<!--
  Bloomwire Implementation Ledger — DOCS ONLY.
  This file documents what Bloomwire changed on top of the OSS base. It has no runtime behavior.
  Do not treat anything here as configuration or executable code.
-->

# Bloomwire Implementation Ledger

> **Docs only — no runtime behavior.** This is an internal implementation reference / change log.
> It changes no application code, no database migrations, and no configuration.

- **Generated:** 2026-06-29
- **Stable baseline SHA:** `4084a23eb4a83b1ee41e298811a91d52d6fb6044` (after Phase 15C)
- **Branch:** `version_1`

---

## 1. Ownership statement

- **Bloomwire** is a **managed business messaging SaaS platform** built additively on the **Chatwoot engine**
  (the OSS base under `app/`, i.e. `@chatwoot/chatwoot`). **WhatsApp is the first go-to-market managed channel /
  current implementation priority — not the permanent product boundary;** future channels may be added later
  without replacing the Chatwoot foundation. **WhatsWay/WhatsAway are product inspiration/benchmark only, not the
  codebase base.**
- **Bloomwire customizations are Bloomwire-owned.** They live in clearly attributed code (controllers,
  models, services, views, and feature toggles) and are layered on top of the OSS code path.
- **Chatwoot Enterprise code/features are not used.** Bloomwire runs with `DISABLE_ENTERPRISE=true`.
- **Current channel scope is WhatsApp only.** Other channels (Instagram, Messenger, Telegram, Signal, …)
  may be added later, but the current implementation is intentionally **WhatsApp-first** and must not be
  over-built for multi-channel now.
- Bloomwire-specific behavior is gated behind **Bloomwire Mode** (`BLOOMWIRE_MODE_ENABLED`). With Mode
  **OFF**, behavior is intended to stay **stock-compatible** with the OSS base.

---

## 2. Current stable baseline

- **Stable SHA after Phase 15C:** `4084a23eb4a83b1ee41e298811a91d52d6fb6044`
- This baseline includes all completed permission/security hardening through **Phase 15C**, plus the
  **Phase 15D** Assigned-Agent RCA (which produced **no code change** — see §3).
- **Phase 16 (customer onboarding) should start from this stable reference.**
- Deployed dev toggles at baseline: `BLOOMWIRE_MODE_ENABLED=ON`, `BLOOMWIRE_PRIVACY_HARDENING=ON`,
  `BLOOMWIRE_GLOBAL_WEBHOOK_ROUTER=ON`.

### Phase → PR → status quick map

| Phase | What | PR | Status |
|---|---|---|---|
| 13B | WhatsApp production hardening | (13x series) | Completed |
| 13C | Live Meta certification (dev) | (13x series) | Completed (templates parked) |
| 13D | Webhook PII log hardening | (13x series) | Completed |
| 13E | Template / out-of-window parking | (13x series) | Parked (awaiting approved WABA template) |
| 14 (S2) | Ops credential capture | #68 | Completed |
| 14 (S3) | Customer provisioning orchestration | #69 | Completed |
| 15A | Platform-admin boundary for `/super_admin` | #71 | Completed |
| 15A.1 | Owner-only Platform Admin management | #72 | Completed |
| 15A.2 | Users vs Platform Admin flow consistency | #73 | Completed |
| 15B | Business account-user flow clarity | #75 | Completed |
| 15C | SuperAdmin impersonation token hardening | #76 | Completed (Issue #74 closed) |
| 15D | Assigned Agent RCA | — (RCA only) | Completed — not a bug (no code change) |
| 15E | This implementation ledger | #77 | Docs only |
| 15E.1 | Documentation Governance guardrail | #77 | Docs only |
| 15F | Owner-only Email Settings (DB SMTP + templates) | #78 | DEV PASS (encryption parked) |
| 15F.1 | Send-from-Template composer (owner-only) | _pending_ | Implemented |
| 15F.2 | Email Template UX Completion (dynamic vars + preview==send + validation + logs subject) | #84 | 100% DEV PASS |
| 15F.3 | Email Send Feedback UX Polish (composer-local result banner + composer anchor + double-send guard) | #86 | DEV PASS |
| 15F.4 | Email Deliverability + Domain Authentication (why mail lands in junk + production DNS/provider plan) | _pending_ | Investigation (report-only) |
| 15F.6 | Email CTA Button Rendering Fix (validate resolved CTA URL is absolute + email-safe button) | #89 | DEV PASS |
| 15F.UI | Email Templates UI Polish & Responsive Upgrade (3→2→1 grid, toolbar, preview frame, prominent composer) | #90 | DEV PASS |
| 15G | CI/CD foundation (PR CI + manual Dev/Staging deploy) | _pending_ | Implemented (infra/docs only) |
| 15G.1 | Fix false-success dev deploy (stdin-consumed deploy script) | _pending_ | Fixed (infra/docs only) |
| 15G.2 | Auth Integrity Hardening (admin form can't change password/auth) | _pending_ | Hardened · DEV PASS |
| 15G.3 | Auth Go-Live Guardrails (admin-edit audit + auth smoke + runbook) | _pending_ | Hardened · DEV PASS |
| 16C | Business-owner activation (Ops "send activation email" → Devise set-password to account admins) | #95 | DEV PASS (end-to-end) · **superseded/removed by 17A** |
| 17A | Remove SuperAdmin customer-provisioning + manual setup-mapping UI + 16C activation (architecture pivot; keep router/mapping) | #97 | Merged (`8719de2`) |
| 17B | SuperAdmin "Global WhatsApp Config" page — read-only platform config (webhook/App-ID/secret-presence/router/readiness) + connected-inbox list | #98 | Merged (`6eac9fa`) |
| 17C.1 | Backend foundation for customer WhatsApp Embedded Signup (capability `canSelfServeManagedWhatsapp` + `WhatsappSetupCreator` + `WHATSAPP_CONFIGURATION_ID` readiness) | #100 | Merged (`ac79a88`) |

> **Dev QA Sign-off (2026-06-30, owner-confirmed)** — dev `version_1` @ `ea3487b`: Auth 15G.2/15G.3 = **DEV
> PASS**, Email Settings/SMTP = **DEV PASS**, Email Templates (15F.2) = **100% DEV PASS**. Owner confirmed both
> dev QA emails received. No production deploy · audit rows not purged · no WhatsApp/Meta/provider creds touched.
> **Phase 16 is READY to start.** Roadmap (authoritative): **15F.3** = Email Send Feedback UX Polish (PR #86,
> pending review/deploy); **15F.4** = Email Deliverability + Domain Authentication (PR #87, report-only/docs-only);
> **15F.5** = POST-based composer preview / query-string hardening (future); **15G.4** = optional auth-audit polish
> (future). The POST-based preview hardening is **15F.5**, not 15F.3.

---

## 3. Phase-by-phase implementation log

### Phase 13B — WhatsApp production hardening — `Completed`
- Encrypt the WhatsApp **provider config** at rest **when Active Record encryption keys are configured**
  (no plaintext-token-at-rest is the target; behavior degrades safely if keys are absent).
- Outbound **retry** behavior for transient send failures.
- **Configurable Graph API version** (no hard-coded Meta API version).
- **No Enterprise dependency** introduced.

### Phase 13C — Live Meta certification (dev) — `Completed`
- Validated on the live **dev** environment.
- **Webhook callback verified** (Meta → Bloomwire).
- **Inbound/outbound WhatsApp session chat verified.**
- **Message status lifecycle verified** (sent / delivered / read).
- **Templates parked** — no approved WABA template was available to certify the template path.

### Phase 13D — Webhook PII log hardening — `Completed`
- Disabled risky **job-args logging** for WhatsApp-related jobs.
- Deep-**filtered webhook `entry` payloads** from request-parameter logs.
- Prevents **phone numbers / profile names / `wa_id` / secrets** from leaking into logs.
- Implemented via `config.filter_parameters` (e.g. `:entry`, `:provider_config`, a broad `token` regex) and
  Sidekiq/log-level adjustments. Logging-only: the processing path still reads the real params.

### Phase 13E — Template / out-of-window parking — `Parked`
- **Template send is parked** until an **approved WABA template** exists.
- Recorded fact: **session chat works**; the **template path waits on Meta/WABA readiness**.

### Phase 14 — Customer provisioning foundation — `Completed`
- **Onboarding runbook** authored.
- **Secure Ops credential capture** (PR #68) — provider credentials handled under a filtered
  `provider_config` key; never echoed.
- **Customer provisioning orchestration** (`Bloomwire::CustomerProvisioningService`, PR #69):
  creates the **tenant/account → owner → agents → WhatsApp channel → inbox**, and **attaches the
  provisioned agents to the WhatsApp inbox** (`attach_agents_to_inbox` → `InboxMember.create!`).
- **No Meta live registration** unless explicitly authorized.

### Phase 15A — Platform-admin boundary — `Completed` (PR #71)
- `/super_admin` is the **Bloomwire internal / platform console**.
- `users.type = 'SuperAdmin'` is a **Rails/Devise STI identity only** — it is **not** a business role.
- Platform access is controlled by the **`bloomwire_platform_admins`** table (ADR-0007).
- **Only approved platform admins** can access `/super_admin` (when Bloomwire Mode is ON).
- **Customer/business users are blocked** from `/super_admin` (Devise `:super_admin` STI scope).

### Phase 15A.1 — Owner-only Platform Admin management — `Completed` (PR #72)
- Added the **Platform Admins** page (`/super_admin/bloomwire_platform_admins`).
- Platform roles: **`owner` / `admin` / `support`**.
- The **owner** can **create / grant / revoke (soft) / reactivate** platform admins.
- **Last-owner guard**: the only active owner cannot be demoted or revoked (`LastOwnerError`).
- **No accidental promotion** of normal users (create-by-email refuses existing business/customer users;
  owner bootstrap requires an existing dedicated SuperAdmin).

### Phase 15A.2 — Users vs Platform Admin flow consistency — `Completed` (PR #73)
- The Administrate **Users** page is preserved for **normal/customer/business user** creation.
- In Bloomwire Mode, the raw **`Type`** field is **hidden on forms and stripped server-side**.
- The Users table shows a computed **Platform Access** column (Owner/Admin/Support/Revoked/Not
  approved/No platform access) instead of the raw `Type`.
- The **Platform Admins** flow is the **only** place platform roles are managed.
- Business users are **normal users with account membership**, never `users.type`.

### Phase 15B — Business account-user flow clarity — `Completed` (PR #75)
- `account_users.role = administrator` is **displayed as "Business Admin"**.
- `account_users.role = agent` is **displayed as "Agent"**.
- **No `BusinessOwner` role added.**
- **DB values remain `administrator` / `agent`** (display/label/UX clarity only — not a model rewrite).
- Customer/business **account access does not grant platform access**.
- Copy moved to i18n (`bloomwire.account_access.*`); the role `<select>` uses a Mode-aware labeled
  collection that submits the unchanged DB enum keys.

### Phase 15C — SuperAdmin impersonation token hardening — `Completed` (PR #76, Issue #74 `closed`)
- **Issue #74**: the old SuperAdmin user-show page rendered an **`sso_auth_token` in the link href**.
- **PR #76** changed impersonation to **POST** (`POST /super_admin/users/:id/impersonate`):
  - the token is **generated only on click/request**, server-side;
  - **no token in the rendered page HTML/href**;
  - the **final browser URL has no token** (the SPA lands on the dashboard);
  - the handoff uses `head` + `Location` (not `redirect_to`) so the token is **not written to the Rails
    "Redirected to …" log line**; it is also already `[FILTERED]` from request-param logs;
  - the token remains **short-lived (5 min) and single-use** (invalidated on consumption).
- **Issue #74 closed as completed.**
- **Residual:** the intermediate **`/app/login?…&sso_auth_token=…` handoff URL** still exists briefly in
  the existing SSO flow (and is sent to the browser/nginx access log for that one request). Full removal
  would require a separate **frontend/auth handoff redesign** (e.g. fragment/cookie handoff). Mitigated by
  short-lived + single-use + on-click-only generation.

### Phase 15D — Assigned Agent RCA — `Completed (not a bug)` — RCA only, no code change
- **Symptom:** in a conversation, the **Assigned Agent** dropdown showed only the account administrator
  (Sameen); an account **Agent** (Lakmal) did not appear, even though Settings → Agents listed him.
- **RCA classification: A (not a bug) + B (setup issue).** This is **stock Chatwoot behavior**.
- **Rule:** assignable agents = **inbox members + account administrators**
  (`Api::V1::Accounts::AssignableAgentsController`, `Inbox#assignable_agents`).
- **Settings → Agents** uses the **account-wide** `AgentsController#index` (shows all account users).
- The **conversation Assigned Agent** dropdown uses the **inbox-scoped** assignable-agents endpoint
  (frontend `useAgentsList` → `inboxAssignableAgents` store → `assignable_agents` API).
- **Lakmal** was an account Agent but **not an inbox member** of the WhatsApp inbox, so he was excluded.
  **Sameen** appeared because he is an **account administrator** (admins are always included).
- **Not caused by Bloomwire Mode** (no Bloomwire/Mode code in the path) and **not caused by 15A/15B**
  permission changes (no enterprise/Bloomwire override of this path).
- **Correct no-code fix:** add the agent as an **inbox collaborator/member** (Settings → Inboxes →
  *inbox* → Collaborators). **Future onboarding must ensure selected agents are attached to the WhatsApp
  inbox** — note the provisioning service already does this (`attach_agents_to_inbox`); manually-created
  inboxes can miss it.

### Phase 15E — Implementation ledger — `Docs only` — PR #77
- Added this ledger (`docs/bloomwire/implementation-ledger.md` + `.html`). No app code, no migrations.

### Phase 15E.1 — Documentation Governance guardrail — `Docs only` — PR #77
- Added the **Bloomwire Documentation Governance** rule to `AGENTS.md` + `CLAUDE.md`, this
  **Documentation Governance** section (§10) + Definition of Done, and the Bloomwire change log
  (`docs/bloomwire/change-log.md`). Ensures every future Bloomwire-owned change stays documented.

### Phase 15F — Owner-only Email Settings — `Implemented (encryption parked)` — PR #78
- Owner-only **`Bloomwire → Email Settings`** console (Administrate shell) with tabs **Overview /
  Configuration / Email Templates / Test Email / Email Logs**, 4 status cards, owner-only badge.
- **DB-backed SMTP config** (`bloomwire_email_settings`) is the source of truth; ENV `SMTP_*` only seed
  bootstrap defaults. Password is **write-only** in the UI (masked, replace-secret, never rendered/logged).
- **DB-backed templates** (`bloomwire_email_templates`): 6 seeded system templates with `{{variable}}`
  preview (sample data) + create / edit / duplicate / deactivate / reactivate. Variables:
  `{{recipient_name}}`, `{{business_name}}`, `{{invitation_link}}`, `{{reset_link}}`, `{{expiry_time}}`,
  `{{support_email}}`.
- **Test Email**: preflight-validated — real send via the DB SMTP settings when complete; honest
  "blocked — missing config" otherwise. **Never fakes success.** Tests never send real mail.
- **Access**: owner-only (`Bloomwire::PlatformAdmin` active owners; `Bloomwire::RequiresPlatformOwner`
  concern). Platform admin/support + customer/business users blocked.
- **Review hardening (PR #78)**: the Overview copy is **honest** (no claim that password resets/transactional
  emails use the DB SMTP — Devise unchanged, transactional sending parked); **system-template keys are
  immutable** (`:key` not permitted on update + model validation; auto-generated on create); **CTA URLs** are
  restricted to `http(s)`/`{{placeholder}}`.
- **SECURITY DEBT (documented)**: `smtp_password` is stored **plaintext** (Active Record encryption not
  configured). Encryption-at-rest is a **parked follow-up** (see §8).
- **Not changed**: no WhatsApp/Meta/provider credentials, no Enterprise code, no `BusinessOwner`, no
  `users.type` for business roles, no chat/message tables. Devise/password-reset mailers untouched (they
  use the global ENV SMTP config; wiring them to the DB-backed config is parked).

### Phase 15F.1 — Send-from-Template composer (+ HTML email + Email Logs) — `Implemented` — PR _pending_
- **Discovery first:** the prior "Send Test Email" button on the Email Templates tab only **linked** to the
  Test Email tab (a fixed sample/test send). There was **no** way to fill a template's variables and send the
  rendered template — so the composer was implemented (no behavior was silently changed).
- Owner-only **"Send from Template"** composer on the Email Templates tab: 9 fields — recipient, the 6
  `{{variables}}`, plus button label/link — with an **"Update preview"** round-trip (server-rendered final
  preview using the entered values) and a **"Send Email"** action.
- **Delivered email matches the preview (review fix):** a single shared partial
  `app/views/bloomwire/email/_branded_email.html.erb` is rendered by BOTH the composer preview and the mailer,
  so they cannot drift. `Bloomwire::EmailTestMailer#template_email` sends **multipart HTML + plain-text** — the
  HTML carries branding + CTA **button** + footer; the text part is a fallback with the same values.
  `{{placeholders}}` are interpolated before send; no raw `{{...}}` remains for supplied values.
- **Per-send Email Logs (review fix):** new Bloomwire-owned table `bloomwire_email_delivery_logs` +
  `Bloomwire::EmailDeliveryLog`. Every template send writes one row (**success / failed / blocked**) with
  recipient, template, status, timestamp, actor, and a **sanitized** error. The Email Logs tab shows these rows
  (plus the latest test-email result). The table **never** stores SMTP credentials.
- **Ownership:** `Bloomwire::SendTemplateEmailService` owns the real send (preflight + enabled-gate + logging);
  `SendTestEmailService` stays Test-Email-only. Preflight + secret-filtering centralized on
  `Bloomwire::EmailSetting` (`block_reason`, `sanitize_secret`).
- **Honest + enabled-gated:** blocks (and records a `blocked` log) when the recipient is blank, SMTP is
  incomplete, **or outbound email is disabled**; the Send button is disabled until SMTP is ready. **Never fakes
  success.** The SMTP password is never rendered, logged, or stored.
- **Access:** owner-only via the existing `Bloomwire::RequiresPlatformOwner` gate on both controllers (send + logs).
- **Tests:** **71 examples, 0 failures** for the Bloomwire email suite — owner can send (→ success log),
  non-owner blocked (send + logs), missing/incomplete/disabled → blocked log, failed send → failed log with
  sanitized error, HTML+text contain replaced values + CTA with no raw `{{...}}`, Email Logs renders rows,
  password never in logs/response/HTML, final-preview round-trip uses the shared shell. RuboCop clean.
- **Not changed:** no WhatsApp/Meta/provider credentials or code, no Enterprise code, no `BusinessOwner`, no
  `users.type` for business roles, no chat/message tables, Devise/password-reset mailers untouched, no new
  dependencies.
- **Migration:** `20260629000003_create_bloomwire_email_delivery_logs` (additive; new Bloomwire-owned table).
- **Residual:** SMTP password remains plaintext-at-rest (Phase 15F debt, §8); Office365 SMTP AUTH may still be
  blocked by tenant Security Defaults (a Microsoft-365 config matter, not a code issue).

### Phase 15G — CI/CD foundation — `Implemented (infra/docs only)` — PR _pending_
- Added repo-root **GitHub Actions** (the first active CI/CD for this repo — prior workflows under
  `app/.github/workflows/` are the inert upstream CE ones).
- **`.github/workflows/ci.yml`** — runs on PRs targeting `version_1` (and manual dispatch),
  GitHub-hosted runner, `permissions: contents: read`, **reads no secrets**. Jobs: `rubocop`, `eslint`,
  `frontend-tests` (Vitest), `assets-build` (`rake assets:precompile`, the Vite build), `bloomwire-rspec`
  (curated Bloomwire scope — every `bloomwire/` spec + WhatsApp webhook job specs, **52 files**, on
  ephemeral Postgres pgvector-pg16 + Redis), `migration-check` (`db:schema:load` +
  `db:abort_if_pending_migrations`), `docs-governance` (forbids root `docs/product`/`docs/adr`, requires
  the Bloomwire docs), and a self-contained `secret-scan` of PR-added content.
- **`.github/workflows/deploy-dev.yml`** + **`.github/scripts/deploy-remote.sh`** — manual
  (`workflow_dispatch`) deploy to **dev/staging only** (production hard-blocked) over SSH. Builds the
  image with the exact `GIT_SHA` (stamps `/app/.git_sha`), optional `db:migrate`, recreates **only**
  `rails`+`sidekiq` (`--no-deps`, **postgres/redis volumes preserved**), tags `bloomwire-app:<sha>` for
  rollback, then smoke-checks (health 200, in-container SHA match, postgres/redis `Up`). `run_migrations`
  defaults to **true** (uncheck for rollbacks). Conservative optional cleanup (stopped containers /
  dangling images / build cache **older than 7 days** — **never volumes**).
- **Runtime fidelity:** the `bloomwire-rspec` job runs with **`DISABLE_ENTERPRISE=true`** — the documented
  Bloomwire runtime (locally supplied via `.env`). The curated specs assume the OSS path (e.g. they stub
  `Account#usage_limits`, which the enterprise prepend `Enterprise::Account::PlanUsageAndLimits` would
  otherwise own). The enterprise tree stays present but disabled, exactly as in the deployed artifact.
- **Security:** no secrets in CI; no live Meta/WhatsApp calls (specs WebMock-blocked); deploy credentials
  are per-environment GitHub Environment secrets, never printed; SSH key written `600` and removed after.
- **Not changed:** no application runtime code, no migrations, no Enterprise code, no Docker/compose files,
  no `.env`, no production deploy path. The server-local `docker-compose.bloomwire-production.yaml` overlay
  is untouched (gitignored).
- **Validation:** YAML parse OK; all embedded shell + `deploy-remote.sh` pass `bash -n`; Bloomwire spec
  selector resolves to 52 files. Live CI/deploy execution happens on the PR / first manual dispatch.
- **Residual:** `dev`/`staging` GitHub Environments + SSH secrets must be configured before the deploy
  workflow runs (see [`deployment-runbook.md`](./deployment-runbook.md) §3.2).

### Phase 15G.1 — Fix false-success dev deploy — `Fixed (infra/docs only)` — PR _pending_
- **Bug:** `deploy-remote.sh` is piped to the server via `ssh … bash -s`; `docker compose run --rm rails
  db:migrate` attached **stdin** and **consumed the rest of the script**, so after `db:migrate` bash hit EOF
  and exited `0` — silently skipping the recreate (step 4) and smoke (step 5). Result: a green deploy that left
  the app on the **old** image (caught on the first real `version_1`/`3bf260f` deploy via independent
  `/app/.git_sha` verification; the migration applied but containers were never swapped).
- **Fix (one line):** `… run --rm -T rails bundle exec rails db:migrate </dev/null` (`-T` + stdin redirect).
  Only `compose run` was affected (`up -d` is detached; smoke `exec -T` already safe).
- **Not changed:** no application code, no migrations, no compose files, no `.env`, no secrets, no production
  path; postgres/redis volumes untouched. Docs updated: runbook §6 troubleshooting + change-log.
- **Validation:** `bash -n` OK; PR CI green. Corrected re-deploy of `version_1` is gated on review/merge.

### Phase 17C.1 — Backend foundation for customer WhatsApp Embedded Signup — `Merged` — PR #100 (merge SHA `ac79a888e825f3c018924685c79c2bb47695e325`; `version_1` tip `ac79a88`)
- **Goal:** land the backend seams (C1 only) the future customer Add-Inbox → WhatsApp → Embedded Signup wizard
  will use, with **no** behavior change to native flows and **no** Meta calls / migration / secrets.
- **What:**
  1. **`canSelfServeManagedWhatsapp`** capability (`Bloomwire::Capabilities`) = `managed_capability(admin,
     restrict_native_whatsapp_setup? && Features.enabled?(:managed_whatsapp_onboarding))` — admin + Bloomwire ON +
     native WhatsApp restricted + the explicit **`managed_whatsapp_onboarding`** feature (master-gated +
     **privacy-dependent**, so privacy hardening required). Mutually-exclusive with `canManageNativeWhatsappSetup`;
     agents/OFF/feature-OFF/privacy-OFF/native-not-restricted → false. Existing capabilities unchanged. _(Review
     Blocker 1.)_
  2. **`Bloomwire::WhatsappSetupCreator`** — creates/updates the non-secret `Bloomwire::WhatsappSetup` router
     mapping for an already-existing channel+inbox (status `ready_for_webhook`). Non-secret inputs only (rejects
     api_key/provider_config kwargs); idempotent per `channel_whatsapp_id`; fails closed on cross-account,
     missing `phone_number_id`, or a `phone_number_id` claimed by another channel. **When `ready_for_webhook`,
     enforces router handoff-safety** (mirrors `WhatsappRouter.channel_aligned_with_payload?`): Cloud provider +
     provider_config `phone_number_id` match + `channel.phone_number == "+<display>"`, else `:unsupported_provider`
     / `:phone_number_id_mismatch` / `:display_phone_number_mismatch` (no value leaked). _(Review Blocker 2.)_ No
     account/user/inbox/channel creation; no Meta call; never mutates channel `provider_config`.
  3. **`WHATSAPP_CONFIGURATION_ID`** added to `Bloomwire::GlobalWhatsappConfig` as a **presence-only** Embedded
     Signup prerequisite (named blocker when missing + gates `platform_ready`; shown Present/Missing on the 17B
     page; value never rendered). App Secret / verify token stay presence-only.
- **Not done (C1 scope):** no dedicated endpoint, token exchange, Meta client, app-to-WABA subscription, frontend
  wizard, channel/inbox creation, manual fallback, or native `/whatsapp/authorization` carve-out.
- **Validation:** capability + creator (incl. router-alignment negative specs) + readiness specs; **full Bloomwire
  scope 683 examples, 0 failures (1 pre-existing pending)**; RuboCop clean. Regression: Global Config read-only;
  native auth still blocked; router + setup #1 unchanged. No deploy · no production · no secrets · no Meta/WhatsApp · no migration.
- **Follow-ups:** C2 (dedicated Bloomwire embedded-signup endpoint/service, Meta stubbed) · C3 (frontend wizard) ·
  C4 (verify/go-live). Real Meta E2E is owner-operated.

### Phase 17B — SuperAdmin "Global WhatsApp Config" page (read-only) — `Merged` — PR #98 (merge SHA `6eac9faf2cf50bf9910da4ae62179c73cfb96957`; `version_1` tip `6eac9fa`)
- **Goal (ADR-0008):** turn the post-17A read-only WhatsApp Setups surface into a clean **Global WhatsApp Platform
  Config** page — never anything resembling customer setup/provisioning.
- **What:** new `Bloomwire::GlobalWhatsappConfig` service (secret-free read-only summary) drives the rebuilt
  setups `index`: global webhook callback URL · Meta App ID (public; **required readiness prerequisite** — a
  missing `WHATSAPP_APP_ID` blocks `platform_ready`, since PR C onboarding is Embedded Signup first) · **App
  Secret / verify token = Present/Missing only** · router enabled/disabled · platform readiness + named blockers · **"Last webhook
  received: Not tracked yet"** · read-only connected-inbox list (account, inbox, masked phone/`phone_number_id`,
  setup status, readiness). Nav → "WhatsApp › Global Config".
- **Secret-storage decision (owner-approved read-only):** no encrypted global-secret store exists —
  `InstallationConfig` is plaintext; App Secret + verify token are **ENV/ops-managed**, read via
  `GlobalConfigService`. PR B shows **presence only** (`config_present?`), **never displays or saves** the values,
  and adds **no plaintext storage, no migration, no new store**. Editable secrets = parked (would need a separate
  encrypted `Bloomwire::PlatformConfig` design/ADR).
- **Not changed / not reintroduced:** no customer provisioning, no manual "New setup mapping", no account/user/
  inbox creation, no `Bloomwire::WhatsappSetup` create/edit here; router + webhook + setup #1 unchanged; feature
  toggles stay on the existing "Bloomwire Features" page (linked, not duplicated).
- **Validation:** `global_whatsapp_config_spec` (presence-only; never leaks values; callback URL; blockers; inbox
  count) + request specs (page renders; secrets Present/Missing with **values never rendered even when
  configured**; non-platform-admin blocked; master-OFF hides surface). **Full Bloomwire scope 657 examples, 0
  failures (1 pre-existing pending)**; RuboCop clean. No deploy · no Meta/WhatsApp · no secrets printed.
- **Follow-ups:** last-webhook-received telemetry (deferred) · PR C customer Add-Inbox Embedded-Signup wizard.

### Phase 17A — Remove SuperAdmin customer-provisioning + manual setup-mapping UI — `Merged` — PR #97 (merged `8719de2`)
- **Decision (ADR-0008):** the SuperAdmin "Provision new WhatsApp customer" flow and the standalone "New setup
  mapping" CRUD were over-engineered and duplicated Chatwoot's native account/user/inbox model. New architecture:
  **SuperAdmin WhatsApp = Global WhatsApp Platform Config only** · account/user creation stays **native**
  (SuperAdmin → Accounts/Users) · customers complete WhatsApp setup from **Account Settings → Inboxes → Add Inbox**
  · the internal `phone_number_id → inbox/channel` mapping remains but is created by the **customer-side wizard**
  (PR C), not manual Ops UI.
- **Removed:** `super_admin/bloomwire_customer_provisionings_controller` + route + view + `Bloomwire::CustomerProvisioningService`;
  `bloomwire_whatsapp_setups` actions `new/create/edit/update` (+ `new`/`edit`/`_form` views) → route `only:
  [:index, :show]`; **16C** `send_owner_activation` + `Bloomwire::BusinessOwnerActivator` + "Business owner
  access" card (redundant now — native Devise invite/reset covers owner access once provisioning is gone); nav
  "New Provision" + index provision/new-mapping/edit links; obsolete specs; stale controller-name refs.
- **Kept intact (router must-stay):** `Bloomwire::Webhooks::WhatsappRouter` + webhook controller;
  `Bloomwire::WhatsappSetup` model + `bloomwire_whatsapp_setups` table (router resolves
  `ready_for_webhook.where(phone_number_id:)` → inbox/channel); encrypted `Channel::Whatsapp#provider_config` +
  `Bloomwire::WhatsappCredentialWriter`; `WhatsappRealHopReadiness`; read-only index/show/readiness/credentials
  (transitional → Global Config in PR B).
- **Not changed / not dropped:** no migration, **no table drops, no data deleted** — existing setup #1 / account
  #1 untouched and still routes. `Bloomwire::WhatsappSetupRequest` **deprecated/parked** (removed later after PR C).
- **Validation:** routing spec (removed routes absent; observability + parked setup-requests routable) · boundary
  + setups + ops-boundary specs refactored · **full Bloomwire scope 647 examples, 0 failures (1 pre-existing
  pending)** · router + whatsapp_events_job regression green · RuboCop clean. No deploy · no Meta/WhatsApp · no secrets.
- **Follow-ups:** PR B (rebuild read-only surface into Global WhatsApp Config) · PR C (customer Add Inbox wizard
  that creates channel + inbox + `WhatsappSetup` mapping) · then remove the parked `WhatsappSetupRequest`.

### Phase 16C — Business-owner activation (set-password after provisioning) — `DEV PASS` (end-to-end) — PR #95 (merged `9b09f9e`)
- **Trigger:** `CustomerProvisioningService` creates the business owner **confirmed with a throwaway password and
  no email** → a provisioned owner could not log in (the one gap blocking a usable managed customer).
- **Owner (behavior):** new `Bloomwire::BusinessOwnerActivator` + a member action `send_owner_activation` on
  `Super_admin::BloomwireWhatsappSetupsController`, surfaced as a **"Send activation email"** button on the setup
  detail page.
- **What it does:** sends Devise **set-password (reset) instructions** to the setup account's **administrator(s)
  only** (native `Account#administrators`; never agents), mirroring `PlatformAdminInviter#send_password_setup`
  (best-effort, rescued). Owner sets a password and signs in to the **native** Chatwoot WhatsApp inbox.
- **Not changed:** no DB migration; creates **no new** accounts/users/account_users/inboxes/conversations/
  messages; **no** role change; **no** `PlatformAdmin` grant; **no** global `BusinessOwner`; reuses Devise
  `recoverable` + native models (no data duplication). No Meta/WhatsApp calls; no SMTP credential change.
- **Only intended mutation:** Devise's recoverable/reset-password fields (`reset_password_token` digest +
  `reset_password_sent_at`) on the targeted administrator user(s) — required to send the set-password email; the
  reset token/password/link are never exposed in UI/logs/audit.
- **Security:** `/super_admin` platform-admin boundary + master-mode gate; reset token/password/link **never**
  shown in UI/logs/audit; safe audit via `AdminUserAudit` (field-names only); SMTP failure rescued (no 500).
- **Validation:** service + request specs (admin-only targeting · authorization · master-OFF unavailable ·
  no-platform-grant · no-new-records / no-role-change · safe audit · no-secret · SMTP-failure) — **15 examples, 0 failures**;
  setups/readiness/provisioning/credentials regression green; RuboCop clean.
- **DEV runtime (2026-06-30 → 2026-07-01) — `DEV PASS` (end-to-end):** deployed `version_1 @ 9b09f9e` to dev (run
  `28461253274`): rails+sidekiq `/app/.git_sha` match · health 200 local+public · 0×5xx · postgres/redis volumes
  preserved · no pending migrations. **Feature end-to-end verified:** "Business owner access" card renders, "Send
  activation email" works, targeting the **real account administrator** `User #2` / `sameen@bloomwire.lk` (account
  #1 admin). Owner **received the email, set a password, logged in, and reached the native Chatwoot inbox** —
  confirmed. `reset_password_sent_at` set at send-time then **cleared by Devise after the successful reset**
  (expected; `reset_password_token` also cleared = consumed). Safe audit row (`action=send_owner_activation`,
  field-names only; `changed_fields=[]`/`blocked_fields=[]`); **no** reset token/password/link in UI/audit/docs;
  **no** `PlatformAdmin` grant created by the activation (`User #2`'s pre-existing `owner` grant is old — **0** new
  grants in 30m/12h); roles unchanged (`User #2`=administrator; `sameen.android@gmail.com`/`User #50`=agent,
  sender/dev only, never made admin); **no** Meta/WhatsApp calls; **no** production deploy. SMTP verified with
  booleans/masked output only.
- **Mailer root cause & fix (cleared the earlier block):** the earlier `PASS-BUT-BLOCKED` was because the dev
  **global SMTP env was empty**, so stock Chatwoot `config/initializers/mailer.rb` correctly fell back to
  `:sendmail` (no MTA → `Errno::EPIPE`, no delivery). Phase 15F **templated** emails worked because they use the
  **DB-backed `Bloomwire::EmailSetting`** SMTP path; Devise/16C use the **global ActionMailer (ENV)** path. **Fix
  (operational, dev only):** populated the dev global `SMTP_*` env from the owner's local `#PERSONAL EMAIL SETTINGS`
  block (`SMTP_PORT=587`, STARTTLS on) and **recreated rails + sidekiq** → `delivery_method=:smtp` on both. **No
  `Bloomwire::EmailSetting` change · no code change · no credential values printed · no production deploy.** (Devise
  tokens appear in Sidekiq job-arg logs for all Devise emails — pre-existing platform behavior, not 16C.)

### Phase 15F.UI — Email Templates UI Polish & Responsive Upgrade — `DEV PASS` — PR #90 (merged `88e0701`)
- **Trigger:** the Email Templates page worked but felt cramped/dense, panels competed, the Send-from-Template
  composer was too low + under-emphasised, the toolbar was cramped, the preview read like a debug area, and the
  3-panel grid jumped 3→1 columns at 1200px (no graceful medium/tablet reflow).
- **Owner (behavior):** none changed — this is **CSS + view-wrapper only**. Files: `super_admin/index.scss`,
  `_tab_templates.html.erb`, `_composer.html.erb`, `_email_preview.html.erb`.
- **What changed:** responsive `bw-email-grid` (library | editor | preview → 2-col with preview reflow ≤1280px →
  stacked ≤880px); wrapping toolbar (search row + category/Filter below); scrollable list with active accent bar +
  hover lift; email-client "window" frame (`bw-preview-frame`) around BOTH sample + final previews (same shared
  branded partial, so preview still equals delivered); a separated "Send a real email" section header above an
  accent-topped composer card (`bw-card--composer`) with a responsive `bw-composer-grid`; more padding/gaps.
- **Not changed:** no controller/model/route/DB change; no SMTP credential/provider/DNS/WhatsApp-Meta change;
  owner-only gate intact; every form/link/id (`#bw-composer`, `#bw-send-result`, compose fields, CRUD forms),
  validation, send-feedback banner, and button states preserved.
- **Validation:** render request specs (templates tab + composer + previews) green; SCSS compiles; **dev runtime
  QA passed on `88e0701`** — deployed CSS confirms 1440 = 3-col, ≤1280 = 2-col + sample-preview full-width reflow,
  ≤880 = stacked, ≤980 = composer stacks; owner-only gate intact; no migration; SMTP unchanged. Before/after
  screenshots = owner-assisted (MCP browser had no authenticated owner session).

### Phase 15F.6 — Email CTA Button Rendering Fix — `DEV PASS` — PR #89 (merged `53e3e7b`)
- **Trigger:** a delivered invitation email showed the CTA as plain text `[www.google.com]Accept Invitation` —
  the purple button was missing (body/card/footer rendered fine).
- **Root cause:** the template `cta_url` is `{{invitation_link}}` (passes the template-level `cta_url_safe_scheme`
  validation because a `{{placeholder}}` is allowed), but the **RESOLVED** CTA URL (after the owner fills the
  variable) was never validated. A scheme-less value `www.google.com` reached the mailer → relative
  `<a href="www.google.com">` → email clients neutralize a relative href in HTML mail → button degrades to text
  and the URL leaks.
- **Owner (behavior):** `Bloomwire::SendTemplateEmailService` (send validation) + `Bloomwire::EmailTemplate`
  (resolved-URL validity) + `bloomwire/email/_branded_email.html.erb` (button render) +
  `super_admin/bloomwire_email_settings/_composer.html.erb` (preview block-state).
- **What changed:** `EmailTemplate.absolute_cta_url?` (requires `http(s)://`); service blocks `invalid_cta_url`
  before SMTP with *"Enter a full URL starting with https:// …"*; branded partial renders an email-safe
  **table + `td bgcolor`** button (inline styles, escaped label+href) ONLY for an absolute URL; composer disables
  Send + shows a *"Button link must be a full URL"* block and the Final preview hides the button — preview ==
  delivered. Text fallback stays `Label: https://…` (never `[url]label`). Also blocks `javascript:`/`data:`.
- **Not changed:** no DB migration; no SMTP secret/credential change; no DNS; no WhatsApp/Meta; no auth/audit;
  CTA-label interpolation (15F.2) + send-feedback UX (15F.3) preserved.
- **Validation:** model + service + mailer + request specs (incl. RED-first: scheme-less URL was delivered before
  the fix); full email + 15G.2 + 15G.3 suite **123 examples, 0 failures**; RuboCop clean; no secret in body/logs.

### Phase 15F.3 — Email Send Feedback UX Polish — `DEV PASS` — PR #86 (merged `bf6aa15`)
- **Trigger:** Phase 15F.2 was deployed + DEV PASS, but the owner found the send feedback unclear — after a
  template send the only signal was a flash at the **top** of the page; the page appeared to refresh, so it was
  unclear whether the email was sent, blocked, or failed.
- **Owner (behavior):** `SuperAdmin::BloomwireEmailTemplatesController#send_email` (redirect target) +
  `super_admin/bloomwire_email_settings/_composer.html.erb` (feedback rendering) +
  `SuperAdmin::BloomwireEmailSettingsController#show` (latest-log context) + `Bloomwire::SendTemplateEmailService`
  (result message shape).
- **What changed:**
  - **Composer-local result banner** (`#bw-send-result`, `role="status"`/`aria-live`): success →
    "Email sent successfully to <recipient>"; blocked/failed → "Email was not sent: <safe reason>"; colour-coded by
    status. The global top flash still shows; composer-local feedback is the new, required surface.
  - **Land on the composer:** `send_email` redirects to the templates tab with the selected `template_id` **and
    `#bw-composer` anchor** (inline redirect — the shared `redirect_to_template` CRUD helper is unchanged to avoid
    a Ruby keyword/positional-hash regression).
  - **Status + logs link:** banner shows the latest per-template delivery-log status/time/recipient
    (`@composer_last_log`) and a **"View Email Logs"** link.
  - **Double-send guard:** Send button uses `data-disable-with="Sending…"`.
  - **Message consistency:** service result messages standardised; Email Log status (success/blocked/failed)
    matches the banner; sanitized errors only.
- **Not changed:** no DB migration; no SMTP secret/credential change; no WhatsApp/Meta; no auth/audit
  (15G.2/15G.3) behavior; CRUD template redirects unchanged; all three outcomes still write an Email Log row.
- **Validation:** new send request specs (visible result near composer for success/blocked/invalid email; composer
  anchor in redirect; template stays selected; Email Log row written; no SMTP secret in body); full Bloomwire
  email + 15G.2 + 15G.3 suite **113 examples, 0 failures**; RuboCop clean.
- **Residual / deferred:** (a) composer "Update preview" still uses a **GET** round-trip (values in query string)
  → **Phase 15F.5** (POST-based preview / query-string hardening); (b) **email deliverability / domain
  authentication** → **Phase 15F.4** (PR #87, report-only); (c) optional auth-audit polish → **Phase 15G.4**.

### Phase 15F.4 — Email Deliverability + Domain Authentication — `Investigation (report-only)` — PR _pending_
- **Trigger:** email send + template UX are DEV PASS and mail is delivered, but messages to the owner's
  `bloomwire.lk` mailbox land in **junk/spam**. Report-only investigation; tracked separately from the 15F.3 Send
  Feedback UX so the two concerns don't mix.
- **Scope guardrails:** no code · no DB migration · **no DNS change** · **no SMTP credential change** ·
  **no production deploy** · **no WhatsApp/Meta/provider credentials touched** · no secrets printed.
- **Current dev SMTP behavior (read-only, masked):** `smtp.gmail.com:587`, `login` + STARTTLS; SMTP username and
  `from_email` both `@gmail.com` (**personal Gmail**, not Workspace for `bloomwire.lk`); From display-name
  `"Bloomwire"`; no Reply-To / no Return-Path override (envelope = the gmail.com username). Password length only.
- **Diagnosis — not an auth failure:** sending *as* `gmail.com` via Gmail's authenticated servers → SPF pass,
  DKIM `d=gmail.com`, DMARC aligned for `gmail.com`. The junking is **brand-identity / reputation / content**:
  (1) brand display-name on a free `@gmail.com` address; (2) branded content linking to **dev.unecast.com**
  (sender domain ≠ link domain, low-reputation dev host); (3) no `bloomwire.lk` sending reputation.
  Owner header evidence (`Authentication-Results`, `Received-SPF`, DKIM `d=`, `From`, `Return-Path`) will confirm.
- **Recommended production setup (NOT applied; owner DNS/provider action required):** dedicated sending subdomain
  (`mail.bloomwire.lk` / `notify.bloomwire.lk`) · transactional provider (Postmark / Resend / AWS SES / Mailgun /
  SendGrid / Brevo) · SPF on the subdomain only (`v=spf1 include:<provider> -all`, leave root SPF untouched) ·
  provider DKIM selector on the subdomain · DMARC `p=none` + `rua` first, then tighten · From == authenticated
  domain (`noreply@mail.bloomwire.lk`) + real Reply-To · production links on the real brand/app domain ·
  bounce/complaint webhooks into Email Logs.
- **App send flow:** unchanged and still **PASS** (deliverability/DNS/provider, not an app bug).
- **Impact:** does **not** block Phase 16 dev work (dev mail is delivered); **blocks production / client email
  readiness** until the DNS/provider setup is completed.
- **Validation:** read-only dev SMTP-config inspection (masked); docs-only; no code/tests changed.

### Phase 15F.2 — Email Template UX Completion — `100% DEV PASS` — PR #84 (merged `ea3487b`)
- **Trigger:** dev runtime QA on `ba76e21` passed core flows but found Email Templates incomplete: composer had
  only 6 fixed variable inputs; the live preview used SAMPLE data for blank variables while the real send sent
  blank (preview ≠ delivered); invalid emails were only caught by SMTP; Email Logs showed template name, not the
  literal subject.
- **Dynamic variables:** `EmailTemplate#used_variables` parses every `{{variable}}` in subject + body + CTA
  (deduped, custom variables supported, shared `VARIABLE_PATTERN`); composer generates one humanized input per
  variable (`humanize_variable`, `keep_id_suffix: true`).
- **Preview == send:** new `EmailTemplate#composition_for` / `#resolved_variables` / `#missing_variables` is the
  SINGLE resolver used by both the "Final preview" and the send. Blank variables are never silently sampled —
  they remain visible `{{placeholders}}`.
- **Blank-on-first-load (review fix):** composer variable inputs open **empty**; `SAMPLE_VARS` are placeholder/
  helper text + the separate "Sample preview" only — never prefilled as real values. Send stays disabled until
  every variable is intentionally filled, so sample data can't be accidentally sent.
- **CTA button label (review fix):** the CTA **label** is now included in variable detection, interpolation,
  and the leftover-`{{placeholder}}` block — a variable used only in the button label generates a composer input,
  renders identically in preview + delivered email, and blocks the send if unfilled (completes the "no raw
  `{{placeholder}}` delivered" guarantee).
- **Validation:** `SendTemplateEmailService` blocks invalid recipient email + any leftover `{{placeholder}}`
  (subject/body/CTA label/CTA URL) before SMTP (blocked Email Log + clear message); composer shows inline "fill
  these in" + disables Send.
- **Email Logs:** literal sent subject column added (data already stored per send). Sample preview relabeled.
- **Deferred:** composer "Update preview" GET round-trip puts values in the URL query string → **Phase 15F.5**
  (POST-based preview / query-string hardening); optional auth-audit polish → **15G.4**.
- **Not changed:** no DB migration; no SMTP secret/credential change; no WhatsApp/Meta; no 15G.2/15G.3 auth
  behavior. CRUD (create/edit/duplicate/deactivate/reactivate) preserved. Optional auth-audit polish deferred to
  **15G.4**.
- **Validation:** model+service+request specs; full email + 15G.2 + 15G.3 suite **109 examples, 0 failures**;
  RuboCop clean; no secrets (fake values only). **Phase 16 blocked** until merged + deployed + runtime QA passes.

### Phase 15G.2 — Auth Integrity Hardening — `Hardened` — PR _pending_
- **Trigger:** forensic RCA of an owner login failure. Proven that the deploy, the platform-admin/permissions
  code (`grant!`/`revoke!`/`reactivate!`/inviter-existing/`EnsurePlatformOwnerService`), migrations, seeds, and
  Devise secret/pepper did **not** mutate the user's password. The only code path that *could* change an
  existing SuperAdmin's password was the **generic Administrate User edit form's password field** (non-blank /
  browser-autofill submit). This phase closes that vector before go-live.
- **Change (minimal, test-backed):**
  - `UserDashboard#form_attributes` drops `:password` + `:confirmed_at` from the **edit** form (create still
    sets an initial password); the edit form renders no password input.
  - `SuperAdmin::UsersController#resource_params` strips, **on update only**, an auth-sensitive denylist:
    `password, password_confirmation, encrypted_password, reset_password_token, reset_password_sent_at,
    confirmed_at` (defense-in-depth). `:type` still stripped in Bloomwire Mode. Password changes go only via the
    Devise reset flow.
- **Protected from generic Users edit:** `encrypted_password`, `password`, `password_confirmation`,
  `reset_password_token`, `reset_password_sent_at`, `confirmed_at`, `type`.
- **Not changed:** no DB data, no password reset, no rollback, no migrations, no Devise/secret/session config,
  no platform-admin/account-role logic. New-user create + platform-admin invite (new email) still set a password.
- **Tests:** new `bloomwire_auth_integrity_spec.rb` (10 examples) + 48-example regression across the related
  super_admin specs; RuboCop clean. No secrets/hashes printed (SHA-256 fingerprint comparison only).

### Phase 15G.3 — Auth Go-Live Guardrails — `Hardened` — PR _pending_
- **Audit trail (closes the RCA provability gap):** new Bloomwire-owned table `bloomwire_admin_audit_logs` +
  `Bloomwire::AdminAuditLog` + `Bloomwire::AdminUserAudit`. Every `super_admin/users#update` records one row —
  `actor_id`, `target_user_id`, `controller`, `action`, `changed_fields` (columns changed), `blocked_fields`
  (auth-sensitive params submitted but stripped by 15G.2). **Field NAMES only, never values**; auditing never
  breaks the request (rescued).
- **Never stored:** `password`, `password_confirmation`, `encrypted_password`, reset tokens, secrets, raw hashes.
- **Auth smoke (`.github/scripts/auth-smoke.sh`):** optional operator-run dev/staging login smoke with a
  **dedicated disposable test admin**. Enforces a **host allowlist (default-deny)** — only `dev.unecast.com`
  (+ `SMOKE_ALLOWED_HOSTS` for a future staging host); every unknown host incl. production is refused. Also
  refuses the owner account; password read from a file (never argv/`ps`); `SMOKE_VALIDATE_ONLY=1` runs just the
  guards; verifies sign-in + deployed `/app/.git_sha`. Not auto-wired (no CI secret); guard contract tested by
  `spec/scripts/bloomwire_auth_smoke_spec.rb`.
- **Runbook §7:** password changes only via the Devise reset flow (never the generic Users edit); audit fields +
  exclusions; the auth-smoke procedure.
- **Dev runtime verification (task 1):** deployed SHA `f140717…`; owner login-ready (SuperAdmin/confirmed/owner
  active; recovery reset applied — fingerprint changed); `/super_admin/sign_in` = 200; deployed code carries the
  15G.2 protections.
- **Not changed:** no rollback, no password reset (recovery already done), no production, no WhatsApp/Meta/
  provider credentials, no business/account role semantics, no Devise/secret/session config.
- **Migration:** `20260630000001_create_bloomwire_admin_audit_logs` (additive). **Tests:** audit request spec
  (3) + 15G.2 (10) + user-flow (6) green; RuboCop clean; `bash -n` on the smoke script OK.

---

## 4. Permission model reference

### Platform side (Bloomwire internal)
- Surface: **`/super_admin`**.
- **`users.type = 'SuperAdmin'`** is a **technical Devise/STI identity** — not a business role.
- Platform access is controlled by **`bloomwire_platform_admins`** (an active approval row is required).
- Platform roles: **`owner`**, **`admin`**, **`support`**.
- Platform users are **Bloomwire internal users**.

### Business / customer side
- Surface: the customer app at **`/app/accounts/:id`**.
- Account membership is controlled by **`account_users`**.
- Roles: **`administrator`**, **`agent`** (DB values).
- UI labels (Bloomwire Mode): **Business Admin**, **Agent**.
- **Do not add `BusinessOwner` yet.**
- **Do not use `users.type` for business/customer roles.**

### Conversation assignment
- **Assignable agents = inbox members + account administrators.**
- An account **Agent must also be an inbox collaborator/member** to appear in the Assigned Agent dropdown.
- **Team assignment** is separate from agent assignment.
- **Priority** is separate from both.

---

## 5. WhatsApp architecture reference

- **Current scope is WhatsApp only.**
- **Global webhook / router** direction (`BLOOMWIRE_GLOBAL_WEBHOOK_ROUTER`): a single shared webhook entry
  that resolves to the correct mapped channel/inbox. **No per-customer random webhook URL strategy.**
- **Provider credentials must not be exposed** (filtered in logs; never returned in business-facing
  responses; scrubbed via the privacy-hardening path).
- **No WhatsApp/Meta live calls** unless explicitly authorized (tests stay WebMock-blocked).
- **No duplicate conversation/message source of truth** — the existing Chatwoot/Bloomwire data model
  remains the **single source of truth** for conversations and messages.
- **Future channels should not be over-built now.** Keep the WhatsApp-first path clean; add channels later
  behind their own scoped work.

---

## 6. OSS / Enterprise statement

- Bloomwire uses the **OSS-compatible code path only** (`DISABLE_ENTERPRISE=true`).
- **Enterprise code/features are not part of the Bloomwire implementation** and must not be relied upon.
- **No Enterprise dependency** should be introduced.
- Any future "Enterprise-like" capability must be implemented in **Bloomwire-owned code**, or evaluated
  **legally and technically** before any use of Enterprise-licensed code.

---

## 7. What we intentionally did NOT change

- **No `BusinessOwner` role yet** (account roles remain `administrator` / `agent`).
- **No new customer message/conversation tables** (no duplicate chat storage).
- **No Enterprise WhatsApp code usage.**
- **No multi-channel support yet** (WhatsApp-first).
- **No billing / subscription system yet.**
- **No Meta template send** until an approved template exists.
- **No full replacement of the Chatwoot assignment system** — stock account/inbox assignment semantics are
  preserved; the only expectation is that **Bloomwire onboarding respects them** (attach agents to inboxes).

---

## 8. Parked / residual items

| Item | Type | Notes |
|---|---|---|
| Approved WABA template required | `Parked` | Out-of-window/template send waits on an approved Meta template. |
| Intermediate SSO token handoff URL | `Residual` | From Phase 15C — brief `/app/login?…sso_auth_token=…` handoff; full removal needs a frontend/auth handoff redesign. Mitigated (short-lived, single-use, on-click only). |
| Manual inboxes can miss collaborators | `Warning` | Onboarding should attach agents to the inbox; manually-created inboxes may have zero members → only admins are assignable (Phase 15D). |
| Inbox-has-no-agents UI warning | `Optional` | A future UX hint when an inbox has no agents/collaborators. |
| `BusinessOwner` role | `Optional` | Only when billing / ownership-transfer / subscription features exist; must be separately designed. |
| Channel expansion | `Optional` | Instagram / Messenger / Telegram / Signal — future, not now. |
| SMTP password stored plaintext (Phase 15F) | `Security debt` | `bloomwire_email_settings.smtp_password` is plaintext because AR encryption isn't configured. Never shown/logged/printed. **Encryption-at-rest is the priority follow-up.** |
| Transactional mailer wiring (Phase 15F) | `Parked` | Business-invitation/welcome/plan-change/receipt/ticket templates exist + preview, but are not yet wired to send on real events. Password reset stays on Devise + global ENV SMTP. |
| Per-message email delivery logging | `Implemented for template sends (Phase 15F.1)` | `bloomwire_email_delivery_logs` records one row per "Send from Template" send (success/failed/blocked); the Email Logs tab shows them. Logging of event-driven/transactional sends remains tied to the parked transactional wiring above. |

---

## 9. Operational rules for future agents

- **Evidence first** — no assumptions; prove the root cause before changing anything.
- **Do not merge/deploy without approval.**
- **Exact-SHA review gate** — only merge the explicitly approved head SHA; abort if the head changed.
- **No WhatsApp/Meta/provider credential mutation** unless explicitly authorized.
- **Mask** secrets, tokens, phone numbers, and emails where practical in reports/logs.
- **Do not use `users.type`** for customer/business roles.
- **Do not add `BusinessOwner`** unless separately designed.
- **Do not duplicate** chat/message storage.
- **Test Bloomwire Mode ON.**
- **Test stock-compatible behavior** (Mode OFF) when touching Chatwoot flows.

---

## 10. Documentation Governance

_Introduced in **Phase 15E.1**. Canonical rule: `AGENTS.md` → "Bloomwire Documentation Governance"._

Every Bloomwire-owned change must be **transparent and documented** — no hidden or undocumented
changes. Any PR that changes **behavior, permissions, security, onboarding, WhatsApp flow, APIs, UI
flows, the data model, an operational process, or customer-facing behavior** must update, **in the
same PR**:

- `docs/bloomwire/implementation-ledger.md` and `docs/bloomwire/implementation-ledger.html`
- the Bloomwire change log (`docs/bloomwire/change-log.md`)
- the related **ADR/runbook** if architecture or operations are affected

**A PR that changes Bloomwire behavior without updating docs/changelog is not approval-ready.**
Docs-only PRs need no runtime deploy.

Each entry records: **phase · PR number · merge SHA · what changed · why · what was intentionally NOT
changed · validation evidence · residual risks / parked items.** Security/permission/WhatsApp entries
must also state: **no secrets exposed · no provider-credential mutation unless authorized · whether
any live Meta/WhatsApp calls were made · whether Enterprise code was touched.**

Preserve the invariants: no `users.type` for business roles · no `BusinessOwner` without separate
design · no duplicate chat/message source of truth · no Enterprise dependency · WhatsApp-first scope.

### Definition of Done (Bloomwire change)

- [ ] code implemented
- [ ] tests passed
- [ ] runtime/browser proof when applicable
- [ ] **docs updated** (implementation ledger `.md` + `.html`)
- [ ] **changelog updated** (`docs/bloomwire/change-log.md`)
- [ ] residual risks recorded
- [ ] **exact merge SHA recorded after merge**

---

<sub>Bloomwire Implementation Ledger · generated 2026-06-29 · baseline `4084a23eb4a83b1ee41e298811a91d52d6fb6044` · docs only, no runtime behavior.</sub>
