# Phase 11B — Runtime Validation Evidence Index

Consolidated index of the dev-runtime validations for the Phase 11B backend security lockdown. Each `…R`
("runtime") phase validated the corresponding implementation PR on the real stack at **`dev.unecast.com`**
(Contabo testing server; Docker Compose project `app`; data disposable). All evidence is **masked / presence
only** — no secrets were printed.

> Detailed transcripts for the `11B.*R` phases live in their working-session histories; this file is the
> durable consolidation point. Standalone deployment/E2E records also exist:
> `phase-10b-dev-deployment-stabilization.md` and `phase-3a-whatsapp-cloud-e2e-baseline.md`. Operational
> how-to: `../ops/whatsapp-webhook-deployment-runbook.md`.

## Index

| Phase | Validates | Toggle | Validated target | Result |
|---|---|---|---|---|
| **11B.2R** | PR #43 account control-plane (`accounts#update`, `agents#*`, `webhooks#*`) | `RESTRICT_ACCOUNT_ADMIN` | PR #43 (`deee34c`) | **PASS** |
| **11B.3R** | PR #44 provider/channel setup + OAuth callback completion | `RESTRICT_PROVIDER_SETUP` | PR #44 (`fdf2806` + `b0d07ce`) | **PASS** |
| **11B.4BR** | PR #46 external-credential inbox create/update (email/sms/line/telegram/voice) | `RESTRICT_PROVIDER_SETUP` | `c96ac53` (PR #46) | **PASS** |
| **11B.4CR** | PR #47 hooks/Slack/Linear integration-connect + Linear OAuth callback | `RESTRICT_PROVIDER_SETUP` | `bf3357d` (PR #47) | **PASS** |
| **11B.5BR** | PR #48 managed/provider inbox destroy + `register_webhook` | `RESTRICT_PROVIDER_SETUP` | `582f3d0` (PR #48) | **PASS** |

Toggle state during validation (all ON): `BLOOMWIRE_MODE_ENABLED`, `RESTRICT_ACCOUNT_ADMIN`,
`RESTRICT_PROVIDER_SETUP`, `RESTRICT_NATIVE_WHATSAPP_SETUP`, `GLOBAL_WEBHOOK_ROUTER` (effective),
`PRIVACY_HARDENING` (effective).

## 11B.4CR — PR #47 (summary)

