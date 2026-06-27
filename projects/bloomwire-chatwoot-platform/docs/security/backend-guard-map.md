# Bloomwire Backend Guard Map

Canonical map of the server-side authorization guards that lock down business/customer account users in
Bloomwire **managed mode**. This is the **security boundary**: the backend returns `403` regardless of what
the UI shows. UI hiding (Phase 11B.6/11B.7) is cosmetic/UX defense-in-depth layered on top of this map —
never a replacement for it.

- **Baseline:** `version_1 @ a8023a78` (PR #58 merge — Phase 11B.7A–E complete), runtime-validated on
  `dev.unecast.com` (see `../runtime/phase-11b-validation-index.md`, incl. the **11B.7R** PASS + the exit-gate
  re-confirmation). Earlier baselines: `582f3d0` (PR #48, end of the 11B.2–11B.5 backend lockdown).
- **Read seam for every toggle:** `Bloomwire::Features` (`app/lib/bloomwire/features.rb`). All toggles default
  **OFF**; the master toggle AND-gates every sub-feature. See `feature-toggles.md`.
- **Shared rule:** every guard is **additive + toggle-gated**. With the relevant toggle OFF, behavior is
  **stock Chatwoot** (no interception).

## 403 response shapes (so the UI can detect an Ops-managed block)

| Guard family | Concern | JSON body | i18n key |
|---|---|---|---|
| Native WhatsApp setup (PR #40) | `Bloomwire::RestrictsNativeWhatsappSetup` | `{ error, managed_request: true }` | `bloomwire.native_whatsapp_setup_restricted` |
| Account control-plane (PR #43) | `Bloomwire::RestrictsAccountControlPlane` | `{ error, managed_by_ops: true }` | `bloomwire.account_control_plane_restricted` |
| Provider/channel/integration setup + inbox create (PR #44/#46/#47/#48/#56/#58) | `Bloomwire::RestrictsProviderSetup` | `{ error, managed_by_ops: true }` | `bloomwire.provider_setup_restricted` |
| Bot management (PR #57) | `Bloomwire::RestrictsBotManagement` | `{ error, managed_by_ops: true }` | `bloomwire.bot_management_restricted` |

All are HTTP **403**. No guard reads or echoes secrets/tokens/provider_config. The bot-management guard
short-circuits **before** the agent-bot JBuilder, so a blocked bot read never emits `access_token`,
`secret`, or `bot_config`.

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
- **Feature SHA:** `deee34c`. **Scope corrected in 11B.7B (PR #55, `38b46bd`)** — `agents#*` were removed from
  this guard; account settings + webhooks remain blocked (see PR #55 below).

| Controller#action |
|---|
| `Api::V1::AccountsController#update` (account settings — incl. registered account/business name) |
| `Api::V1::Accounts::WebhooksController#create, #update, #destroy` |

- **ON:** business admin → **403** `managed_by_ops: true` (`account_control_plane_restricted`).
- **OFF:** stock Chatwoot.
- **No longer in this guard (11B.7B):** `Api::V1::Accounts::AgentsController#create, #update, #destroy,
  #bulk_create` — agent/team management is a **business-owner** capability again (allowed; still subject to
  the stock Enterprise usage limit). See **PR #55** below.

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

# Phase 11B.7 — permission-model correction (IMPLEMENTED + runtime-validated)

Phase 11B.7 corrects the managed-mode permission model so the **business owner/admin regains
people-management + full visibility inside their own account**, while platform / provider / bot / integration
**setup** stays Ops-owned. **All slices below are merged into `version_1 @ a8023a78` and runtime-validated
(11B.7R PASS + exit-gate re-confirmation).** Contract: `business-owner-permission-matrix.md`.

## PR #55 — Agents/Teams management RESTORED (`BLOOMWIRE_RESTRICT_ACCOUNT_ADMIN`) — 11B.7B

- **Change:** removed `restrict_account_control_plane!` from `AgentsController` (create/update/destroy/bulk_create
  now allowed for the business admin). `accounts#update` + `webhooks#*` **stay blocked**. Teams were always
  stock-allowed (no Bloomwire guard) and remain so.
- **Plan limit:** the stock Enterprise usage limit is **preserved** — `AgentsController#validate_limit` /
  `validate_limit_for_bulk_create` (reads `Account#usage_limits[:agents]`) returns **402** when exceeded. No
  invented billing.
- **Non-admin agent:** still blocked by the stock admin-only policy (**401**, not `managed_by_ops`).
- **Merge SHA:** `38b46bd`.

## PR #56 — All inbox creation Ops-owned (`BLOOMWIRE_RESTRICT_PROVIDER_SETUP`) — 11B.7C

- **Concern/method:** `Bloomwire::RestrictsProviderSetup#restrict_inbox_creation!` (admin-gated; a **distinct**
  before_action name that delegates to `restrict_provider_setup_for_account_admin!` — required so Rails does
  not dedup it with the `register_webhook` callback wired via `WhatsappHealthManagement`).

| Controller#action | Scope |
|---|---|
| `Api::V1::Accounts::InboxesController#create` | **ALL** channel types, including self-service `web_widget` / `api` |

- The native-WhatsApp (PR #40) and external-provider (PR #46) create guards still fire **first** for their
  channel types, so response shapes are preserved (`whatsapp` → `managed_request`; `email/sms/...` →
  `managed_by_ops`); `web_widget`/`api` fall through to `restrict_inbox_creation!` → `managed_by_ops`.
- **Unchanged:** inbox `index`/`show`/`update` (read/settings) allowed; `web_widget`/`api` **delete** allowed;
  managed/provider **delete** still blocked (PR #48).
- **ON:** business admin → **403** `managed_by_ops: true`. **OFF:** stock Chatwoot. **Merge SHA:** `d8099de`.

## PR #57 — Bots Ops-owned (`BLOOMWIRE_RESTRICT_BOT_MANAGEMENT`) — 11B.7D

- **New toggle** `BLOOMWIRE_RESTRICT_BOT_MANAGEMENT` (**default OFF**, master-gated). Concern/method:
  `Bloomwire::RestrictsBotManagement#restrict_bot_management!`. **Not admin-gated** — the bot read endpoints
  expose `access_token` / `secret` / `bot_config`, so **agents are blocked too**.

| Controller#action |
|---|
| `Api::V1::Accounts::AgentBotsController#index, #show, #create, #update, #destroy, #avatar, #reset_access_token, #reset_secret` |
| `Api::V1::Accounts::InboxesController#agent_bot` (read) `, #set_agent_bot` (set **and** disconnect) |

- **Secret safety:** the guard renders only the i18n error + `managed_by_ops: true` and short-circuits
  **before** the agent-bot JBuilder — a blocked read leaks no `access_token`/`secret`/`bot_config`.
- **Runtime NOT blocked:** bot execution (`AgentBots::WebhookJob`, `AgentBotListener`) does not route through
  this controller and is unaffected.
- **ON:** business user (admin **and** agent) → **403** `managed_by_ops: true`. **OFF:** stock Chatwoot.
  **Merge SHA:** `f8138de`.

## PR #58 — Integrations Ops-owned (`BLOOMWIRE_RESTRICT_PROVIDER_SETUP`) — 11B.7E

- **No new backend guard.** Connect/config **writes** were already blocked by PR #47
  (`integrations/hooks#create|update`, `integrations/slack#create|update`, `integrations/shopify#auth`).
- **Catalog read intentionally OPEN:** `Api::V1::Accounts::Integrations::AppsController#index, #show` is **not**
  403-guarded because it is consumed by **runtime conversation surfaces** (ContactPanel/Linear, video-call
  button, label suggestions). 403'ing it would break runtime, which the contract forbids.
- **Enforcement:** UI hide + route-block (capability `canAccessIntegrations`) + the existing PR #47 write 403.
- **Merge SHA:** `de42d74` (+ `c49ea80` route-guard hardening; merge `a8023a78`).

---

## Quick index: blocked account-API actions (managed mode, all toggles ON)

```
BLOCKED (403):
accounts#update (incl. registered name)          PR#43  managed_by_ops
webhooks#{create,update,destroy}                 PR#43  managed_by_ops
oauth_authorization, twitter/authorizations#create,
  channels/twilio_channels#create,
  callbacks#{register_facebook_page,facebook_pages,reauthorize_page},
  integrations/shopify#auth, + provider OAuth callbacks   PR#44  managed_by_ops
inboxes#create|update (email/sms/line/telegram/voice)     PR#46  managed_by_ops
inboxes#create|update (whatsapp)                          PR#40  managed_request
inboxes#create (web_widget / api + ALL other types)      PR#56  managed_by_ops
integrations/hooks#{create,update}, integrations/slack#{create,update},
  linear OAuth callback                                   PR#47  managed_by_ops
inboxes#destroy (managed/provider channels)              PR#48  managed_by_ops
inboxes#register_webhook                                  PR#48  managed_by_ops
agent_bots#{index,show,create,update,destroy,avatar,
  reset_access_token,reset_secret}                        PR#57  managed_by_ops
inboxes#{agent_bot,set_agent_bot} (inbox-level bot)       PR#57  managed_by_ops

ALLOWED (business admin, managed mode — 11B.7 correction):
agents#{create,update,destroy,bulk_create}       PR#55  (stock usage limit → 402 if exceeded)
teams#* (stock-allowed; no Bloomwire guard)
inboxes#{index,show,update}                       (read / settings)
inboxes#destroy (web_widget / api self-service)
integrations/apps#{index,show} (catalog read)    PR#58  (intentionally open for runtime)
conversations / contacts / inbox reads           (workspace transparency)
```

See `ui-hiding-source-of-truth.md` for the UI hide/allow breakdown (Phase 11B.6 + 11B.7).

---

## Phase 11B.7 — permission-model correction: COMPLETE

All Phase 11B.7 slices are **merged and runtime-validated** (`version_1 @ a8023a78`, 11B.7R PASS + exit-gate
re-confirmation). The per-slice guard detail is documented in the **Phase 11B.7** section above (PR #55–#58);
the contract is `business-owner-permission-matrix.md`. There are no pending/planned backend guard changes for
Phase 11B.
