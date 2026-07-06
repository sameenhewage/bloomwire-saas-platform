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
| 17C.2 | Dedicated Bloomwire WhatsApp Embedded Signup endpoint + service (`bloomwire/whatsapp/embedded_signup`; global-router app-to-WABA subscribe; `bloomwire_managed` channel + inbox + mapping; Meta stubbed) | #102 | Merged (`84481ed`) |
| 17C.3 | Customer frontend WhatsApp connection wizard (`canSelfServeManagedWhatsapp` gate + `BloomwireWhatsapp.vue`; **connection-choice screen** → Coexistence [disabled/coming-soon] + Register New Number [standard]; Connect with Meta → safe DTO; no credentials/agents step; Meta mocked) | #104 | Merged (`bf81c7c`) |
| 17D.0 | WhatsApp Business App **Coexistence discovery contract** (`docs/bloomwire/whatsapp-coexistence-discovery.md`; evidence/report-only — locks the `connection_mode=coexistence` contract + boundary before enabling) | #106 | Merged (`f9aeac7`) |
| 17D.1 | WhatsApp Business App **Coexistence backend contract** (`bloomwire/whatsapp/coexistence_embedded_signup` + `WhatsappCoexistenceEmbeddedSignupService`; `connection_mode=coexistence`; inherits safe 17C.2 seam; Meta stubbed) — backend only, Coexistence UI still disabled | #107 | Merged (`ebdcba2`) |
| 17D.2 | WhatsApp Business App **Coexistence webhook proof** (router routes coexistence by phone_number_id; `smb_message_echoes` → existing outgoing echo path; `smb_app_state_sync` → new safe-ignore guard; proof doc; fake payloads) — backend/webhook only, Coexistence UI still disabled | #109 | Merged (`4a57564`) |
| 17D.3 | WhatsApp Business App **Coexistence frontend enablement** (enable the `BloomwireWhatsapp.vue` Coexistence card — remove disabled/"Coming soon"; `flow=coexistence` reuses the credential-free Embedded-Signup form + new `createBloomwireCoexistenceEmbeddedSignup` → `bloomwire/whatsapp/coexistence_embedded_signup`; Standard flow unchanged; Meta/SDK mocked) — frontend only, no backend/migration | #111 | Merged (`ea30579`) |
| 17E.0 | Multiple WhatsApp Inbox per Account **discovery + ADR-0009** (`docs/bloomwire/whatsapp-multi-inbox-discovery.md` + ADR; **verdict SUPPORTED** — multi-inbox per account already works, services create a new channel+inbox+setup per number & block only duplicate `phone_number`/`phone_number_id`, no per-account cap, router resolves by `phone_number_id`; Category = Team + Inbox; caveats: contacts account-wide + no multi-inbox tests) — docs-only, no code/tests | #112 | Merged (`8349689`) |
| 17E.1 | Multiple WhatsApp Inbox **backend contract tests** (RSpec: Standard+Coexistence service/request → 2 numbers = 2 channels/inboxes/setups per account, dup `phone_number`/`phone_number_id` blocked; router 2 pnids→2 inboxes in one account, unknown/crossed fail-closed; NEW category contract: ConversationFinder+ConversationPolicy agent-isolation + team-filtered assignment) — **test-only, no product code** | #113 | Merged (`5df9f9d`) |
| 17E.2 | **Contact isolation & UI/permission polish** (gated backend fix — new `BLOOMWIRE_RESTRICT_AGENT_CONTACT_VISIBILITY` + `Bloomwire::ContactVisibility` seam; agent contact list/search/show scoped to contacts reachable via assigned inboxes through `contact_inboxes`; admins see all; **OFF == stock**; routed through ContactsController/FilterService/SearchService/contacts base_controller) — **product code YES, no migration/frontend** | #114 | Open (ready for review, not merged) |
| 17F.2A | Managed WhatsApp onboarding entry restoration (New Inbox entry + non-blank Add Inbox surface; admin/agent + feature-OFF/stock-compatible behavior preserved) — frontend product code | #122 | Merged (`6894d93`) · DEV PASS for UI/runtime scope; Real Meta Coexistence certification BLOCKED/DEFERRED |

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

### Phase 17D.0 — WhatsApp Business App Coexistence discovery contract — `Merged` — PR #106 (merge SHA `f9aeac7245bb6e9869c25233ed68377f77062e90`; approved head `1b8ae29`)
- **Goal:** an evidence/report-only discovery that locks the Coexistence backend contract before enabling the
  disabled "Connect Existing WhatsApp Business App" card — so 17D.1 could implement it without leaking credentials,
  duplicating messages, or weakening the native flow.
- **What:** `docs/bloomwire/whatsapp-coexistence-discovery.md` — current-`version_1` evidence, the intended
  `connection_mode=coexistence` contract, open questions, and the 17D.1/17D.2/17D.3 plan. Docs only; no code,
  route, frontend, migration, deploy, or Meta call.
- **Validation:** docs-only; CI docs governance green on PR #106.

### Coexistence onboarding infinite-wait hardening + sanitized end-to-end trace — `Open (product code; not merged)`
- **Branch** `fix/bloomwire-coexistence-onboarding-trace` off `version_1` `d21a243b614835769a3dd3c255c1d917e75dfdfc`.
  No schema/migration · Enterprise: NO · webhook router: UNCHANGED · Standard flow: UNCHANGED · account-1 fixture untouched.
- **Incident RCA (Part 1) — Stage A:** the customer completed the Meta flow (3 Meta webhooks 04:17–04:19 →
  `no handoff-safe setup`, 200), but the browser received no signal that resolved `runEmbeddedSignup()`; the create
  POST was never dispatched (0 coexistence POSTs in the current-container logs), 0 records created, and the hang was
  indefinite → PR #127's second-signal timeout never armed. Read-only investigation; no records mutated; no retry.
- **Fix (Part 3):** finite state (`idle/launching/waiting_for_meta/waiting_for_second_signal`) + **overall watchdog
  armed at launch** (default 180s, covers zero-signal / never-settling SDK) + kept second-signal timer + **bounded
  backend create** (45s). Guaranteed teardown (settle-once + `cancel()` on `onBeforeUnmount`/`onBeforeRouteLeave`)
  clears timers/listener/`isAuthenticating`/processing on every terminal path. Failure UX: spinner stops, sanitized
  message, support reference (short attempt id), manual Retry, no auto-retry, no partial records.
- **Trace (Part 2):** one `onboarding_attempt_id` carried browser→controller; `Bloomwire::OnboardingTrace` writes
  one allow-listed structured-JSON line per event to the app log (22 events); new admin-only, account-scoped,
  feature-gated (404), rate-limited endpoint `POST …/bloomwire/whatsapp/onboarding_traces` with strict event +
  metadata allow-list (unknown event → 422; logging failure → 204). Never logs code/token/phone/phone_number_id/
  WABA/business/App ID/Config ID/Meta URL. Standard/native flow untraced (no-op tracer).
- **Validation:** composable 20 · wizard 25 · trace service 9 · trace endpoint 8; WhatsApp backend regression
  281/0; ESLint + RuboCop clean; vite build ok; no secret in diff. Runtime trace evidence deferred to Part 6
  (post-approval deploy + owner-assisted controlled retry).

### WhatsApp channel tile intermittently disappears (deterministic-state fix) — `Open (product code; not merged)`
- **Branch** `fix/bloomwire-whatsapp-tile-race` off `version_1` `8fabfc331b7f62d5c64197fe020e563140d3239f`.
  **Frontend-only.** Backend/DB/router/auth/config: NO · Enterprise: NO · Standard/Coexistence flows: UNCHANGED.
- **Symptom** `/app/accounts/:id/settings/inboxes/new`: the WhatsApp tile appeared on one refresh, was absent on
  another (same user/account/URL/build) — demo-blocking, non-deterministic.
- **RCA (proven)** Backend deterministic (deployed `8fabfc33`: `Bloomwire::Capabilities.for` →
  `canSelfServeManagedWhatsapp=true`, `canCreateInbox=false`, 10/10; flags all true). Capabilities ship **only** on
  the account-show payload (`_account.json.jbuilder`, gated on `@current_account_user`); the bootstrap `_user`
  accounts array omits them. Frontend fault: `useBloomwireCapabilities` falls back to `canSelfServeManagedWhatsapp=false`
  whenever the account payload has not hydrated (cannot tell "loading" from "denied"); for a managed account WhatsApp
  is the ONLY tile, so `ChannelList.vue` (which had **no loading state**) painted the terminal "MANAGED_BY_OPS" empty
  surface whenever the filtered list was momentarily empty. `accounts/get` swallows failures silently (no retry/error),
  and `initializeEnabledFeatures` dereferenced `currentAccount.value.features` unguarded.
- **Fix** `useBloomwireCapabilities` exposes `capabilitiesLoaded`; `ChannelList.vue` hydrates the account on mount
  and renders loading skeleton → recoverable error+retry (on failure / caps-never-arrive) → tiles → managed empty
  state only when genuinely loaded with no permitted channel. Never an empty surface during loading. Agents stay
  blocked; account context + Standard/Coexistence entry unchanged.
