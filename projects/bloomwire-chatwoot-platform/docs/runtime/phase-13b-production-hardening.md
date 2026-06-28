# Phase 13B — WhatsApp Production Hardening (before live certification)

Status: **IMPLEMENTATION COMPLETE (internal hardening; no real Meta, no deploy).** This phase prepares the app
so Phase 13C can safely run the human-operated live Meta outbound/status/template certification. It follows the
Phase 13A audit. All identifiers in this doc are masked; no secret values appear.

Branch: `feature/bloomwire-phase-13b-whatsapp-production-hardening` → PR to `version_1` (not merged here).

## Scope delivered

### 13B.1 — provider_config secret-at-rest (ADR-0006 Option A)
- `Channel::Whatsapp` now declares `encrypts :provider_config if Chatwoot.encryption_configured?`, mirroring
  every sibling channel secret. `provider_config` holds the Meta Cloud API access token (`api_key`) and the
  auto-generated `webhook_verify_token`.
- **Safe by construction:** `provider_config` is never queried at the DB level (routing keys off the
  `phone_number` column + `Bloomwire::WhatsappSetup.phone_number_id`), so non-deterministic encryption does not
  break inbound routing or any lookup. The static map confirmed **zero** SQL queries on `provider_config`
  sub-keys.
- **OFF == stock:** with no AR encryption keys configured the declaration is skipped → plaintext jsonb exactly
  as before; `support_unencrypted_data` (already global) reads legacy rows until re-saved.
- **Proof:** `spec/models/channel/whatsapp_provider_config_encryption_spec.rb` — round-trip runs with and
  without keys; with ephemeral keys the "no plaintext at rest" + legacy-plaintext backfill examples run and
  pass. ADR-0006 status updated to *Accepted — implemented*; production rollout (provision keys + backfill)
  remains a deliberate ops step recorded in the ADR.

### 13B.2 — outbound transient retry / terminal failure policy
- A transient send failure (HTTP **429 / 5xx**) now raises `Whatsapp::Providers::TransientError` instead of
  being marked failed immediately. `SendReplyJob` retries it within a **bounded** policy (3 attempts, 3s wait,
  mirroring `AgentBots::WebhookJob`). After the budget is exhausted the message is marked **failed** with a
  status-only error (no secret), preserving the terminal-failure contract.
- **Permanent** errors (e.g. 4xx auth/invalid) keep the existing `failed` + redacted `external_error` path.
- Campaign (`Whatsapp::OneoffCampaignService`) and CSAT (`CsatSurveyService`) already rescue per item, so they
  continue uninterrupted (no double-send, no campaign abort).
- **Proof:** provider-level transient/terminal specs + an end-to-end retry test (persistent 503 → retried 3× →
  failed; transient-then-success → `wamid` stored). No real Meta (WebMock-blocked).

### 13B.3 — configurable Graph API version
- Retired the legacy hard-coded `v13.0` on the outbound **message** + **media** paths. Introduced
  `DEFAULT_API_VERSION = 'v24.0'` (the version already used for attachments) and an `api_version` reader
  overridable via `WHATSAPP_CLOUD_API_VERSION`. `phone_id_path` and `media_url` use it.
- `business_account_path` (template-management surface, mirrored by `Whatsapp::CsatTemplateService`) keeps its
  own version and is intentionally out of scope.
- **Proof:** default/override/URL-correctness specs; the access token never appears in the generated URL.

### 13B.4 — docs reconciliation
- `phase-3a-whatsapp-cloud-e2e-baseline.md`: §9 inbound rows now point to the **Phase 10B** real-inbound PASS;
  outbound/status/template/privacy rows are explicitly **Phase 13C** live targets (still `TODO`). No live
  outbound/status/template PASS is claimed.
- `ADR-0006`: status moved to *Accepted — Option A implemented in 13B.1*, with the remaining production ops
  steps (key provisioning + backfill) called out.

## 13B.5 — Non-WhatsApp channel secret exposure: DECISION

**Question:** should Phase 13B also scrub non-WhatsApp provider secrets from the account inbox API?

**Finding (from the Phase 13A audit).** `Bloomwire::ProviderConfigScrubber` scrubs `provider_config` secrets
(`api_key`, `webhook_verify_token`, and any `secret|token|password|api_key` key) in
`app/views/api/v1/models/_inbox.json.jbuilder` when privacy hardening is ON. Other channels keep their secrets
in **dedicated columns** (e.g. `Channel::Email#imap_password/smtp_password`, `Channel::TwilioSms#auth_token`,
`Channel::Api#hmac_token/secret`) that are rendered from their own attributes in the same jbuilder and are
**not** covered by the provider_config scrubber. Those columns are already **encrypted at rest** (Rails 7
`encrypts`), and in managed mode business admins **cannot create or update** those channels
(`Bloomwire::RestrictsProviderSetup`); only a pre-existing channel could still surface its credential to an
account admin via the API.

**Decision: Option B — out of Phase 13B scope, documented as a prerequisite.** Bloomwire is WhatsApp-first; the
managed WhatsApp-commerce flow does not use email/Twilio/API channels, and their *setup* is already blocked in
managed mode. Extending the scrubber to every channel now would be scope creep with regression risk to stock
Chatwoot behavior and no benefit to the WhatsApp certification path.

**Required before those channels are enabled in managed mode** (tracked, not done here):
- Extend the privacy-hardening DTO scrub (or block the fields) to cover non-WhatsApp channel secret columns in
  `_inbox.json.jbuilder` (email IMAP/SMTP, Twilio `auth_token`/`account_sid`, API `hmac_token`/`secret`), and
- add request-spec coverage proving those values are hidden for business admins when privacy hardening is ON.

This keeps Bloomwire OFF == stock and does not change non-WhatsApp behavior in this phase.

## Not done in 13B (by design)
- No real Meta / WhatsApp / Graph calls; no live outbound/status/template PASS (that is **Phase 13C**).
- No AR encryption key provisioning or production backfill (deliberate ops step, ADR-0006).
- No deploy, no schema/migration change, no secret values committed.

## Next: Phase 13C (human-operated, real Meta)
Execute the live-hop runbook (`phase-12g-live-hop-readiness-package.md`): re-confirm inbound on the current
SHA, then prove outbound session send, status `sent/delivered/read/failed`, and out-of-window template send;
record masked evidence into `phase-3a-…` §9. Requires real WABA + number + physical phone + public HTTPS
callback, and the ADR-0006 encryption keys provisioned before any real customer token is stored.
