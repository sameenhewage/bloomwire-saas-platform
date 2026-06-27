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

## The seven toggles in scope for the backend security boundary

| Toggle (InstallationConfig key) | `Features` helper | Effective when | Governs |
|---|---|---|---|
| `BLOOMWIRE_MODE_ENABLED` | `master_enabled?` | (master) | AND-gates **all** sub-features. Master OFF ⇒ everything stock except the SuperAdmin bootstrap page. |
| `BLOOMWIRE_RESTRICT_ACCOUNT_ADMIN` | `restrict_account_admin?` | master ON **and** key ON | PR #43 account control-plane guard. **Scope (post-11B.7B):** `accounts#update` + `webhooks#*` only. Agents/teams management is **no longer** gated here (restored to the business admin in PR #55). |
| `BLOOMWIRE_RESTRICT_PROVIDER_SETUP` | `restrict_provider_setup?` | master ON **and** key ON | PR #44/#46/#47/#48 provider/channel/integration setup, inbox create/update/destroy, register_webhook, hooks/slack/Linear connect; **+ PR #56** all inbox creation (incl. `web_widget`/`api`); **+ PR #58** integrations admin-surface UI route-block (catalog read stays open for runtime). |
| `BLOOMWIRE_RESTRICT_NATIVE_WHATSAPP_SETUP` | `restrict_native_whatsapp_setup?` | master ON **and** key ON | PR #40 native WhatsApp setup guard. |
| `BLOOMWIRE_RESTRICT_BOT_MANAGEMENT` | `restrict_bot_management?` | master ON **and** key ON | **PR #57 (11B.7D)** bot management guard — agent-bot list/show/create/update/destroy/avatar/reset_access_token/reset_secret + inbox-level `agent_bot`/`set_agent_bot`. Not admin-gated (blocks agents too; bot reads expose secrets). |
| `BLOOMWIRE_GLOBAL_WEBHOOK_ROUTER` | `enabled?(:global_webhook_router)` | master ON **and** `privacy_hardening` ON **and** key ON | Global Meta WhatsApp webhook router (ADR-0005). Privacy-dependent (fail-closed). |
| `BLOOMWIRE_PRIVACY_HARDENING` | `enabled?(:privacy_hardening)` | master ON **and** key ON | Secret masking + the prerequisite that unlocks the privacy-dependent managed-data features. |

> `BLOOMWIRE_RESTRICT_BOT_MANAGEMENT` is a **new toggle (Phase 11B.7D)** and, like all toggles, **defaults OFF**
> (master AND-gated by `BLOOMWIRE_MODE_ENABLED`).

## Dev-validated state (11B.7R + exit gate, `a8023a78`)

Managed-mode toggles ON on `dev.unecast.com`:
`MODE_ENABLED · RESTRICT_ACCOUNT_ADMIN · RESTRICT_PROVIDER_SETUP · RESTRICT_NATIVE_WHATSAPP_SETUP ·
RESTRICT_BOT_MANAGEMENT` = `true` (plus `GLOBAL_WEBHOOK_ROUTER` / `PRIVACY_HARDENING` effective for the
WhatsApp router from the earlier 11B.5BR baseline).

- **`BLOOMWIRE_RESTRICT_BOT_MANAGEMENT` on dev is ON via `InstallationConfig` (DB) only — it is NOT in the
  server `.env`.** It was enabled during 11B.7R/exit-gate validation (the toggle defaults OFF). **If the dev DB
  is reseeded it will reset to OFF** unless it is also added to the server `app/.env`. Persisting it in `.env`
  is the follow-up for a permanently bots-managed dev.

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