- **`custom_roles` 500 (separate)** Enterprise controller `Current.account.custom_roles` on a non-enterprise build
  (`has_many :custom_roles` is enterprise-only). NOT requested on inbox-new (verified) → unrelated → separate
  follow-up (frontend should skip the fetch without the enterprise custom-roles capability); not touched here.
- **Validation** `ChannelList.spec.js` 24/24 (14 existing + 10 new race cases); `useBloomwireCapabilities.spec.js`
  +`capabilitiesLoaded`; focused FE 58/58; ESLint + `vite build` clean; no secrets. Runtime: case A + account-show
  304-cache captured (deployed, authenticated); case B + 20-refresh need the **account-1 admin** session (provided
  session was account-21/amaya) — pending.

### WhatsApp / Meta Graph API version contract → v25.0 — `Open (product code; not merged)`
- **Branch** `fix/bloomwire-whatsapp-graph-api-v25` off `version_1` `e8717b059759da7b090b172c291ad2a33ea08794`.
  Version-only; no behavior change beyond v25.0. Schema: NO · Enterprise: NO (untouched) · webhook router: UNCHANGED.
- **Audit finding:** the Coexistence flow inherited older/implicit Graph API versions — frontend Embedded Signup SDK
  silently used **v22.0** (`WHATSAPP_API_VERSION` never reached the browser → `utils.js` hard-coded fallback); outbound
  message/media used **v24.0**; backend code fallbacks were **v22.0**.
- **Centralization:** new `Whatsapp::GraphApi::DEFAULT_VERSION = 'v25.0'` (BE) + `DEFAULT_WHATSAPP_GRAPH_API_VERSION`
  (FE). Referenced by `Whatsapp::FacebookApiClient` (token exchange, WABA/phone queries, debug_token, register,
  subscribed_apps), `Whatsapp::HealthService`, `Whatsapp::Providers::WhatsappCloudService` (message + media),
  `initializeFacebook`/`setupFacebookSdk`. `dashboard_controller` now feeds `WHATSAPP_API_VERSION` (default v25.0) to
  `window.chatwootConfig.whatsappApiVersion`. Ops overrides preserved; runtime DB `WHATSAPP_API_VERSION` already v25.0.
- **NOT changed:** webhook router (routes by `phone_number_id`, version-independent); Enterprise calling
  (`WHATSAPP_CALLING_API_VERSION_FALLBACK`); template-management surface (`business_account_path` + CSAT stay `v14.0`,
  separate follow-up); Instagram/Messenger/Shopify/reports.
- **TDD (RED→GREEN):** FE `whatsapp/specs/utils.spec.js` RED-proven (4/5 on old v22.0) → v25.0; BE
  `facebook_api_client_spec` asserts all Graph URLs `/v25.0/` and never `/v1x|20–24/`; `whatsapp_cloud_service_spec`
  message/media `/v25.0/` (+ override); `dashboard_controller_spec` asserts `whatsappApiVersion: 'v25.0'`. WhatsApp
  backend regression **278/0** (Enterprise call-flow **pre-existing** 6/6 fail on clean base, unrelated). RuboCop +
  ESLint clean; vite build ok; no secret in diff.
### Coexistence onboarding callback fix — Stage-B transition hang — `Open (product code; not merged)`
- **Branch** `fix/bloomwire-coexistence-callback-transition` off `version_1` `e8717b059759da7b090b172c291ad2a33ea08794`
  (base verified). **Frontend-only.** Schema/migration: NO · backend/endpoint/router change: NO · Meta/WhatsApp/HTTP call
  added: NO · Enterprise: NO · `WHATSAPP_CONFIGURATION_ID`: unchanged (`0643fcdbad9c`) · DEV deploy: pending review.
- **Root cause (proven):** owner `useWhatsappEmbeddedSignup.js`. Its run Promise settled only when BOTH the FB.login
  `authCode` and the postMessage `businessData` were present; if exactly one Meta signal arrived and the other never
  did, it **never settled** → `isAuthenticating` stayed true → `BloomwireWhatsapp.vue`'s `await runEmbeddedSignup()`
  hung → `PROCESSING` loader forever → **no** create POST (matches the incident: 0 backend create requests, account 21
  at 0 Inbox/Channel/Setup, Meta sent 2 webhooks, router fail-closed 200). **Stage B.**
- **Smallest fix:** a **bounded completion timeout** armed only once the FIRST signal arrives (does not limit time in the
  Meta popup); if the second never arrives within `timeoutMs` (default 60s) the run rejects safely instead of hanging.
  Both arrival orders still resolve once; the `settled` guard keeps duplicate Meta events → one resolution → **one**
  create POST; reject/timeout → caller shows sanitized error, spinner ends, form retryable; account context preserved.
- **TDD (RED→GREEN):** composable spec **14/14** (auth-only + business-only timeouts RED-proven as 5s hangs pre-fix;
  no-spurious-timeout; duplicate→one); caller spec **16/16** (signup reject → safe error + no create dispatch +
  retryable). Backend coexistence specs **20/0** (contract unaffected). ESLint clean; `git diff --check` clean; no
  secret in diff (auth code / token / phone / phone_number_id / WABA ID / Configuration ID / App ID never touched).
- **Follow-up (separate slice, NOT here):** `GET /api/v1/accounts/:id/custom_roles` → 500 `NoMethodError` on
  non-enterprise accounts; independent of the create-POST path, reported separately.

### Phase 17F.3 — Guided TeamMember + InboxMember alignment — `Open (product code; not merged)`
- **Branch:** `feature/bloomwire-phase-17f3-guided-membership-alignment` off `version_1` `e9fcef9` (PR #125; base
  fail-closed verified). **Scope: staff-access alignment only.** **Schema/migration: NO · persistent Inbox↔Team mapping:
  NO · new Category model: NO · WhatsApp onboarding/credentials/callbacks/subscriptions/global-router/routing: UNCHANGED
  · Meta/external call: NONE · Enterprise: NO · DEV deploy: NO · production untouched.**
- **Recorded — Phase 17F.2B DEV runtime PASS:** deployed SHA `e9fcef9`; run `28732366110`; authenticated account-1 admin;
  launcher visible on both eligible rows; account-scoped existing WhatsApp wizard reached (no team/category param);
  Standard + Coexistence reused; zero membership/inbox/channel/setup/contact/conversation/message deltas; no Meta signup;
  **not Gate B PASS**.
- **Server-authoritative (GPT‑5.5 CHANGES REQUIRED fix):** endpoint is **identity-only** — request carries only
  `team_id` + `inbox_id` (`user_ids` removed from strong params + FE payload). Server **recomputes eligibility +
  additive drift from fresh DB state inside the transaction** and adds only server-computed diffs; **never** trusts
  client membership IDs (preview is display-only). Fails closed (422) for **unrelated / ambiguous / unlinked / stale**;
  cross-account → 404. One shared algorithm extracted to `Bloomwire::CategoryInboxDerivation` (used by BOTH overview +
  alignment; overview output unchanged).
- **Helper decision:** existing `team_members` + `inbox_members` are independent HTTP calls (separate transactions) →
  partial completion possible → local-only, admin-only, feature-gated helper `Bloomwire::CategoryInboxAlignment`
  (`POST /bloomwire/category_inbox_alignment`) wraps both additive `TeamMember` + `InboxMember` writes in ONE
  `ActiveRecord::Base.transaction`; additive, idempotent, account-scoped, no schema, no persisted mapping.
- **Atomicity boundary (corrected):** membership writes are **database-atomic** (full rollback on failure). The stock
  `InboxMember after_create` round-robin (local Redis `LPUSH`) is **outside the DB transaction** and can survive a
  rollback; it self-heals from `inbox.inbox_members` via `InboxRoundRobinService` (`reset_queue unless validate_queue?`).
  Upstream callback **not modified**. No Meta/HTTP/external call.
- **Frontend:** "Align staff access" only on a linked/derived inbox with drift for a category-admin (agents/feature-OFF/
  ambiguous → fail closed). `MembershipAlignmentDialog.vue` previews current + additive diff (display-only); Cancel = no
  write; **Confirm sends only `{team_id, inbox_id}`** with a double-submit guard; success refreshes overview; failure safe.
- **Validation (RED→GREEN):** backend request spec **19/0** (no client-user_ids authority; server recompute; bidirectional;
  stale-safe; unrelated/ambiguous/unlinked fail-closed; cross-account 404; database-atomic rollback; Redis boundary; no
  mapping; no external); overview regression **15** unchanged; RuboCop clean; Vitest categoryInboxes **4 files/54** (incl.
  double-submit); ESLint clean; `git diff --check` clean; no secrets; no schema. Safe DTO `{id,name}` only.
- **Status: 17F.3 IMPLEMENTED (staff-access alignment only).** Not customer-onboarding cert; full Gate B still required
  before production/customer go-live. Do not merge/deploy/run Meta/onboard/touch fixture — awaiting GPT-5.5 review.

