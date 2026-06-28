# ADR-0006 — WhatsApp Provider Secret-at-Rest (decision gate)

- Status: **Accepted — Option A implemented in Phase 13B.1.** `Channel::Whatsapp` now declares
  `encrypts :provider_config if Chatwoot.encryption_configured?` (commit on `feature/bloomwire-phase-13b-…`).
  The model/code change is done and tested; the **production rollout** (provision AR encryption keys +
  re-encrypt legacy rows) remains a deliberate ops step (see "Remaining for production" below). Originally
  raised as a decision gate resolving ADR-0003 / CONTEXT.md ("encrypt or accept+document").
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

## Recommendation (chosen)
**Option A** — the smallest path that reuses the approved pattern. **Implemented in Phase 13B.1**:
`encrypts :provider_config if Chatwoot.encryption_configured?` on `Channel::Whatsapp`, non-deterministic,
relying on the already-global `support_unencrypted_data = true` transition. JSONB-encryption is covered by
`spec/models/channel/whatsapp_provider_config_encryption_spec.rb` (round-trip with/without keys; "no plaintext
at rest" + legacy-plaintext backfill proven with ephemeral keys). With no keys configured (default), the
declaration is skipped → **OFF == stock plaintext jsonb**, so nothing changes until keys are provisioned.

## Remaining for production (deliberate ops steps — not code)
1. **Provision AR encryption keys** in the target env (`ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY` /
   `…_DETERMINISTIC_KEY` / `…_KEY_DERIVATION_SALT`) so `Chatwoot.encryption_configured?` is true.
2. **Backfill** existing rows by re-saving each `Channel::Whatsapp` so plaintext `provider_config` is
   re-encrypted (a controlled data op; `save!(validate: false)` avoids the remote credential re-check). New
   writes encrypt automatically; `support_unencrypted_data` keeps legacy rows readable until then.

## What is unblocked vs still gated
- **Unblocked (code):** the encryption itself ships in the Phase 13B PR.
- **Still gated on the ops steps above:** loading **real customer** `api_key`s at scale and any secret-entry
  Ops UI in production — do this only after keys are provisioned and the backfill has run.
- **Not blocked:** a single operator-controlled **test-number live hop** (Phase 12G/13C) with the documented
  interim risk (test token, rotatable), since no production customer secret is at rest.

## Decision-gate status
**Resolved.** Option A is implemented in code (Phase 13B.1) with JSONB-encryption tests. No schema change, no
new secret columns, no secret-entry UI, and no automatic backfill in code (backfill is the deliberate ops step
above). Production rollout proceeds once the encryption keys are provisioned.