Blocked (403 + `managed_by_ops`): `integrations/hooks#create|update`, `integrations/slack#create|update`,
Linear `/linear/callback` (fail-closed **before** token exchange — no Linear hook persisted). Side effects:
no hook created/updated, no inbox created. Allowed/runtime intact: `hooks#process_event`, `slack` reads,
`hooks#destroy`, conversations/contacts reads. Existing guards (PR #43/#44/#46/#40) and SuperAdmin/Ops and
WhatsApp readiness all intact. Deployed on `bf3357d`.

## 11B.5BR — PR #48 (full evidence)

- **Deploy:** `bf3357d → 582f3d0`; image rebuilt `--build-arg GIT_SHA=582f3d0`; **rails + sidekiq recreated
  `--no-deps`** (postgres/redis volumes preserved); `db:migrate` no-op (PR #48 has no migrations);
  `/app/.git_sha = 582f3d0`; internal + external health **200**.
- **Blocked (403 `managed_by_ops`):** DELETE email / sms / line provider inboxes; DELETE the **real managed
  WhatsApp inbox**; `register_webhook` on the real WhatsApp inbox.
- **Side effects:** inbox + channel intact; aggregate inbox count unchanged ⇒ **no `DeleteObjectJob`
  enqueued**; `Bloomwire::WhatsappSetup` intact; `provider_config` unchanged ⇒ **`WebhookSetupService` not
  invoked**.
- **Allowed (stock):** DELETE web_widget / api inbox (200); conversations + contacts reads (200);
  `reset_secret` / `sync_templates` / `health` not blocked; managed WhatsApp inbox readable.
- **Existing-guard regression:** PR #43 `agents#create`, PR #44 `google/authorization`, PR #46 external email
  inbox create, PR #40 native WhatsApp (`managed_request`), PR #47 hooks + slack — all 403. Agent path
  unchanged (cross-account agent token → 401, not `managed_by_ops`).
- **WhatsApp readiness/router:** `status=ready`, `router_handoff_safe=pass`, router resolves setup 1
  (handoff-safe), masked IDs only.
- **SuperAdmin/Ops:** `/super_admin`, `/super_admin/bloomwire_config`, `/super_admin/bloomwire_whatsapp_setups`,
  `/super_admin/bloomwire_whatsapp_setup_requests` all reachable + **auth-gated** (302 → sign_in); sign-in 200.
- **Hygiene:** throwaway fixtures fully cleaned (env restored to accounts=2/users=2/inboxes=1/setups=1);
  no secrets printed; no destructive DB ops; no `.env`/Meta changes; no outgoing WhatsApp.

**Verdict:** all Phase 11B backend lockdowns validated on dev through PR #48. UI hiding (11B.6) may proceed
against `../security/ui-hiding-source-of-truth.md` Group A.

## Phase 11B.6 (UI hiding) + 11B.7 (permission-model correction)

- **11B.6BR / 11B.6CR / 11B.6DR** runtime-validated the UI-hiding PRs on dev — all **PASS**: PR #50
  (capability seam + account control-plane, `f3e3f60`), PR #51 (provider / native-WhatsApp setup, `c5776a8`),
  PR #52 (managed-inbox delete + register-webhook, `3526efa`). Each confirmed the `bloomwire_capabilities`
  payload (no raw `BLOOMWIRE_*`), the backend `403` regressions (`managed_by_ops` / `managed_request`),
  Group-B reads intact, SuperAdmin/Ops auth-gated, and throwaway fixtures cleaned to baseline.

---

## Phase 11B.7 — permission-model correction (MERGED + validated)

11B.7 corrects the managed-mode permission model — the business owner/admin regains agents/teams management +
full in-account visibility, while platform/provider/bot/integration **setup** stays Ops-owned. Contract:
`../security/business-owner-permission-matrix.md`; guard map: `../security/backend-guard-map.md`.

| Slice | PR | Merge SHA | What it does |
|---|---|---|---|
| **11B.7A** | #54 | `ea16eb6` | Account name (and locale/domain/support-email) **readonly/disabled** + managed helper; Save stays hidden. Frontend-only (backend `accounts#update` 403 already enforced by PR #43). |
| **11B.7B** | #55 | `38b46bd` | **Restore** business-admin **agents/teams** management (remove the account-control guard from `AgentsController`); stock Enterprise usage limit preserved (402); `accounts#update` + webhooks stay blocked. |
| **11B.7C** | #56 | `d8099de` | **Block ALL inbox creation** (incl. `web_widget`/`api`) via `restrict_inbox_creation!` + `canCreateInbox`; reads/settings + self-service delete unchanged. |
| **11B.7D** | #57 | `f8138de` | **Bots Ops-owned** — new toggle `BLOOMWIRE_RESTRICT_BOT_MANAGEMENT` (default OFF) + `canManageBots`; blocks agent-bot reads/writes/reset + inbox-level set/disconnect; no secret leak; runtime bot execution untouched. |
| **11B.7E** | #58 | `de42d74` (merge `a8023a78`) | **Integrations Ops-owned** — `canAccessIntegrations` + sidebar hide + route-block; connect/config writes already 403 (PR #47); catalog read intentionally open for runtime. |

### 11B.7R — combined runtime/security validation — **PASS** (`a8023a78`)

Deployed `version_1 @ a8023a78` to `dev.unecast.com` (image rebuilt with GIT_SHA, rails+sidekiq recreated
`--no-deps`, pg/redis volumes preserved, `db:migrate` no-op). `/app/.git_sha = a8023a78`; internal + external
health **200**. Toggles ON: `MODE_ENABLED · RESTRICT_ACCOUNT_ADMIN · RESTRICT_PROVIDER_SETUP ·
RESTRICT_NATIVE_WHATSAPP_SETUP · RESTRICT_BOT_MANAGEMENT` (the bot toggle enabled via `InstallationConfig`,
not `.env`).

- **Capability payload:** all **8** `bloomwire_capabilities` = `false` for the business admin
  (`canManageAccountControlPlane, canManageProviderSetup, canManageNativeWhatsappSetup,
  canDeleteManagedProviderInbox, canRegisterProviderWebhook, canCreateInbox, canManageBots,
  canAccessIntegrations`); **no raw `BLOOMWIRE_*`** in the body.
- **Backend/API:** `accounts#update` 403; inbox create `web_widget`/`api`/`email` 403 `managed_by_ops`,
  `whatsapp` 403 `managed_request`; bot index/show/create/update/destroy/reset 403 (**no `access_token`/
  `secret`/`bot_config` leak**); inbox-level `agent_bot`/`set_agent_bot` 403; integrations hooks/slack write
  403; **integrations catalog read 200** (runtime-open); webhooks 403; **agents create/update/delete allowed**
  (limit 402 preserved); non-admin agent 401; **teams allowed**.
- **UI/MCP:** account fields disabled + Save hidden + managed helper; agents New visible; New Inbox hidden +
  direct website/api create → managed-state; Bots sidebar hidden + direct route managed-state; Integrations
  sidebar hidden + direct route redirect; conversations/contacts render; no console errors.
- **Role matrix:** business admin allowed agents/teams + workspace, blocked setup; agent gains no admin/setup
  + no bot secrets; SuperAdmin/Ops `/super_admin*` **302 → sign_in** (auth-gated, Bloomwire pages unaffected).
- **Cleanup:** throwaway fixtures removed, residue **0**, counts at baseline; no secrets printed; no Meta/
  WhatsApp outgoing; no DB reset / volume removal / `.env` drift.

### Phase 11B Exit Gate / Phase 12 Readiness — code/runtime/security/UI **PASS**

The exit gate re-confirmed (on `a8023a78`): git/PR state (PR #53–#58 merged, 0 open, clean tree), code-level
guard verification (no dead/duplicate/stale guards), runtime (SHA + health + no pending migrations + stable
rails/sidekiq), toggles, capability payload (8/false, no raw toggles), backend/API 403 boundary, UI/MCP, role
matrix, and cleanup — **all PASS**. The gate's **only** blocker was **stale documentation**; this docs-sync
brings the canonical security/runtime docs to the merged reality and resolves that blocker. Phase 11B is then
complete; **Phase 12 = WhatsApp E2E**.