### Phase 17F.2B — Category → "Add WhatsApp Inbox" launcher — `Merged (PR #125, merge SHA e9fcef9) + DEV runtime PASS`
- **Branch:** `feature/bloomwire-phase-17f2b-category-add-whatsapp-launcher` off `version_1` `0c3f32d` (PR #124; base
  verified fail-closed). Frontend-only. **Product code: YES (frontend) · schema/migration: NO · backend endpoint: NO ·
  new Category model/mapping: NO · membership writes: NO · duplicate wizard: NO · per-customer webhook: NO · credential
  mutation: NO · Enterprise: NO · real Meta: NO · DEV deploy: NO · production: untouched.**
- **Owner-approved dependency change (recorded here in the implementation PR):** 17F.2B may begin **before** full Gate B;
  **full Gate B / real Meta Coexistence certification remains mandatory before production/customer go-live and before
  any end-to-end customer-onboarding certification claim.**
- **What:** `categoryInboxes/Index.vue` — each Category/Team row shows an **"Add WhatsApp Inbox"** `router-link` that
  deep-links to the existing wizard (`settings_inboxes_page_channel`/`sub_page=whatsapp`) via
  `useAccount().accountScopedRoute`. No writes, no backend call, no Category↔Inbox mapping (alignment = 17F.3).
- **Gating:** `canAccessCategoryAdmin && canSelfServeManagedWhatsapp` (agents + feature-OFF hidden); route guard +
  backend remain authoritative. Return refreshes the overview via the existing `onBeforeMount` fetch.
- **Validation (supporting only; Gate B still required for customer cert):** RED→GREEN Vitest `categoryInboxes/Index.spec.js`
  **20 passed** (8 new; 4 RED pre-fix); categoryInboxes regression 3 files/35; ESLint clean; `git diff --check` clean;
  no secrets. Files: `categoryInboxes/Index.vue`, `categoryInboxes/specs/Index.spec.js`, `i18n/.../categoryInboxes.json`.
- **Status: 17F.2B IMPLEMENTED (frontend launcher).** Not a customer-onboarding certification. Do not merge/deploy/run
  Meta/start 17F.3 — awaiting GPT-5.5 exact-head review.

