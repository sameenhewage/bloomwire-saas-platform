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

- **Bloomwire** is a **WhatsApp-first SaaS product** built on the WhatsWay / Chatwoot-derived **OSS base**.
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
| 15F | Owner-only Email Settings (DB SMTP + templates) | #78 | Implemented (encryption parked) |
| 15F.1 | Send-from-Template composer (owner-only) | _pending_ | Implemented |
| 15G | CI/CD foundation (PR CI + manual Dev/Staging deploy) | _pending_ | Implemented (infra/docs only) |

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

### Phase 15F.1 — Send-from-Template composer — `Implemented` — PR _pending_
- **Discovery first:** the prior "Send Test Email" button on the Email Templates tab only **linked** to the
  Test Email tab (a fixed sample/test send). There was **no** way to fill a template's variables and send the
  rendered template — so the composer was implemented (no behavior was silently changed).
- Owner-only **"Send from Template"** composer on the Email Templates tab: 9 fields — recipient, the 6
  `{{variables}}`, plus button label/link — with an **"Update preview"** round-trip (server-rendered final
  preview using the entered values) and a **"Send Email"** action.
- **Real send** through the existing DB-backed SMTP settings, reusing `Bloomwire::SendTestEmailService`
  (extended: `subject:` / `body:` / `require_enabled:` / `noun:`) and `Bloomwire::EmailTestMailer`.
  `{{placeholders}}` are interpolated before sending; the CTA becomes a `label: url` line.
- **Honest + enabled-gated:** blocks when the recipient is blank, SMTP is incomplete, **or outbound email is
  disabled** (`require_enabled: true`); the Send button is disabled until SMTP is ready. **Never fakes
  success.** The SMTP password is never rendered or logged (service sanitizes/filters).
- **Access:** owner-only via the existing `Bloomwire::RequiresPlatformOwner` gate on both controllers.
- **Tests:** **62 examples, 0 failures** for the Bloomwire email suite (48 prior + 14 new) — owner can send,
  non-owner blocked, missing recipient blocked, incomplete SMTP blocked, disabled SMTP blocked, placeholders
  replaced, password never in the response, final-preview round-trip. RuboCop clean on changed Ruby.
- **Not changed:** no WhatsApp/Meta/provider credentials or code, no Enterprise code, no `BusinessOwner`, no
  `users.type` for business roles, no chat/message tables, Devise/password-reset mailers untouched, no new
  dependencies, no migrations.
- **Residual:** composer sends **plain text** (rendered body + CTA line), not the branded HTML shell shown in
  the preview; SMTP password remains plaintext-at-rest (Phase 15F debt, §8); Office365 SMTP AUTH may still be
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
| Per-message email delivery logging (Phase 15F) | `Parked` | The Email Logs tab shows the last test-email result only; full per-message logging is a follow-up. |

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
