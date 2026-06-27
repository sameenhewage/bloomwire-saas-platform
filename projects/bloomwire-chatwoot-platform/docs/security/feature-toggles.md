# Bloomwire Feature Toggle Reference

Single read seam: **`Bloomwire::Features`** (`app/lib/bloomwire/features.rb`). No scattered `ENV` reads.
Values are stored in `InstallationConfig` (DB) and read via `GlobalConfigService` (DB → ENV fallback).
Flip them from the SuperAdmin-only bootstrap page at **`/super_admin/bloomwire_config`** (reachable with the
master toggle OFF so the feature can be enabled from the UI without out-of-band DB edits).

## Core rules

- **All toggles default OFF.** OFF == stock Chatwoot (tenant-facing).
- **Master AND-gate:** every sub-feature is `false` unless `BLOOMWIRE_MODE_ENABLED` is also ON
  (`Bloomwire::Features.enabled?` / each `restrict_*?` helper checks `master_enabled?` first).
- **Privacy-dependent (fail-closed):** the managed-data sub-features (`global_webhook_router`,
  `managed_whatsapp_onboarding`) additionally require `BLOOMWIRE_PRIVACY_HARDENING` ON — they stay inert
  otherwise.

## The six toggles in scope for the backend security boundary

| Toggle (InstallationConfig key) | `Features` helper | Effective when | Governs |
|---|---|---|---|
| `BLOOMWIRE_MODE_ENABLED` | `master_enabled?` | (master) | AND-gates **all** sub-features. Master OFF ⇒ everything stock except the SuperAdmin bootstrap page. |
| `BLOOMWIRE_RESTRICT_ACCOUNT_ADMIN` | `restrict_account_admin?` | master ON **and** key ON | PR #43 account control-plane guard (`accounts#update`, `agents`, `webhooks`). |
| `BLOOMWIRE_RESTRICT_PROVIDER_SETUP` | `restrict_provider_setup?` | master ON **and** key ON | PR #44/#46/#47/#48 provider/channel/integration setup, inbox create/update/destroy, register_webhook, hooks/slack/Linear connect. |
| `BLOOMWIRE_RESTRICT_NATIVE_WHATSAPP_SETUP` | `restrict_native_whatsapp_setup?` | master ON **and** key ON | PR #40 native WhatsApp setup guard. |
| `BLOOMWIRE_GLOBAL_WEBHOOK_ROUTER` | `enabled?(:global_webhook_router)` | master ON **and** `privacy_hardening` ON **and** key ON | Global Meta WhatsApp webhook router (ADR-0005). Privacy-dependent (fail-closed). |
| `BLOOMWIRE_PRIVACY_HARDENING` | `enabled?(:privacy_hardening)` | master ON **and** key ON | Secret masking + the prerequisite that unlocks the privacy-dependent managed-data features. |

## Dev-validated state (11B.5BR, `582f3d0`)

All six ON: `MODE_ENABLED · RESTRICT_ACCOUNT_ADMIN · RESTRICT_PROVIDER_SETUP · RESTRICT_NATIVE_WHATSAPP_SETUP ·
GLOBAL_WEBHOOK_ROUTER(effective) · PRIVACY_HARDENING(effective)` = `true`.

## Other Bloomwire toggles (not part of this backend-guard boundary)

Defined in `Bloomwire::Features::SUB_FEATURES` but outside the 11B lockdown scope:
`BLOOMWIRE_MANAGED_WHATSAPP_ONBOARDING` (privacy-dependent), `BLOOMWIRE_OUTGOING_GATEWAY`,
`BLOOMWIRE_CUSTOM_BRANDING`. Listed for completeness; not referenced by the guard map.

## Masked-secret keys (privacy hardening)

`Bloomwire::Features::MASKED_SECRET_KEYS` = `WHATSAPP_APP_SECRET`, `BLOOMWIRE_WHATSAPP_GLOBAL_VERIFY_TOKEN` —
never shown in cleartext on SuperAdmin surfaces while privacy hardening is effectively ON (ADR-0003).

## How a guard reads a toggle (pattern)

```ruby
# in a Bloomwire::Restricts* concern
return unless Bloomwire::Features.restrict_provider_setup?   # master AND-gated
# ... optional admin gate / request-scope predicate ...
render_provider_setup_restricted                            # 403 { managed_by_ops: true }
```
