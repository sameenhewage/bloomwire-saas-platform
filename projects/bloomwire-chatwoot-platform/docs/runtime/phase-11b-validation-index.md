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
- **11B.7** corrects the managed-mode **permission model** — the business owner/admin regains agents/teams
  management + full in-account visibility, while platform/provider/bot/integration **setup** stays Ops-owned.
  Contract + corrected guard map: `../security/business-owner-permission-matrix.md`. Slices **11B.7A–E** land
  as separate PRs; **11B.7R** will add the runtime evidence here once they merge.
