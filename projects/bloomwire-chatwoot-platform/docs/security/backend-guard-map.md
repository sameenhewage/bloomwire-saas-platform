# Bloomwire Backend Guard Map

Canonical map of the server-side authorization guards that lock down business/customer account users in
Bloomwire **managed mode**. This is the **security boundary**: the backend returns `403` regardless of what
the UI shows. UI hiding (Phase 11B.6) is cosmetic/UX defense-in-depth layered on top of this map — never a
replacement for it.

- **Baseline:** `version_1 @ 582f3d0` (PR #48 merge), runtime-validated on `dev.unecast.com` (see
  `../runtime/phase-11b-validation-index.md`).
- **Read seam for every toggle:** `Bloomwire::Features` (`app/lib/bloomwire/features.rb`). All toggles default
  **OFF**; the master toggle AND-gates every sub-feature. See `feature-toggles.md`.
- **Shared rule:** every guard is **additive + toggle-gated**. With the relevant toggle OFF, behavior is
  **stock Chatwoot** (no interception).

## 403 response shapes (so the UI can detect an Ops-managed block)

| Guard family | Concern | JSON body | i18n key |
|---|---|---|---|
| Native WhatsApp setup (PR #40) | `Bloomwire::RestrictsNativeWhatsappSetup` | `{ error, managed_request: true }` | `bloomwire.native_whatsapp_setup_restricted` |
| Account control-plane (PR #43) | `Bloomwire::RestrictsAccountControlPlane` | `{ error, managed_by_ops: true }` | `bloomwire.account_control_plane_restricted` |
| Provider/channel/integration setup (PR #44/#46/#47/#48) | `Bloomwire::RestrictsProviderSetup` | `{ error, managed_by_ops: true }` | `bloomwire.provider_setup_restricted` |

All are HTTP **403**. No guard reads or echoes secrets/tokens/provider_config.

---

## PR #40 — Native WhatsApp setup (`BLOOMWIRE_RESTRICT_NATIVE_WHATSAPP_SETUP`)

- **Concern/method:** `Bloomwire::RestrictsNativeWhatsappSetup#restrict_native_whatsapp_setup!`
  (scoped via overridable `native_whatsapp_setup_request?`).
- **Feature SHA:** `876d81c`.

| Controller#action | Scope |
|---|---|
| `Api::V1::Accounts::InboxesController#create` | only when `channel.type == 'whatsapp'` |
| `Api::V1::Accounts::InboxesController#update` | only when the existing channel is `Channel::Whatsapp` and channel params are present |
| `Api::V1::Accounts::Whatsapp::AuthorizationsController#create` | embedded-signup authorization |

- **ON:** business user → **403** `managed_request: true` (`native_whatsapp_setup_restricted`).
- **OFF:** stock Chatwoot (native WhatsApp setup works).

## PR #43 — Account control-plane (`BLOOMWIRE_RESTRICT_ACCOUNT_ADMIN`)

- **Concern/method:** `Bloomwire::RestrictsAccountControlPlane#restrict_account_control_plane!`.
- **Feature SHA:** `deee34c`.

| Controller#action |
|---|
| `Api::V1::AccountsController#update` (account settings) |
| `Api::V1::Accounts::AgentsController#create, #update, #destroy, #bulk_create` |
| `Api::V1::Accounts::WebhooksController#create, #update, #destroy` |

- **ON:** business admin → **403** `managed_by_ops: true` (`account_control_plane_restricted`).
- **OFF:** stock Chatwoot.

## PR #44 — Provider/channel setup + callback completion (`BLOOMWIRE_RESTRICT_PROVIDER_SETUP`)

- **Concern/method:** `Bloomwire::RestrictsProviderSetup#restrict_provider_setup!` (unconditional — also blocks
  agents, since these flows are authentication-only in stock).
- **Feature SHA:** `fdf2806` (+ `b0d07ce` callback-completion review fix).

| Controller#action | Notes |
|---|---|
| `Api::V1::Accounts::OauthAuthorizationController` (all actions) + provider subclasses that inherit it (e.g. `Google::AuthorizationsController`) | provider OAuth init/redirect (e.g. Google connect — validated in 11B.5BR) |
| `Api::V1::Accounts::Twitter::AuthorizationsController#create` | X/Twitter connect |
| `Api::V1::Accounts::Channels::TwilioChannelsController#create` | Twilio channel create |
| `Api::V1::Accounts::CallbacksController#register_facebook_page, #facebook_pages, #reauthorize_page` | Facebook page setup |
| `Api::V1::Accounts::Integrations::ShopifyController#auth` | Shopify connect init (`:auth` only; `:orders`/`:destroy` stay stock) |
| `OauthCallbackController#show` | Google/Microsoft/Facebook OAuth completion (public callback) |
| `Instagram::CallbacksController#show` | Instagram OAuth completion |
| `Twitter::CallbacksController#show` | X/Twitter OAuth completion |
| `Tiktok::CallbacksController#show` | TikTok OAuth completion |
| `Shopify::CallbacksController#show` | Shopify OAuth completion |

- **ON:** business user (admin **and** agent on the auth-only paths) → **403** `managed_by_ops: true`.
- **OFF:** stock Chatwoot.

## PR #46 — External-credential inbox create/update (`BLOOMWIRE_RESTRICT_PROVIDER_SETUP`)

- **Concern/method:** `Bloomwire::RestrictsProviderSetup#restrict_external_provider_channel_setup!`
  (admin-gated; scoped via overridable `external_provider_channel_setup_request?`).
- **Feature SHA:** `3dda4fa` (+ `c96ac53`).

| Controller#action | Scope |
|---|---|
| `Api::V1::Accounts::InboxesController#create` | `channel.type ∈ {email, sms, line, telegram, voice}` |
| `Api::V1::Accounts::InboxesController#update` | existing channel ∈ `{Channel::Email, Channel::Sms, Channel::Line, Channel::Telegram, Channel::TwilioSms}` with channel params |

- **Not matched (stay stock):** `web_widget`, `api`; WhatsApp (covered by its own native guard, PR #40).
- **ON:** business admin → **403** `managed_by_ops: true`. Agents stay on the stock admin-only `InboxPolicy`.
- **OFF:** stock Chatwoot.

## PR #47 — Hooks / Slack / Linear integration-connect (`BLOOMWIRE_RESTRICT_PROVIDER_SETUP`)

- **Concern/methods:** `restrict_provider_setup_for_account_admin!` (admin-gated) for hooks/slack;
  `restrict_provider_setup!` (unconditional) for the Linear OAuth callback.
- **Feature SHA:** `8895011` (+ `5ccbd04` Linear-callback review fix).

| Controller#action | Notes |
|---|---|
| `Api::V1::Accounts::Integrations::HooksController#create, #update` | integration connect (stores tokens/keys/settings) |
| `Api::V1::Accounts::Integrations::SlackController#create, #update` | Slack connect/update |
| `Linear::CallbacksController#show` | Linear OAuth completion (public callback) |

- **Stay allowed:** `hooks#process_event` (runtime), `hooks#destroy`, `slack#destroy` (HookPolicy admin).
- **ON:** business admin → **403** `managed_by_ops: true`. Agents stay on the stock admin-only `HookPolicy`.
- **OFF:** stock Chatwoot.

## PR #48 — Managed/provider inbox destroy + webhook re-register (`BLOOMWIRE_RESTRICT_PROVIDER_SETUP`)

- **Concern/methods:** `restrict_managed_provider_inbox_destroy!` (admin-gated; scoped via overridable
  `managed_provider_inbox_destroy?`) for destroy; `restrict_provider_setup_for_account_admin!` for
  register_webhook (declared inside `WhatsappHealthManagement` where the action is defined).
- **Feature SHA:** `4f4c041` (merge `582f3d0`).

| Controller#action | Scope |
|---|---|
| `Api::V1::Accounts::InboxesController#destroy` | channel type **not** in `{Channel::WebWidget, Channel::Api}` (i.e. all managed/provider channels incl. WhatsApp) |
| `Api::V1::Accounts::Concerns::WhatsappHealthManagement#register_webhook` | WhatsApp Cloud webhook re-registration |

- **Not matched (stay stock):** `web_widget`, `api` inbox destroy.
- **Side-effect guarantee:** the guard short-circuits **before** `DeleteObjectJob` is enqueued and before
  `Whatsapp::WebhookSetupService` is invoked — no inbox/channel deleted, no webhook/router/provider_config
  mutated (validated in 11B.5BR).
- **ON:** business admin → **403** `managed_by_ops: true`. Agents stay on stock `InboxPolicy` /
  `check_admin_authorization?`.
- **OFF:** stock Chatwoot.

---

## Quick index: blocked account-API actions (managed mode, all toggles ON)

```
accounts#update                                  PR#43  managed_by_ops
agents#{create,update,destroy,bulk_create}       PR#43  managed_by_ops
webhooks#{create,update,destroy}                 PR#43  managed_by_ops
oauth_authorization, twitter/authorizations#create,
  channels/twilio_channels#create,
  callbacks#{register_facebook_page,facebook_pages,reauthorize_page},
  integrations/shopify#auth, + provider OAuth callbacks   PR#44  managed_by_ops
inboxes#create|update (email/sms/line/telegram/voice)     PR#46  managed_by_ops
inboxes#create|update (whatsapp)                          PR#40  managed_request
integrations/hooks#{create,update}, integrations/slack#{create,update},
  linear OAuth callback                                   PR#47  managed_by_ops
inboxes#destroy (managed/provider channels)              PR#48  managed_by_ops
inboxes#register_webhook                                  PR#48  managed_by_ops
```

See `ui-hiding-source-of-truth.md` for the allow/hide/defer breakdown for Phase 11B.6.

---

## Phase 11B.7 — pending permission-model corrections (planned, not yet implemented)

The map above is accurate for `version_1 @ 3526efa`. Phase 11B.7 (see
`business-owner-permission-matrix.md`) **corrects the managed-mode permission model** so the business
owner/admin regains people-management + full visibility inside their own account, while platform / provider /
bot / integration **setup** stays Ops-owned. Planned guard changes:

| Guard | Planned change | Slice |
|---|---|---|
| PR #43 `agents#{create,update,destroy,bulk_create}` | **Relax** — allow business admin; add plan-limit hook + audit. `accounts#update` (name) and `webhooks#*` **stay blocked**. | 11B.7B |
| Inbox create (`web_widget` / `api`) — currently stock-allowed | **Add block** — all inbox creation Ops-owned in managed mode. | 11B.7C |
| Bots create/update/destroy — currently unguarded | **Add block** — bots Ops-owned. | 11B.7D |
| Integrations catalog/detail read — currently reachable | **Decision pending** (403 vs read-only) then route-block; connect/config already blocked (PR #47). | 11B.7E |

Until each slice merges and is validated (11B.7R), the **current-state** rows above remain in force.
