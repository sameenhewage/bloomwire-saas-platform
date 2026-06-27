# Tier-B Existing-Ops Decisions (Phase 11B.5C)

Product/security decisions for the existing-channel operations that mutate provider/channel/integration state
but may be legitimate self-service or runtime behavior. Source-grounded against `version_1 @ 582f3d0`.
These are **not** currently backend-blocked (that is PR #43–#48; see `backend-guard-map.md`).

## Decision matrix

| # | Action | Route / controller | Admin today | Agent today | Mutation / side effect | Decision |
|---|---|---|---|---|---|---|
| A | `reset_secret` | `POST …/inboxes/:id/reset_secret` → `InboxesController#reset_secret` (api inboxes only) | allow (`InboxPolicy#reset_secret?`) | blocked | Regenerates the API channel's own `secret` (`WebhookSecretable#reset_secret!`). No Meta/webhook/Ops state. | **Allow** (self-service; business-owned API channel) |
| B | `sync_templates` | `POST …/inboxes/:id/sync_templates` → `WhatsappHealthManagement#sync_templates` | allow (`InboxPolicy#sync_templates?`) | blocked | Enqueues `Channels::Whatsapp::TemplatesSyncJob` → **reads** templates from Meta, stores on channel. No credential/webhook/setup change. | **Allow** (optionally audit-log) |
| C | `health` | `GET …/inboxes/:id/health` → `WhatsappHealthManagement#health` | allow | allow if **assigned** (skips `check_authorization`; gated by `fetch_inbox` `show?`) | **Reads** WhatsApp health from Meta Graph. Read-only. | **Allow** |
| D | `enable_whatsapp_calling` / `disable_whatsapp_calling` | `POST …/inboxes/:id/{enable,disable}_whatsapp_calling` → Enterprise `InboxesController` | allow (`InboxPolicy`) | blocked | `enable_voice_calling!` calls **Meta** (`update_calling_status`) **and re-registers the Meta webhook** (subscribes/drops `calls`); disable also re-registers. Same router-owned webhook PR #48 protects. | **Block / Ops-only — recommended (Phase 11B.5D candidate)** if calling is enabled |
| E | `set_inbound_calls` | `POST …/inboxes/:id/set_inbound_calls` → Enterprise `InboxesController` | allow | blocked | Merges local `provider_config['inbound_calls_enabled']`, `save!(validate: false)`. **No Meta call, no webhook re-register.** | **Allow** (or product decision together with D) |
| F | `conference#token / create / destroy` | `…/inboxes/:id/conference[/token]` → `ConferenceController` (`authorize :show?`) | allow | allow if assigned | Live call state (token/join/end). No setup/credential/webhook mutation. | **Allow** (runtime call handling) |
| G | integrations `linear` / `notion` / `shopify` `#destroy` | `DELETE …/integrations/{linear,notion,shopify}` (dedicated controllers) | allow | **also allow — no admin gate** (no `authorize` call; BaseController adds none) | Destroys the `Integrations::Hook` (disconnect); Linear also revokes its OAuth token. | **Product owner decision** — recommend adding an **admin gate** as stock hardening (the generic `hooks#destroy` is HookPolicy admin; these dedicated controllers are not) |
| H | Runtime token refresh / maintenance | services (below) | n/a | n/a | Refresh + persist provider tokens for **already-connected** channels/integrations. | **Allow — do NOT block** |

### H — runtime token-refresh services (invocation = runtime/background, never account-API setup)

| Service | Invoked by |
|---|---|
| `Integrations::Linear::AccessTokenService` | `Integrations::Linear::ProcessorService` (runtime issue ops during a conversation) |
| `Google::RefreshOauthTokenService` / `Microsoft::RefreshOauthTokenService` | `Imap::{Google,Microsoft}FetchEmailService` (background email-fetch jobs) |
| `Instagram::RefreshOauthTokenService` | `Channel::Instagram` (message send/fetch) |
| `Tiktok::TokenService` | `Channel::Tiktok` (message ops) |
| `Whatsapp::ReauthorizationService` | `Whatsapp::EmbeddedSignupService` (Ops onboarding, not a business-admin account-API) |

None is a business-admin account-API setup/control-plane endpoint, so there is no direct setup risk to block;
blocking them would break existing connected integrations.

## Already covered elsewhere (not Tier-B)

- Enterprise **voice channel create** (`inboxes#create` with `channel.type == 'voice'`) is already blocked by
  **PR #46** (`voice` ∈ external-credential channel types).

## Recommended next implementation slice (if pursued): 11B.5D

Block `enable_whatsapp_calling` + `disable_whatsapp_calling` in managed mode (the only Tier-B actions that
re-register the Ops-owned Meta webhook), reusing `BLOOMWIRE_RESTRICT_PROVIDER_SETUP`, admin-gated, scoped in
the Enterprise overlay where the actions are defined; decide `set_inbound_calls` at the same time. Priority is
**conditional** on `channel_voice` being enabled for the managed inbox (the actions short-circuit otherwise).
No other Tier-B backend block is warranted.

Separately (stock hardening, non-Bloomwire): add an admin gate to the dedicated
`linear`/`notion`/`shopify` `#destroy` controllers.