### Phase 17F.2A — DEV secure config + Meta Embedded Signup launch/cancel preflight — `Pending docs-only PR`
- **Base:** current latest `version_1` = `9fe522fbd5221ae301b7b133276c6c193eb65019` (PR #123 docs-only merge). This
  ledger update is docs-only and must not deploy. It does not change product code, tests, schema, workflows, runtime
  config, DEV, production, roles, memberships, inboxes, channels, setups, credentials, or the existing WhatsApp fixture.
- **Secure DEV config evidence:** `WHATSAPP_APP_ID` present = true; `WHATSAPP_CONFIGURATION_ID` present = true;
  `platform_ready=true`. The two existing blank DEV `InstallationConfig` rows were updated securely; no duplicate rows
  were created; values were never printed, logged, or exposed. Rails and Sidekiq SHA remained
  `6894d93459cdba0fbc503a7d68b4f54b42a54571`; PostgreSQL and Redis were preserved; production was untouched.
- **Browser result:** **Meta Embedded Signup launch/cancel preflight PASS — account 1**.
- **Browser evidence:** authenticated legitimate account-1 administrator; `canCreateInbox=false`;
  `canSelfServeManagedWhatsapp=true`; normal UI path Settings → Inboxes → Add Inbox → WhatsApp Business → Coexistence;
  real Facebook OAuth popup launched for WhatsApp Business App onboarding; popup was cancelled before any number selection
  or onboarding completion; no onboarding persistence POST occurred.
- **Zero-delta evidence:** account-scoped `Channel::Whatsapp` 1 → 1, `Inbox` 1 → 1, `Bloomwire::WhatsappSetup` 1 → 1;
  global counts remained 1 / 1 / 1; Contact 6 → 6; Conversation 6 → 6; Message 116 → 116; Sidekiq retry 0 → 0; Sidekiq
  dead 49 → 49; relevant application requests had no 5xx.
- **No mutation / no exposure:** no credential, subscription, callback, routing mapping, contact, conversation, message,
  inbox, channel, or setup mutation occurred; no secret or full identifier was recorded.
- **Boundary:** this is **not Gate B PASS**, not Embedded Signup completion PASS, not new Coexistence inbox creation or
  routing proof. Full Gate B / Real Meta Coexistence certification remains **BLOCKED / DEFERRED** because no second
  distinct controlled WhatsApp Business number is available. **17F.2B remains NOT STARTED**. The existing WhatsApp fixture
  remains do-not-touch; the popup preflight must not be rerun for this docs-only PR.

### Phase 17F.2A — Managed WhatsApp onboarding entry restoration — `Merged + DEV PASS for UI/runtime scope` — PR #122 (merge SHA `6894d93459cdba0fbc503a7d68b4f54b42a54571`; deploy run `28699117487`)
- **Branch / merge / deploy:** `fix/bloomwire-phase-17f2a-whatsapp-onboarding-entry` merged into `version_1` via PR #122
  at `6894d93459cdba0fbc503a7d68b4f54b42a54571` after exact-head review of
  `eb01e0f44c9b5c96f905dfb37230a72d830c3853`. DEV deploy run `28699117487` completed successfully for that merge SHA.
  Production untouched.
- **Exact PASS wording:** **Phase 17F.2A product implementation: PASS. DEV deployment: PASS. Gate A: PASS. Phase 17F.2A
  UI/runtime scope: DEV PASS.** This PASS is limited to restoring the managed WhatsApp New Inbox entry, eliminating the
  blank Add Inbox surface, preserving admin/agent authorization behavior, and preserving feature-OFF / stock-compatible
  behavior. It is **not** a real Meta customer onboarding PASS and **not** Coexistence certification.
- **Root cause fixed:** `settings/inbox/Index.vue` New Inbox entry was gated on `isAdmin && canCreateInbox` (managed ⇒
  false; `canSelfServeManagedWhatsapp` not imported); `settings/inbox/ChannelList.vue` filtered all cards with **no empty
  state** when both caps were false ⇒ blank `/settings/inboxes/new`.
- **Fix shipped:** `Index.vue` entry is now `isAdmin && (canCreateInbox || canSelfServeManagedWhatsapp)` (stock/native
  unchanged; agents denied). `ChannelList.vue` renders a **safe unavailable state** (reused `INBOX_MGMT.MANAGED_BY_OPS`)
  + **Back** action (`goBack` → `settings_inbox_list`) instead of blank; managed WhatsApp card still routes to the
  existing wizard (`settings_inboxes_page_channel`/`whatsapp`); no other provider cards in managed mode; no secrets.
- **Automated validation:** RED→GREEN Vitest 22 passed (Index 9 + ChannelList 13; 3 RED pre-fix); inbox-settings
  regression 8 files/76 tests; ESLint clean; `git diff --check` clean; no secrets; CI green before merge.
- **Gate A deployed DEV evidence (owner-approved):** authenticated DEV normal navigation confirmed Settings → Inboxes,
  New Inbox visible for the authorized administrator, click-through to non-blank `/settings/inboxes/new`, WhatsApp
  Business card visible, Standard + Coexistence options visible, no provider secret fields exposed, cancel/back without
  creating records, safe unavailable state instead of blank where applicable, agent denied, feature-OFF/stock-compatible
  behavior preserved, and real Meta/WhatsApp calls = **0**.
- **Real Meta Coexistence onboarding certification (formerly Gate B):** **BLOCKED / DEFERRED**. After the secure DEV
  config update, `WHATSAPP_APP_ID` present = true, `WHATSAPP_CONFIGURATION_ID` present = true, and
  `platform_ready=true`; the remaining blocker is that no second distinct controlled WhatsApp Business number is available
  for the original new-inbox isolation contract. The only controlled DEV number is already connected to the existing
  **“Bloomwire WA Dev”** inbox, the same number cannot create a second `Channel::Whatsapp` because of the unique
  phone-number constraint, and destructive removal/migration of the existing inbox is not approved. This is a
  readiness/test-fixture limitation, **not a confirmed product defect**.
- **Zero Gate B / certification resource deltas:** the two existing blank DEV public-identifier `InstallationConfig` rows
  were updated securely and no duplicate rows were created. The launch/cancel preflight made no credential, subscription,
  callback, routing mapping, contact, conversation, message, inbox, channel, or setup mutation; no new fixture was
  created; production was untouched.
- **Do-not-touch fixture rule:** do **not** delete, migrate, rename, detach, modify, or re-onboard the existing
  “Bloomwire WA Dev” inbox, `Channel::Whatsapp`, `WhatsappSetup`, credentials, conversations, messages, contacts, or
  routing mapping. Do **not** bypass the unique phone-number constraint.
- **Existing Standard inbox global-router supporting evidence:** completed on DEV against the existing **“Bloomwire WA
  Dev”** Standard inbox at Rails/Sidekiq SHA `6894d93459cdba0fbc503a7d68b4f54b42a54571` and labelled exactly
  **“Existing Standard inbox global-router supporting evidence only”**. One owner-assisted inbound text
  (`BW-STD-SMOKE-20260704T1100Z`) routed through the global webhook router to the existing masked `phone_number_id`
  (`****8541`) with one persisted target conversation/message path, zero duplicates, zero cross-account/inbox leakage,
  zero 401/no-handoff/5xx, and zero matching Sidekiq retry/scheduled jobs. One outbound reply
  (`BW-STD-SMOKE-REPLY-20260704T1108Z`) used the normal `Messages::MessageBuilder` → `SendReplyJob` path, reached final
  status `read`, retained a masked source id, and had zero duplicate/cross-account/retry/error findings. Local and public
  health remained 200, pending migrations remained false, Rails/Sidekiq SHA remained unchanged, and fixture counts for
  `Channel::Whatsapp`, `Inbox`, and `Bloomwire::WhatsappSetup` remained one each.
- **Certification boundary:** this smoke supports the existing Standard inbox global-router path only. It is **not**
  Coexistence signup PASS, Embedded Signup PASS, new inbox creation PASS, new-inbox isolation PASS, Real Meta Coexistence
  onboarding certification, full Gate B PASS, or proof that the platform is ready for customer Coexistence onboarding.
- **Future certification hard gate:** Real Meta Coexistence onboarding certification remains mandatory before production
  enablement of customer Coexistence onboarding, before the first real customer Coexistence onboarding, and before any
  claim that Bloomwire Coexistence onboarding is end-to-end certified. It remains **BLOCKED / DEFERRED** until a second
  distinct controlled WhatsApp Business number is available for the original new-inbox isolation contract; restored public
  identifiers and `platform_ready=true` are necessary evidence, not Gate B PASS.
- **17F.2B dependency:** **17F.2B remains NOT STARTED**. It must not begin until the existing full Gate B / Real Meta
  Coexistence certification passes. This docs-only status-evidence correction does **not** change that contract. Any
  future dependency change requires a separate explicit owner-approved contract-change decision and GPT-5.5 review.

### Phase 17F.2 — Guided "Add WhatsApp Inbox to Category" — Discovery & Contract — `Merged` — PR #121 (merge SHA `ada23bc`, docs‑only; NO implementation)
- **Goal:** evaluate + define the contract for the guided "admin picks a category → Add WhatsApp Inbox (Standard/Coex)
  → reuse existing wizard → assign staff → return to overview" journey, using existing primitives only.
- **Deliverable:** `docs/bloomwire/phase-17f2-guided-inbox-category-flow-discovery.md` (architecture map w/ file:line
  evidence, request/response contracts, transaction boundaries, failure/rollback matrix, security/authz matrix, feature
  ON/OFF, UX + backend + frontend orchestration, flow‑shape decision, partial‑completion handling, slices, RED→GREEN
  tests, risks, non‑goals, final recommendation).
- **CORRECTION (owner‑observed DEV blocker — doc §0):** authenticated DEV `/settings/inboxes/list` shows **NO New Inbox
  button**; `/settings/inboxes/new` renders a **blank channel list** ⇒ a business admin **cannot add a second WhatsApp
  inbox via the normal UI on DEV**. Multi‑inbox backend alone is **not** a product PASS; 17F.1 MCP did not cover the
  *Inbox list → New Inbox → WhatsApp card → Standard/Coexistence* click journey; **managed onboarding entry is NOT DEV
  PASS**. Root cause (source‑verified): `settings/inbox/Index.vue` gates New Inbox on `isAdmin && canCreateInbox`
  (ignores `canSelfServeManagedWhatsapp`), and `settings/inbox/ChannelList.vue` filters all cards with **no safe empty
  state** when both caps are false. Effective managed cap needs admin + `MODE_ENABLED` + `PRIVACY_HARDENING` +
  `RESTRICT_NATIVE_WHATSAPP_SETUP` + `MANAGED_WHATSAPP_ONBOARDING` (do not assume which DEV flag is missing; inspect
  server‑side in deploy phase).
- **Key finding:** the *category launcher* is feasible **without a new mapping and without a Meta‑spanning transaction**
  (setup = Meta **before** one `ActiveRecord::Base.transaction`; membership admin‑only/transactional/idempotent/
  reversible; overview surfaces partial completion) — **but** the launcher is **not** the first slice; the onboarding
  **entry** must be restored first.
- **Recommendation (revised by owner-approved status-evidence corrections):** current status correction authorizes
  documentation of the 17F.2A DEV pass, supporting smoke, secure public-identifier config update, and launch/cancel
  preflight only. **17F.2B remains NOT STARTED** and must not begin until the existing full Gate B / Real Meta Coexistence
  certification passes. Any future change to that dependency requires a separate explicit owner-approved contract-change
  decision and GPT-5.5 review. Persistent `Inbox↔Team` mapping remains parked (owner-approved ADR).
- **17F.2A / certification split:** **Gate A PASS** validates the 17F.2A product scope (New Inbox entry restored,
  `/settings/inboxes/new` non-blank, admin/agent behavior preserved, feature-OFF/stock-compatible behavior preserved,
  no real Meta calls). Former Gate B is reclassified as **Real Meta Coexistence onboarding certification** with status
  **BLOCKED / DEFERRED** until a second distinct controlled WhatsApp Business number is available. `WHATSAPP_APP_ID` and
  `WHATSAPP_CONFIGURATION_ID` are now present and `platform_ready=true`, but restored public identifiers are necessary
  evidence only, not Gate B PASS. This certification remains the required gate before 17F.2B can start unless a separate
  explicit owner-approved contract-change decision and GPT-5.5 review changes that dependency later.
- **Governance corrections:** 17F.0 relabelled Merged (PR #118, `6c0ab8c`); SESSION‑LOG distinguishes `version_1` tip
  `bb2a3d7` vs DEV runtime SHA `7bc59c7`.
- **Validation:** docs‑only; no product code/tests/schema/deploy; no real Meta/WhatsApp/Shopify; production untouched.

### Phase 17F.1 — Read‑only "Categories & Inboxes" admin overview — `Merged` — PR #119 (approved head `024b35a`; merge SHA `7bc59c74ba5f96fc7ed394b0335dc216d4ab6529`; `version_1` tip `7bc59c7`; deployed to DEV in 17F.1D; product code: YES, gated)
- **Goal:** ship the administrator‑only, **read‑only** "Categories & Inboxes" overview from 17F.0 Option C, using
  existing Chatwoot primitives only (**no schema, no new Category entity, no writes**), gated by a new master‑gated
  feature so OFF ⇒ stock Chatwoot.
- **Feature flag:** `BLOOMWIRE_CATEGORY_ADMIN_UI` (`Bloomwire::Features` SUB_FEATURES; master‑gated; **not**
  privacy‑dependent). OFF ⇒ no route/page/API/nav.
- **Backend:** `GET /api/v1/accounts/:id/bloomwire/category_inbox_overview` →
  `Api::V1::Accounts::Bloomwire::CategoryInboxOverviewController#show` (`before_action :ensure_category_admin_ui!`
  → `head :not_found` when OFF; then `check_admin_authorization?` → Pundit not‑authorized for agents). Read‑only DTO
  from `Bloomwire::CategoryInboxOverview`: categories = **Teams**; every WhatsApp inbox is classified exactly once as
  **linked** (one matched Team), **ambiguous** (multiple matched Teams), or **unlinked** (zero matched Teams), using
  membership overlap only (**no persisted Inbox↔Team link**). The DTO includes safe staff/collaborator summaries
  (**id + name only**), matched team metadata, relationship status, WhatsApp `connection_mode` standard/coexistence,
  `Bloomwire::WhatsappSetup#setup_status`, safe `not_configured` fallback when no setup row exists, and drift for linked
  pairs. **provider_config/tokens/secrets never serialized.** Route: singular `resource :category_inbox_overview,
  only: [:show]` under the existing `namespace :bloomwire`.
- **Frontend:** admin‑only Settings page `dashboard/routes/dashboard/settings/categoryInboxes/` (`Index.vue` +
  `InboxSummary.vue`) reusing `SettingsLayout` / `BaseSettingsHeader` / `components-next/label/Label.vue`;
  **deep‑links** to `settings_teams_edit`, `settings_inbox_show`, and `agent_list`; loading / empty / error + retry
  states; explicit ambiguous and unlinked sections; API client `api/bloomwire/categoryInboxOverview.js`. Gating: new
  opt‑in capability `canAccessCategoryAdmin` (`Bloomwire::Capabilities.for` = `managed_capability(admin,
  Features.enabled?(:category_admin_ui))` → `useBloomwireCapabilities`, default false), route guard
  `categoryInboxes.routeGuards.js` (`redirectIfCategoryAdminDisabled` → dashboard unless capability `true`), sidebar nav
  entry (conditional spread), i18n `en/categoryInboxes.json` + `SIDEBAR.CATEGORY_INBOXES`.
- **Permissions (backend‑enforced):** admin+ON ⇒ 200 (all account teams/inboxes); agent+ON ⇒ **401 (no payload)**;
  OFF ⇒ **404 (any role)**; account‑scoped (no cross‑account). Frontend hiding is UX only.
- **What was NOT changed:** no schema/migration; no writes / membership‑sync / persistent mapping / new Category
  entity; contact visibility, inbox assignment, Standard/Coexistence setup controllers, native
  `/whatsapp/authorization`, and the global webhook router untouched; Enterprise untouched.
- **Tests (TDD, RED→GREEN):** backend `spec/requests/bloomwire/category_inbox_overview_spec.rb` **15/15** with RED
  coverage for linked/ambiguous/unlinked relationship states, setup fallback, and no external calls; frontend
  `categoryInboxes/specs/` targeted specs **24/24** with RED coverage for ambiguous section, retry action, Agents
  deep‑link, relationship labels, and setup fallback label.
- **Validation:** scoped category/capability Vitest **39/39**; curated Bloomwire RSpec **627 examples, 0 failures,
  1 pending**; full Vitest **3661 passed**; full RuboCop **2700 files inspected, no offenses**; full ESLint **0 errors**
  (existing warnings only); docs governance + secret scan + migration/schema diff guard clean; `git diff --check` clean.
- **Runtime proof (LOCAL full stack; Chrome DevTools MCP; synthetic local‑only account):** Admin+ON page rendered the
  Categories & Inboxes nav, linked row with drift, ambiguous section with matched teams, unlinked section,
  Standard/Coexistence labels, setup statuses including **Not configured**, Team/Inbox editor links, and the Agents
  deep‑link. Network proof: `GET …/category_inbox_overview` returned **200** with safe DTO fields only. Agents link
  navigated to `/settings/agents/list`. Console had no application errors. Screenshot saved locally at
  `/tmp/pr119-category-inboxes-runtime.png`. Cleanup: synthetic account/users/inboxes/teams/setups/sessions verified
  zero; local Rails/Vite stopped; **no production; DEV untouched.**
- **Security:** no secrets exposed; no provider‑credential mutation; **no live Meta/WhatsApp/Shopify**; no Enterprise.
- **Residual / parked:** Category↔Inbox is derived (convention‑only); a persistent Inbox↔Team mapping/data‑tag is
  **out of scope** and needs a separate owner‑approved design (17F.0). Read‑only slice; guided add/assign flow later.

### Phase 17F.1D — DEV deploy + authenticated runtime validation — `Done (PASS)` — deploy run `28694180364`
- **Merge:** PR #119 approved head `024b35a` → **merge SHA `7bc59c7`** (2‑parent merge; parents `6c0ab8c` + `024b35a`;
  admin merge, branch policy `REVIEW_REQUIRED` only, CI 8/8 green; self‑approve blocked → pinned approval comment).
  `version_1` tip = `7bc59c7`.
- **Deploy:** `deploy-dev.yml` (manual; prod hard‑blocked), `env=dev ref=version_1 run_migrations=true skip_smoke=false
  prune=false`. Run `28694180364` SUCCESS. Rails + sidekiq `/app/.git_sha = 7bc59c74ba5f96fc7ed394b0335dc216d4ab6529`
  (SSH‑verified); local + public health 200; rails+sidekiq recreated; postgres/redis preserved (not recreated); no
  pending migrations; no 5xx. Dev deployed SHA now `7bc59c7`.
- **DEV flags (dev only):** `BLOOMWIRE_MODE_ENABLED=true` + `BLOOMWIRE_CATEGORY_ADMIN_UI=true`; capability admin=true /
  agent=false. Never touched in prod.
- **Admin+ON (PASS):** real account 1 (2 categories + ambiguous, deep‑links, read‑only, 1 overview GET, 0 console, no
  secrets, DTO secret‑scan false) + synthetic account (full matrix: 7 categories, ambiguous+unlinked sections, 2 drift,
  3 Standard/2 Coexistence badges, statuses pending/configured/ready_for_webhook/blocked/not_configured, Team+Inbox+Agents
  deep‑links, read‑only, isolation, desktop/tablet/mobile). Masked screenshots.
- **Agent+ON (PASS):** curl agent token → own‑account 401 + cross‑account 401 (0 overview keys; labels control 200);
  browser → nav absent, route redirect (0 rows, no flash), overview fetch 401. Existing agent paths unchanged (untouched).
- **Feature OFF (PASS):** admin overview 404; existing labels/inboxes/teams/agents 200; browser nav absent + redirect +
  existing screens render; restored ON + re‑verified.
- **Counts:** 5xx=0 · console errors=0 (only the deliberate agent 401 probe) · graph.facebook.com=0 · myshopify.com=0 ·
  overview mutations=0 · secrets=0.
- **Cleanup:** synthetic account+users+tokens removed (0 left); real account 1 + admin preserved; DEV feature left ON;
  browser session cleared; no real Meta/WhatsApp/Shopify; production untouched. **Phase 17F.1 COMPLETE; 17F.2 NOT started.**

### Phase 17F.0 — Multi‑WhatsApp‑Inbox / Category Admin UI Discovery — `Merged` — PR #118 (merge SHA `6c0ab8c`, docs‑only)
- **Goal:** design the Bloomwire admin experience for multiple WhatsApp inboxes + business categories/departments +
  staff, using existing Chatwoot primitives only (no new Category entity).
- **Deliverable:** `docs/bloomwire/phase-17f0-multi-inbox-category-admin-ui-discovery.md` (executive summary, arch map,
  code evidence w/ paths, runtime UX findings, permission matrix, Mermaid data‑flows, gap analysis, UX options +
  recommendation, implementation slices, TDD plan, risks, non‑goals, go/no‑go).
- **Key finding:** `Inbox` ↔ `Team` are independent (no FK / no `team_id` / no join). Category = Team + Inbox(es) is
  **convention‑only** (parallel `InboxMember` + `TeamMember`; auto‑assign intersects `inbox ∩ team`). Backend admin/agent
  isolation already enforced (policies + Bloomwire gates, all ON on DEV).
- **Locked permission model (backend‑enforced; doc §5a):** admin manages **all** inboxes + Standard/Coexistence managed
  setup + members/teams/staff; agent sees **only** `InboxMember` inboxes + reachable conversations/contacts and
  **cannot** create a WhatsApp inbox / access Standard‑Coexistence setup / modify provider config / bypass via direct
  API (managed embedded‑signup controllers enforce `check_admin_authorization?`). 17F.1 overview is admin‑only (shows all
  inboxes); agent selectors stay assigned‑inbox‑only; no agent WhatsApp‑setup CTA/route. Frontend hiding alone is not
  sufficient.
- **Recommendation:** **Option C (Hybrid)** — compose + deep‑link existing editors + guided dual‑membership add flow.
  Slices 17F.1–17F.6; **Go for 17F.1** (read‑only overview, zero schema risk).
- **Validation:** docs‑only; no product code; no migration/schema; no deploy; no real Meta/WhatsApp/Shopify; production
  untouched. Method: 4 read‑only sub‑agents + authenticated DEV admin runtime (MCP, PHI masked).

### Phase 17E.4D — Dev Deploy + Authenticated Runtime Validation — `Done (PASS)` — deploy run `28684004558`
- **Deploy:** `deploy-dev.yml` (manual; prod hard-blocked) deployed `version_1 @ 4525bea` to **dev only**
  (`run_migrations=true` no-op — 0 pending in `3c45720..4525bea`; `prune=false`; postgres/redis volumes preserved).
  Run `28684004558` **SUCCESS**. Post-deploy: `/app/.git_sha = 4525bea`, local+public health 200, login renders,
  rails+sidekiq up, pg/redis reachable, **no pending migrations**, no 5xx. **Dev deployed SHA now `4525bea`.**
- **DEV gate:** `BLOOMWIRE_RESTRICT_AGENT_CONTACT_VISIBILITY=true` enabled on dev only (InstallationConfig; cache
  cleared; resolves true); **kept enabled** — never enabled/modified in prod.
- **Authenticated runtime smoke (gate ON) — PASS:** admin regression (existing session) — dashboard, WhatsApp
  Standard+Coexistence (Available now), inbox list, conversations, contacts list/search, no 500/secret/Meta.
  17E.4 targeted (synthetic account; Shopify stubbed, no real egress; in-process real controller stack) —
  contact merge agent in-scope 200 / oos mergee+base 404 (intact) / admin 200; conversation-create agent in-scope
  200 / oos 404 (0 side-effects) / admin 200; Shopify agent oos **422, 0 client calls (no egress)** / in-scope 200
  (stub) / admin 200; isolation regression unassigned conv 401 (never 500), oos contact 404 (never 500), agent
  index only assigned-inbox contact, admin all, seam agent=in-scope only.
- **Evidence:** 0 console errors · 0 HTTP 5xx · 0 `graph.facebook.com` · 0 real `myshopify.com` · masked screenshot.
- **Cleanup:** all synthetic records destroyed (0 remaining); no temp token files; real data unchanged
  (account 1 still 5 contacts). No production; no real Meta/WhatsApp/Shopify.

### Phase 17E.4 — Contact ID hardening — `Merged` — PR #116 (merge SHA `4525bea6baf8c17315436982f0d70106508b9c57`; `version_1` tip `4525bea`; deployed to dev in 17E.4D; product code: YES)
- **Goal:** close the direct, ID-based contact-visibility gaps deferred in 17E.2/17E.3 (contact merge,
  conversation-create contact lookup, Shopify orders contact lookup) using the existing
  `Bloomwire::ContactVisibility.scope(account:, user:)` seam.
- **Implementation (backend, gated; one line each):**
  1. `Actions::ContactMergesController#contacts` → seam (out-of-scope base/mergee → `RecordNotFound` → 404).
  2. `ConversationsController#contact` → `seam.find(params[:contact_id])` (out-of-scope → 404; inbox authz unchanged).
  3. `Integrations::ShopifyController#contact` → `seam.find_by(id:)` (out-of-scope → nil → existing `validate_contact`
     renders 422 and halts BEFORE any external Shopify call → no egress; no extra product code needed).
- **Gate ON:** gated agent blocked from all three out-of-scope paths. **Gate OFF == stock Chatwoot.** **Admin**
  never narrowed. **CSAT** stays admin-only/protected (product code NOT touched).
- **What was NOT changed:** CSAT product code; DB schema/migrations; frontend; routes; native
  `/whatsapp/authorization` / `Whatsapp.vue`; global webhook router. No new category entity; no duplicate store.
- **Tests:** `hardening_followup_inventory_spec.rb` rewritten characterization → hardening (**15 ex**); RED-proven
  via `git stash` (the 4 out-of-scope block cases fail on stock code, incl. Shopify `get` ×2). Shopify no-egress
  asserted (`shopify_client` never `:get`; no `myshopify.com` request).
- **Security (Safe DTO):** no secrets · no provider-credential mutation · no live Meta/WhatsApp · no Enterprise.
- **Validation:** new **15/15**; suite **73/73** (+ conversations_controller regression **80/80**); RuboCop clean;
  `git diff --check` clean; no migration/schema; secret scan clean. No deploy · no production · dev `3c45720`.

### Phase 17E.3D — Dev Validation Release — `Done (dev deploy)` — no PR (workflow dispatch)
- **What:** deployed `version_1 @ 3c45720` to **dev only** via `deploy-dev.yml` (manual; prod hard-blocked;
  `run_migrations=true` no-op — 0 pending; `prune=false`; postgres/redis volumes preserved).
- **Result:** SUCCESS — `/app/.git_sha = 3c45720…`; local + public health 200; rails + sidekiq up; postgres
  untouched (`Up 6 days`). **Dev deployed SHA is now `3c45720204fe4c57528dfd8d1ef43f8a34674612` (`3c45720`)**
  (was `9b09f9e`). No production; no secrets; no real Meta.

### Phase 17E.3 — Owner-operated runtime E2E with mocked Meta — `Merged` — PR #115 (merge SHA `3c45720204fe4c57528dfd8d1ef43f8a34674612`; `version_1` tip `3c45720`; test-only)
- **Goal:** owner-operated runtime E2E proving the full multi-WhatsApp-inbox + customer/agent-visibility workflow
  works end to end through the REAL runtime stack, with **mocked Meta only** (no real Meta, no production, no deploy).
- **Scope:** TEST-ONLY. Two integration specs under `app/spec/integration/bloomwire/`; **no product code, no
  migration/schema, no frontend, no routes.** Meta stubbed at the seam (`Whatsapp::TokenExchangeService` /
  `PhoneInfoService` / `FacebookApiClient` + `Bloomwire::GlobalWhatsappConfig`); `WebMock.disable_net_connect!`
  blocks egress (an example asserts no `graph.facebook.com` call).
- **Coverage — `multi_inbox_runtime_e2e_spec.rb` (22 ex):**
  - **Flow 1** admin creates Inbox 1 (Standard) + Inbox 2 (Coexistence) via mocked embedded signup; each maps to its
    own `Channel::Whatsapp` + `Bloomwire::WhatsappSetup`; safe DTO (no token/api_key); non-admin forbidden.
  - **Flow 2** signed inbound webhook routes `phone_number_id_1`→Inbox 1, `phone_number_id_2`→Inbox 2; unknown +
    crossed pnid fail closed (create nothing); router is connection_mode-agnostic; no Meta egress.
  - **Flow 3** category agent lists/opens only its own inbox's conversations (cross-open → 401); admin sees both.
  - **Flow 4** contact isolation gate ON: list/search/show + sub-resource 404 + bulk label add/remove scoped; admin
    unaffected; feature OFF == stock.
  - **Flow 5** UI-sanity at the API: no cross-inbox inbox/contact leakage to a category agent.
- **Coverage — `hardening_followup_inventory_spec.rb` (5 ex, 1 pending):** characterizes (does NOT fix) the KNOWN,
  DEFERRED 17E.2 gaps with the gate ON: **contact merge** + **conversation-create** are agent-reachable + unscoped
  (current behavior); **CSAT report** is admin-only (protected); **Shopify orders** is statically reachable +
  unscoped but outside the mocked runtime (needs an integration hook + external stub) — documented, pending. A
  CONTROL example proves the gate is active (17E.2 enumeration path still closed). No NEW leak beyond the 17E.2 set.
- **What was NOT changed:** no product/app code; DB schema/migrations; frontend; routes; native
  `/whatsapp/authorization` / `Whatsapp.vue`; global webhook router.
- **Security:** no secrets (all fake) · no provider-credential mutation · no live Meta/WhatsApp (mocked) · no
  Enterprise code touched.
- **Owner-operated browser E2E:** no Capybara/system-spec harness exists → CI coverage is the request-level runtime
  E2E; a browser walkthrough (Playwright/Chrome DevTools) is owner-operated (checklist in SESSION-LOG). No
  screenshots produced (owner-operated).
- **Validation:** new **27 examples, 0 failures, 1 pending**; regression **109 examples, 0 failures, 1 pending**;
  RuboCop clean; `git diff --check` clean; secret scan clean; migration/schema guard empty. No deploy · no
  production · no real Meta · dev remains `9b09f9e`.

### Phase 17E.2 — Contact isolation & UI/permission polish — `Merged` — PR #114 (merge SHA `d98f7d8080fb4bd7f7e46745b7f6ac373b798ade`; `version_1` tip `d98f7d8`; product code: YES)
- **Goal / decision:** resolve the 17E.0/17E.1 caveat that stock Chatwoot contact list/search is account-wide.
  A business **agent** may only list/search/open contacts **reachable through their assigned inboxes** (via
  `contact_inboxes`); **admins see all**; a **shared** contact (linked to ≥2 inboxes) is visible to agents of any
  of those inboxes; conversation isolation stays the primary enforcement. **Gated** by
  `BLOOMWIRE_RESTRICT_AGENT_CONTACT_VISIBILITY` (master AND-gated) — **OFF == stock Chatwoot** (invariant preserved).
- **Implementation (backend, gated; product code YES):**
  1. `Bloomwire::Features.restrict_agent_contact_visibility?` + new SUB_FEATURE toggle.
  2. `Bloomwire::ContactVisibility.scope(account:, user:)` — single seam: `account.contacts` for admin / stock /
     non-User; for a gated agent, `contacts.where(id: contacts.joins(:contact_inboxes).where(contact_inboxes:
     { inbox_id: user.inboxes(account) }).select(:id))` (subquery — distinct-safe, composes with sort/paginate/includes).
  3. Wired into every agent-facing READ path: `ContactsController#index/search/active/show` (via `resolved_contacts`,
     `search`, `active`, `fetch_contact`), `Contacts::FilterService#base_relation`, global `SearchService#filter_contacts`,
     `contacts/base_controller#ensure_contact` (sub-resources → 404 out-of-scope).
  4. **PR #114 review blocker fix — bulk contact WRITE path.** `BulkActionsController#enqueue_contact_job` now
     filters `ids` through `Bloomwire::ContactVisibility.scope` BEFORE enqueueing `Contacts::BulkActionJob`, so a
     gated agent cannot bulk add/remove labels on an out-of-scope `contact_id`. Out-of-scope IDs are dropped
     (silently, matching stock `where(id:)`); admins / gate-OFF pass through unchanged; delete stays admin-only via
     the existing `authorize(Contact, :destroy?)`. Filtered controller-side so unsafe raw IDs never reach the async job.
- **Ownership / source-of-truth:** contact_inboxes is the existing link table (no new entity, no duplicate store).
  Admin visibility, conversation/inbox scoping, and the global webhook router are untouched.
- **Security (Safe DTO):** agents can no longer enumerate other categories' contacts; admins unchanged; no secrets;
  no live Meta; no Enterprise code touched.
- **What was NOT changed:** DB schema/migrations; frontend; routes; native `/whatsapp/authorization` / `Whatsapp.vue`;
  webhook router; export/import (already admin-only).
- **Known limitation (deferred):** direct ID-based access via contact **merge**, **CSAT** report inclusion,
  **Shopify** integration, and **conversation-create** contact lookup are not scoped here (mutations/reports/
  integrations needing a known contact_id, not enumeration) — candidates for a hardening follow-up / 17E.3 review.
  **Bulk contact label add/remove — previously part of this gap — is now scoped (PR #114 blocker fix, item 4).**
- **Validation:** new `contact_visibility_spec` 5/5 + `contact_isolation_spec` **20/20** (was 13/13; +7 bulk-action
  cases); bulk-path regression `bulk_actions_controller_spec` + `contacts/bulk_action_service_spec` +
  `contacts/bulk_action_job_spec` + `contacts_controller_spec` = **76/76**; RED proof: reverting the controller
  (`git stash`) fails exactly the 3 "does-not-mutate-B" cases, re-applying is GREEN. RuboCop clean; `git diff --check`
  clean; no migration/schema; secret scan clean. No deploy · no production · dev `9b09f9e`.

### Phase 17E.1 — Multiple WhatsApp Inbox backend contract tests — `Merged` — PR #113 (merge SHA `5df9f9d74a59057e099e82c1e5471bfff0c8e449`; `version_1` tip `5df9f9d`; test-only)
- **Goal:** turn the 17E.0 discovery into automated, regression-locked backend coverage of "one account owns
  multiple WhatsApp inboxes." **Test-only** — RSpec added; **no product code changed** (existing code already
  satisfies the contract). No migration/schema; all Meta stubbed (no real Meta/WhatsApp).
- **Coverage:**
  - **Standard + Coexistence services** — two different numbers → two distinct `Channel::Whatsapp` + `Inbox` +
    `Bloomwire::WhatsappSetup` (same account, distinct channel/inbox ids); each routes to its own inbox; duplicate
    `phone_number` → `:phone_number_taken`; duplicate `phone_number_id` → `:phone_number_id_conflict` (second
    channel rolled back); coexistence keeps `connection_mode=coexistence`.
  - **Standard + Coexistence request endpoints** — admin registers two numbers as two inboxes; duplicate → 422.
  - **Global router** — two numbers in ONE account each resolve to their own inbox; unknown pnid → nil; crossed
    pnid/display → fail-closed; Standard + Coexistence coexist (routing is connection_mode-agnostic).
  - **NEW category contract** (`spec/services/bloomwire/multi_whatsapp_inbox_category_contract_spec.rb`) —
    Category = Team + Inbox: ConversationFinder + ConversationPolicy prove a category agent lists/opens ONLY its
    own inbox (admin sees both); team-filtered assignment rejects a cross-category (team-2-only) assignee.
- **Files:** extended `whatsapp_embedded_signup_service_spec.rb`, `whatsapp_coexistence_embedded_signup_service_spec.rb`,
  `webhooks/whatsapp_router_spec.rb`, `requests/…/embedded_signups_spec.rb`, `requests/…/coexistence_embedded_signups_spec.rb`;
  new `multi_whatsapp_inbox_category_contract_spec.rb`.
- **Validation:** targeted `rspec` (6 files) = **73 examples, 0 failures**; RuboCop clean; `git diff --check` clean;
  secret-scan clean. No deploy · no production · dev remains `9b09f9e`.
- **Deferred:** contacts-isolation decision + any UI/permission changes → **17E.2**; runtime E2E → **17E.3**.

### Phase 17E.0 — Multiple WhatsApp Inbox per Account discovery + ADR-0009 — `Merged` — PR #112 (merge SHA `83496896fcc7bcaa6ca076dbd2f346ee5eb4f7bc`; `version_1` tip `83496896`)
- **Goal:** lock the Bloomwire **multiple WhatsApp inbox per account** business model (5 categories × 1 WhatsApp
  number × 10 agents) before the 17E hardening slices. Docs-only; no code, tests, route, migration, deploy, or Meta call.
- **Deliverables:** `docs/bloomwire/whatsapp-multi-inbox-discovery.md` (executive verdict + evidence with file:line +
  caveats + phased plan + open questions) and `projects/bloomwire-chatwoot-platform/docs/adr/0009-multi-whatsapp-inbox-category-model.md`.
- **Verdict:** **SUPPORTED.** `Bloomwire::WhatsappEmbeddedSignupService#persist` creates a new `Channel::Whatsapp`
  + `Inbox` + `Bloomwire::WhatsappSetup` per call, blocking only a duplicate `phone_number` (global) — Coexistence
  inherits it. Schema has **no per-account WhatsApp uniqueness** (`channel_whatsapp.phone_number` unique is global;
  `bloomwire_whatsapp_setups.account_id` is a non-unique index; `phone_number_id` unique is global-partial).
  `canSelfServeManagedWhatsapp` (`lib/bloomwire/capabilities.rb`) is a role/managed-mode guard, not count-based, so
  the WhatsApp Add-Inbox card never disappears. `Bloomwire::Webhooks::WhatsappRouter.resolve` routes by
  `phone_number_id` → one setup → its own inbox (fail-closed).
- **Model:** Category = **Team + Inbox**; number = `Channel::Whatsapp` + `Inbox` + `Bloomwire::WhatsappSetup`;
  employee = `User`/agent; category staff = TeamMembers + InboxMembers; message = `Conversation`; assignment =
  `assignee_id` / `team_id`. Native round-robin + team-filtered assignment already support it.
- **Permission/visibility:** agent inbox/conversation access is backend-scoped (`InboxPolicy::Scope`,
  `ConversationFinder`, `Conversations::PermissionFilterService`, `ConversationPolicy`). Admin sees all.
- **Caveats:** (1) **contacts** index/search is account-wide in stock Chatwoot (contact-record leak across
  categories; conversations stay isolated) — decision deferred to 17E.2; (2) **no multi-inbox-per-account tests** yet
  — added in 17E.1.
- **Next:** 17E.1 backend contract tests → 17E.2 UI/permission + contacts-isolation decision → 17E.3 owner-operated
  runtime E2E (mocked Meta) before customer go-live.
- **Validation:** docs-only; `git diff --check` clean; no app/test/route/migration/workflow change. No deploy · no
  production · dev remains `9b09f9e`.

### Phase 17D.3 — WhatsApp Business App Coexistence frontend enablement — `Merged` — PR #111 (merge SHA `ea305792dc83f864f8e1374ce0ca832f99f7d8f9`; approved head `d9810b7`; `version_1` tip `ea30579`)
- **Goal (Product Truth):** *User expects* to connect an **existing** WhatsApp Business App number from the
  customer WhatsApp setup screen. *Current system* showed the Coexistence card **disabled / "Coming soon"* (17C.3).
  *Done means* the card is selectable and drives Meta Embedded Signup → the dedicated coexistence endpoint,
  creating the managed inbox, with the Standard flow untouched.
- **Scope:** **frontend only** — `BloomwireWhatsapp.vue`, `whatsappChannel.js`, `store/modules/inboxes.js`,
  `i18n/locale/en/inboxMgmt.json`, specs (`BloomwireWhatsapp.spec.js`, new `whatsappChannel.spec.js`).
- **What changed:**
  1. **Card enabled** — removed the disabled/"Coming soon" state (teal "Available now" badge + "Connect existing
     number" CTA `@click=startCoexistence`); prerequisites list unchanged.
  2. **Shared flow** — `flow` ref (`standard | coexistence`) reuses the same credential-free form +
     `useWhatsappEmbeddedSignup` composable (which already handles `FINISH_WHATSAPP_BUSINESS_APP_ONBOARDING` and
     returns only `code` / `business_id` / `waba_id` / `phone_number_id`).
  3. **Coexistence endpoint** — new `WhatsappChannel.createBloomwireCoexistenceEmbeddedSignup` →
     `POST /api/v1/accounts/:id/bloomwire/whatsapp/coexistence_embedded_signup`, via new Vuex action
     `inboxes/createBloomwireWhatsAppCoexistenceEmbeddedSignup` (mirrors the Standard action's safe-DTO contract).
  4. **Standard unchanged** — still posts to `…/bloomwire/whatsapp/embedded_signup`; regression-locked by a test
     asserting Standard never dispatches the coexistence action.
- **Ownership / Source-of-truth:** the backend endpoint (17D.1) remains the enforcement boundary and DTO owner;
  the frontend only wires the card to it. No new client-side state or store of chat/message data.
- **Security (Safe DTO):** UI exposes **no** App Secret / Verify Token / Webhook URL / API token /
  `provider_config`; the coexistence API test asserts the payload is exactly the 4 non-secret fields. **No live
  Meta/WhatsApp calls** (SDK + `postMessage` mocked). No Enterprise code touched.
- **What was NOT changed:** native `/whatsapp/authorization` + `Whatsapp.vue`; `canSelfServeManagedWhatsapp` gate
  in `ChannelFactory` / `useBloomwireCapabilities` (role guards intact — agents/staff still blocked); backend
  controllers/services/routes; webhook router/job; DB schema/migrations.
- **Validation:** Vitest — component 15/15, new API client 4/4, hook 10/10; regression `inboxes/actions` 20/20,
  `ChannelFactory` 9/9, `ChannelList` 8/8, `useBloomwireCapabilities` 9/9. ESLint clean (`--max-warnings=0`);
  `inboxMgmt.json` valid JSON. No deploy · no production · dev remains `9b09f9e`.
- **Residual risks / parked:** real coexistence Meta Embedded-Signup = owner-operated browser E2E (no automated
  real-Meta); **17C.4** verify / go-live UX still parked.

### Phase 17D.2 — WhatsApp Business App Coexistence webhook proof — `Merged` — PR #109 (merge SHA `4a57564d7c1fbc54aeafbf9049f61b5b7a8b0795`; approved head `fbbbe14`; `version_1` tip `4a57564`)
- **Goal:** prove the existing global webhook router (ADR-0005) + stock `Webhooks::WhatsappEventsJob` safely handle
  Coexistence traffic before frontend enablement (17D.3). Backend/webhook proof only; Coexistence card stays
  disabled/"Coming soon".
- **Proven:**
  1. **Routing** — router keys on `phone_number_id` + channel alignment, never `connection_mode`; a coexistence
     channel routes identically; wrong pnid fails closed; account-scoped.
  2. **`smb_message_echoes`** — already handled via the **outgoing** echo path
     (`IncomingMessageWhatsappCloudService(outgoing_echo: true)`); not a duplicate inbound; account/inbox-scoped.
  3. **`smb_app_state_sync`** — was unhandled (fell through to inbound processing) → added a **safe-ignore** guard
     (`app_state_sync_event?` + `handle_app_state_sync`): redacted content-free log, no inbound processing, no
     message/conversation, no crash.
  4. **No duplicate storage** — existing Chatwoot processing only; no app-side chat/message tables.
- **Only production change:** `app/app/jobs/webhooks/whatsapp_events_job.rb` (the app-state-sync guard). Routing +
  echo required no code change. Proof doc: `docs/bloomwire/whatsapp-coexistence-webhook-proof.md`.
- **Security/DTO:** no secrets logged; fake payloads only; no real Meta/WhatsApp; native `/whatsapp/authorization`
  + `BloomwireWhatsapp.vue` untouched.
- **Not done:** 17D.3 frontend enablement.
- **Validation:** targeted rspec router + events-job = **43 ex, 0 fail**; broader webhook regression = **58 ex, 0
  fail**; RuboCop clean. No migration · no deploy · no production · no real Meta · no frontend enablement.

### Phase 17D.1 — WhatsApp Business App Coexistence backend contract — `Merged` — PR #107 (merge SHA `ebdcba2831fd40330eaefd5a6dfe87f97a00b867`; approved head `67b63cd`; `version_1` tip `ebdcba2`)
- **Goal:** the backend for **"Connect Existing WhatsApp Business App" (Coexistence)** — the option the 17C.3
  wizard shows disabled/"Coming soon". Backend contract only; the UI card stays disabled until a later frontend
  phase (17D.3).
- **What:**
  - **Endpoint** `POST /api/v1/accounts/:account_id/bloomwire/whatsapp/coexistence_embedded_signup`
    (`Api::V1::Accounts::Bloomwire::Whatsapp::CoexistenceEmbeddedSignupsController`), under the **same** namespace
    as the 17C.2 `embedded_signup` route. Admin-only; 404/inert unless native WhatsApp restricted AND
    `managed_whatsapp_onboarding`; `Current.account`-scoped; safe DTO + sanitized errors. Native
    `/whatsapp/authorization` untouched.
  - **Service** `Bloomwire::WhatsappCoexistenceEmbeddedSignupService < Bloomwire::WhatsappEmbeddedSignupService`:
    inherits the full safe 17C.2 seam (fail-closed readiness + encryption guard; token exchange + phone info +
    **`subscribe_app_to_waba` only**, never override/setup_webhooks; token via `WhatsappCredentialWriter`;
    non-secret `WhatsappSetup` mapping). Overrides only: channel `provider_config['connection_mode']='coexistence'`
    (source still `bloomwire_managed`) + `connection_mode: 'coexistence'` on the channel/setup DTO sections.
- **Security/DTO:** no credentials collected; token only in encrypted `provider_config`; response never shows
  token/api_key/provider_config; masked number is the source of truth; sanitized `:meta_error`.
- **Not done:** 17D.2 webhook/coexistence proof; 17D.3 frontend enablement (Coexistence card stays disabled);
  no `WhatsappSetupRequest` removal.
- **Validation:** service + request specs (Meta stubbed) — **14 targeted examples, 0 failures**; RuboCop clean;
  route resolves. No real Meta · no frontend enablement · no migration · no deploy · no production · no secrets.

### Phase 17C.3 — Customer frontend WhatsApp connection wizard — `Merged` — PR #104 (merge SHA `bf81c7c62f5c9f8621142250e37b47e51b86ed82`; approved head `1bc432f`; `version_1` tip `bf81c7c`)
- **Goal:** the customer UI on the 17C.2 endpoint — Settings → Inboxes → Add Inbox → WhatsApp Business → **choose a
  connection method** → register the number with Meta → ready inbox. Managed mode only; native flows untouched;
  number registration only (no agents step — Chatwoot's inbox-agent management owns that).
- **What:**
  - **Connection-choice screen (first step):** "Connect WhatsApp Channel" → two options: **Connect Existing
    WhatsApp Business App** (badge Coexistence) **disabled / "Coming soon"** with its prerequisites listed and
    **no backend call** (no coexistence backend yet); and **Register New Number** (badge Standard, "Available
    now") which continues to the number-registration form.
  - `useBloomwireCapabilities` exposes **`canSelfServeManagedWhatsapp`** (opt-in, **default FALSE** — hidden in
    stock; shown only on explicit server `true`).
  - `ChannelList` shows the WhatsApp card in managed mode; `ChannelFactory` renders `BloomwireWhatsapp.vue` in
    place of native WhatsApp when the capability is granted. Agents never see it.
  - `BloomwireWhatsapp.vue` (Standard flow): optional inbox-name + number confirmation (NO App Secret / Verify
    Token / Webhook / API token / provider_config) → **Connect with Meta / Register WhatsApp number** → posts only
    the non-secret signup credentials to the 17C.2 endpoint (`inboxes/createBloomwireWhatsAppEmbeddedSignup` +
    `WhatsappChannel.createBloomwireEmbeddedSignup`). Success = safe DTO (inbox id/name, masked number, Ready) +
    Open inbox / Inbox settings; failure = one sanitized generic message. Custom name applied best-effort via the
    existing inbox-update API (no endpoint contract change).
- **Security/DTO:** no credentials collected; response/DOM never show token/api_key/provider_config; registered
  number = backend/Meta source of truth (masked), not the typed value; raw Meta/server errors never surfaced;
  Coexistence card triggers no network call.
- **Not done:** Coexistence **backend** (card is UI-only/disabled until then); 17C.4 verify/go-live; retire parked
  `WhatsappSetupRequest`.
- **Validation:** Vitest **36 tests** (capability default-false; factory/list gating; **choice screen: two
  options, Coexistence disabled/coming-soon + 8 prerequisites + no backend call, Register New Number continues**;
  wizard no-agents + no-credentials + sanitized error + posts-only-credentials); ESLint clean; i18n JSON valid; no
  real Meta (SDK + store mocked). No migration · no deploy · no production · no backend/native change.

### Phase 17C.2 — Dedicated Bloomwire WhatsApp Embedded Signup endpoint + service — `Merged` — PR #102 (merge SHA `84481ed1eeceadf91860f03a1515b01bb7d7abd4`; approved head `c8bd01e`; `version_1` tip `84481ed`)
- **Goal (ADR-0008):** the customer-side Embedded-Signup backend on the 17C.1 foundation — no native flow touched,
  no frontend wizard yet, no real Meta calls in tests.
- **Endpoint:** `POST /api/v1/accounts/:account_id/bloomwire/whatsapp/embedded_signup`
  (`Api::V1::Accounts::Bloomwire::Whatsapp::EmbeddedSignupsController`). Admin-only; **404/inert** unless native
  WhatsApp restricted AND `managed_whatsapp_onboarding` enabled; `Current.account`-scoped; safe DTO + sanitized errors.
- **Service `Bloomwire::WhatsappEmbeddedSignupService`:** fail-closed preflight (platform readiness via
  `GlobalWhatsappConfig#platform_ready`; **encryption required outside dev/test before token storage**; code/waba
  present) → Meta steps (token exchange + phone info + **`subscribe_app_to_waba` only** — global router; never
  `override_waba_callback`/`subscribe_waba_webhook`/`channel.setup_webhooks`) → atomic DB: `source:'bloomwire_managed'`
  Cloud channel shell (`save(validate:false)` → no live `validate_provider_config`, no auto webhook, no template
  sync), encrypted token via `WhatsappCredentialWriter`, `Inbox`, and `ready_for_webhook` mapping via
  `WhatsappSetupCreator`. Meta failures → sanitized `:meta_error`, persist nothing.
- **Security:** token only in encrypted `Channel::Whatsapp#provider_config`; mapping holds only non-secret ids;
  DTO/response never include token/api_key/provider_config; Meta error bodies never logged/returned.
- **Not done (later slices):** frontend wizard (17C.3), verify/go-live (17C.4), manual fallback; `WhatsappSetupRequest` still parked.
- **Validation:** service spec (Meta stubbed) + request spec (authz/denials/safe-DTO); native regression 31 ex 0
  fail; **full Bloomwire scope 700 examples, 0 failures (1 pre-existing pending)**; RuboCop clean. No real Meta ·
  no migration · no deploy · no production · no secrets.

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
