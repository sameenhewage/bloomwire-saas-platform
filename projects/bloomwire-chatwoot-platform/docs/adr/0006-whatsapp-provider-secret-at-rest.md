# ADR-0006 — WhatsApp Provider Secret-at-Rest (decision gate)

- Status: **Proposed — DECISION GATE (no implementation)**. Resolves the secret-at-rest gate flagged in
  ADR-0003 / CONTEXT.md ("encrypt or accept+document").
- Extends: ADR-0001…ADR-0005 (never overrides).
- Scope: inspect where WhatsApp provider secrets live, decide whether the existing repo pattern supports safe
  encryption, and record the decision. **No secrets moved, no schema change, no new secret columns, no
  secret-entry UI, no backfill in this ADR** (Phase 12H hard stop: storage redesign ⇒ record the gate only).

## Context — where WhatsApp secrets are stored/read today

| Secret / value | Sensitivity | Stored | At-rest encryption today | Read by |
|---|---|---|---|---|
| `api_key` (Meta access token) | **secret** | `Channel::Whatsapp#provider_config` (JSONB, `app/models/channel/whatsapp.rb:10`) | **NONE (plaintext JSONB)** | `Whatsapp::Providers::WhatsappCloudService#api_headers` (Bearer), media download, webhook setup |
| `webhook_verify_token` | **secret** | same `provider_config` (auto-gen `SecureRandom.hex(16)`, `whatsapp.rb:125`) | **NONE (plaintext JSONB)** | native `Webhooks::WhatsappController#valid_token?` |
| `WHATSAPP_APP_SECRET` (signature) | **secret** | `InstallationConfig` (DB) / ENV via `GlobalConfigService` | **NONE at rest** (Phase 2A masks on *display* only via `MASKED_SECRET_KEYS`) | native + Bloomwire webhook signature verify |
| `BLOOMWIRE_WHATSAPP_GLOBAL_VERIFY_TOKEN` | **secret** | `InstallationConfig` / ENV | **NONE at rest** (display-masked only) | Bloomwire global router GET verify |
| `phone_number_id`, `display_phone_number`, `waba_id` | **non-secret routing ids** | `provider_config` + `Bloomwire::WhatsappSetup` columns | n/a (non-secret; display-masked in Ops UI per 12E) | router/readiness |

**Key asymmetry.** Every *sibling* channel encrypts its provider secret(s) with **Rails 7 ActiveRecord
Encryption** on dedicated columns, gated on `Chatwoot.encryption_configured?` (`config/application.rb:101`):
`Channel::TwilioSms#auth_token`, `Channel::Instagram#access_token`, `Channel::Tiktok#access_token/refresh_token`,
`Channel::Email#imap_password/smtp_password`, `Channel::FacebookPage#page_access_token/user_access_token`,
`Channel::Telegram#bot_token`, `Channel::TwitterProfile#…`, `Channel::Line#…`, plus `Integrations::Hook#access_token`,
`WebhookSecretable#secret`, and `User#otp_secret`. **`Channel::Whatsapp` is the outlier**: it keeps its secrets
in a plaintext JSONB blob (`provider_config`) and does **not** call `encrypts`.

## Risk
- WhatsApp `api_key` + `webhook_verify_token` are **plaintext at rest** (DB dumps, backups, read replicas, logical
  exports) — unlike every sibling channel. Same for the InstallationConfig-stored global secrets.
- This is acceptable for a controlled **test** number (operator-owned, rotatable) but is **not** an acceptable
  posture for onboarding **real managed customer** WhatsApp credentials at scale.

## Does an approved repo pattern exist?
**Yes** — Rails 7 `encrypts ... if Chatwoot.encryption_configured?` is the established, in-repo pattern. The
question is not "is there a pattern" but "can it be applied to WhatsApp *safely and minimally*."

## Options
- **A — Encrypt the whole `provider_config` JSONB** via `encrypts :provider_config if Chatwoot.encryption_configured?`.
  - Pros: reuses the approved pattern; no schema column change; smallest model diff.
  - Cons/requirements (why it is a gate, not a casual change):
    1. Needs AR encryption **keys provisioned** in the target env (`Chatwoot.encryption_configured?` true).
    2. Existing rows are plaintext ⇒ a **transition** (`config.active_record.encryption.support_unencrypted_data`)
       + a **backfill** (re-save each channel) to re-encrypt — a deliberate data operation.
    3. AR-encryption over a **JSONB** attribute must be verified (it encrypts the serialized value; type +
       `encrypts` interplay needs explicit tests); non-deterministic is fine (WhatsApp `provider_config` is
       **not** queried at the DB level — the router keys off the separate non-secret
       `Bloomwire::WhatsappSetup.phone_number_id` column).
    4. Encrypts non-secret keys too (wasteful but safe).
- **B — Move secrets to dedicated encrypted columns** (`encrypts :api_key`, `:webhook_verify_token`) like siblings.
  - Pros: mirrors sibling channels exactly; clean secret/non-secret separation.
  - Cons: schema migration + data migration out of `provider_config` + refactor of **every** reader
    (`provider_config['api_key']` is read across providers/webhook/setup services) ⇒ large change.
- **C — Accept + document (interim)**: keep current plaintext until keys are provisioned and a deliberate
  rollout is approved.

## Recommendation
**Option A** is the smallest path that reuses the approved pattern and should be the chosen implementation —
**but only as a deliberate, separately-approved slice**, because it requires encryption keys + a
`support_unencrypted_data` transition + a backfill + JSONB-encryption test coverage. Per the Phase 12H hard
stop (storage redesign / backfill ⇒ record the gate), **it is NOT implemented here**. Interim posture: **Option C**
(documented acceptance) for test/non-production credentials only.

## What is blocked until this decision is implemented
- **Production managed onboarding of real customer WhatsApp secrets** at scale (do not load real customer
  `api_key`s into plaintext `provider_config` in production before Option A ships).
- **A secret-entry Ops UI** (architecture "Phase 4" Ops channel creation) — must not accept real Meta
  credentials into plaintext at rest; blocked on Option A.
- **Not blocked:** a single operator-controlled **test-number live hop** (Phase 12G) with the documented
  interim risk (test token, rotatable), since no production customer secret is at rest.

## Decision-gate status
No code, schema, migration, backfill, or secret movement in this ADR. Implementing Option A requires explicit
approval plus a transition + backfill plan and JSONB-encryption tests. This ADR records the gate and the
recommended direction so the choice is deliberate.
