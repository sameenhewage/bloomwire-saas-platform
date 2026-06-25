# Bloomwire — Evidence Collection Report

> **Status:** Evidence only. **No** final architecture plan here.
> **Scope note:** Pricing / billing / plan limits are **OUT OF SCOPE** for this pass (per request).
> **Constraint:** This document only reads code. Nothing was implemented, branched, migrated, or PR'd.
>
> **Status update — superseded by completed spikes (retained for history).** This is the **earliest, pre-spike**
> evidence pass. Since it was written, runtime spikes **S-01 → S-07** have all been **run** (see the S-01…S-07 reports
> and the **final architecture plan §2** evidence table), so **P-01…P-05 are resolved** (P-04 live Meta *send* + media
> remain production **[BLOCKER]s**). The **"runtime spikes needed (not yet run)"** and **open-questions** sections below
> are kept **for history**; for current direction follow the final architecture plan and **proceed to Phase 1** — do
> **not** re-run the spikes.

## Sources read

- **Chatwoot (fresh)** — Rails app at `app/`, current branch is a Cascade snapshot off `develop`/`main`
  (both at initial commit `56c98c8`). `version_1` is historical reference only and was **not** read.
- **WhatsWay (reference only, never copied)** — Node/TypeScript app at
  `/home/sameen/Downloads/codecanyon-4W7Jp8lG-whatsway-...-saas-platform-.../whatsway/`
  (Drizzle ORM, Express, Vite). Version `3.7.7`. CodeCanyon/Envato proprietary license.

---

## Product direction being validated

Bloomwire is a SaaS where a business owner registers, manages a business account, connects channels, and
manages their own customer inboxes. **WhatsApp first**; Instagram / Messenger / SMS / Email later.
The architecture must treat **"Channel"** as a generic connected endpoint (one WhatsApp number = one channel,
one Instagram inbox = one channel, etc.) and must **not** be hardcoded WhatsApp-only.

---

# A. Chatwoot tenant / account model

### 1. Questions investigated
- What is `Account` / `User` / `AccountUser`?
- Can one account have multiple inboxes, and multiple WhatsApp numbers?
- Can staff/users be isolated per account?

### 2. Evidence found
- **`Account` = the tenant.** `@/home/sameen/.windsurf/worktrees/bloomwire-saas-platform/bloomwire-saas-platform-058f1818/app/app/models/account.rb:25-101`
  Owns everything: `has_many :inboxes` (`:83`), `has_many :contacts` (`:71`), `has_many :conversations` (`:72`),
  `has_many :campaigns` (`:68`), `has_many :automation_rules` (`:66`), and **per-channel** collections incl.
  `has_many :whatsapp_channels, class_name: '::Channel::Whatsapp'` (`:100`), `email_channels` (`:78`),
  `instagram_channels` (`:80`), `facebook_pages` (`:79`), `sms_channels` (`:92`), `api_channels` (`:63`).
- **`User` = a person/login**, STI via `type` column. `@/home/sameen/.windsurf/worktrees/bloomwire-saas-platform/bloomwire-saas-platform-058f1818/app/app/models/user.rb:31`
  (`type :string`), `has_many :accounts, through: :account_users` (`:88`). A `SuperAdmin` is a `User` subtype.
- **`AccountUser` = membership join (account ↔ user) with role.** `@/home/sameen/.windsurf/worktrees/bloomwire-saas-platform/bloomwire-saas-platform-058f1818/app/app/models/account_user.rb:27-58`
  `enum role: { agent: 0, administrator: 1 }` (`:34`); unique `(account_id,user_id)` (`:24`, `:43`);
  `permissions` returns `['administrator']` or `['agent']` (`:56-58`).
- **Multiple inboxes / multiple WhatsApp numbers per account:** `account.inboxes` is unbounded; `channel_whatsapp`
  is keyed by `phone_number UNIQUE` only — **no** uniqueness on `account_id`, so one account may hold many
  WhatsApp channels. `@/home/sameen/.windsurf/worktrees/bloomwire-saas-platform/bloomwire-saas-platform-058f1818/app/app/models/channel/whatsapp.rb:16-17,32`
- **Per-account staff isolation enforced at request time:** `@/home/sameen/.windsurf/worktrees/bloomwire-saas-platform/bloomwire-saas-platform-058f1818/app/app/controllers/concerns/ensure_current_account_helper.rb:21-25`
  — a user must have an `account_users` row for the requested account or it `render_unauthorized`.

### 3. What is proven
- The Account/User/AccountUser triad is a real multi-tenant model. One account → many inboxes → many WhatsApp
  numbers. Membership + role isolate staff per account. This maps cleanly to "business owner owns their account".

### 4. What is not proven
- There is **no** "organization above account" / reseller hierarchy in core. "Bloomwire platform" sits at the
  super-admin/installation layer, not as a parent tenant entity.
- `usage_limits` returns `ChatwootApp.max_limit` (`account.rb:149-154`) — limits exist as a hook but are not a
  business model yet (out of scope anyway).

---

# B. Chatwoot channel / inbox model

### 1. Questions investigated
- What is an inbox; how does it map to channel records; what channel types exist; is "one endpoint = one inbox/channel"
  valid; does it support future channel expansion?

### 2. Evidence found
- **`Inbox` belongs to a polymorphic channel.** `@/home/sameen/.windsurf/worktrees/bloomwire-saas-platform/bloomwire-saas-platform-058f1818/app/app/models/inbox.rb:60`
  `belongs_to :channel, polymorphic: true, dependent: :destroy`; columns `channel_type` + `channel_id`
  (`:11,:28`), indexed `(channel_id,channel_type)` (`:34`). Per-type helpers `whatsapp?`, `email?`, `instagram?`,
  `facebook?`, `sms?`, `api?`, `telegram?`, … (`:117-167`).
- **Generic channel contract = `Channelable` concern.** `@/home/sameen/.windsurf/worktrees/bloomwire-saas-platform/bloomwire-saas-platform-058f1818/app/app/models/concerns/channelable.rb:1-11`
  Every channel `belongs_to :account` and `has_one :inbox, as: :channel`. **This is the existing generic
  "connected endpoint" abstraction.**
- **Channel types that already exist** (`@/home/sameen/.windsurf/worktrees/bloomwire-saas-platform/bloomwire-saas-platform-058f1818/app/app/models/channel/`):
  `api.rb`, `email.rb`, `facebook_page.rb`, `instagram.rb`, `line.rb`, `sms.rb`, `telegram.rb`, `tiktok.rb`,
  `twilio_sms.rb`, `twitter_profile.rb`, `web_widget.rb`, `whatsapp.rb`.

### 3. What is proven
- "One connected endpoint = one channel record = one inbox" is **exactly** how Chatwoot already works
  (`Channelable.has_one :inbox`). WhatsApp, Instagram, Messenger (FacebookPage), SMS, and Email channel types
  **already exist**. Future expansion = add a `Channel::X` including `Channelable`. The generic-Channel abstraction
  the product wants is native.

### 4. What is not proven
- There is **no separate "channel registry" table** abstracting providers/credentials above the per-type channel
  models — provider config lives inside each channel (e.g. WhatsApp `provider_config` jsonb). A Bloomwire-level
  registry, if wanted, would be additive.

---

# C. Chatwoot privacy / access model

### 1. Questions investigated
- Who can read conversations/messages by default? Can platform/super admins read tenant messages? Which endpoints
  expose message content? Can Bloomwire restrict platform-admin message access? Are message bodies logged? Audit gaps?

### 2. Evidence found
- **Tenant scoping:** every account-scoped request runs through `Api::V1::Accounts::BaseController` →
  `current_account` → membership check. `@/home/sameen/.windsurf/worktrees/bloomwire-saas-platform/bloomwire-saas-platform-058f1818/app/app/controllers/api/v1/accounts/base_controller.rb:1-6`
  and `@/home/sameen/.windsurf/worktrees/bloomwire-saas-platform/bloomwire-saas-platform-058f1818/app/app/controllers/concerns/ensure_current_account_helper.rb:21-25`.
- **Conversation access policy** (`@/home/sameen/.windsurf/worktrees/bloomwire-saas-platform/bloomwire-saas-platform-058f1818/app/app/policies/conversation_policy.rb:1-44`):
  `show?` = account `administrator?` OR agent_bot OR `agent_can_view_conversation?` (inbox membership or team).
  `administrator?` = `account_user&.administrator?` — i.e. an **account-scoped** admin, not the platform admin.
- **Conversations / messages are fetched only within `Current.account`:**
  `@/home/sameen/.windsurf/worktrees/bloomwire-saas-platform/bloomwire-saas-platform-058f1818/app/app/controllers/api/v1/accounts/conversations/base_controller.rb:6-9`
  (`Current.account.conversations.find_by!`) and the messages controller `@/home/sameen/.windsurf/worktrees/bloomwire-saas-platform/bloomwire-saas-platform-058f1818/app/app/controllers/api/v1/accounts/conversations/messages_controller.rb:59-65`.
- **Super-admin (platform) surface does NOT include conversations/messages.** Dashboards present:
  `@/home/sameen/.windsurf/worktrees/bloomwire-saas-platform/bloomwire-saas-platform-058f1818/app/app/dashboards/`
  = account, account_user, user, access_token, agent_bot, installation_config, platform_app, platform_banner.
  **No** conversation or message dashboard. Super-admin controllers list confirms the same set
  (`app/app/controllers/super_admin/`).

### 3. What is proven
- By default, **only members of an account** can read that account's conversations/messages; agents are further
  limited to assigned inboxes/teams. The platform super-admin UI has **no** direct conversation/message browser.

### 4. What is NOT proven (these are real gaps for Bloomwire's "platform admins shouldn't read client messages")
- **Super-admin IMPERSONATION exists and bypasses the boundary.** A super-admin can generate a login link as any
  user: `@/home/sameen/.windsurf/worktrees/bloomwire-saas-platform/bloomwire-saas-platform-058f1818/app/app/views/super_admin/users/_impersonate.erb:5`
  calling `generate_sso_link_with_impersonation` (`@/home/sameen/.windsurf/worktrees/bloomwire-saas-platform/bloomwire-saas-platform-058f1818/app/app/models/concerns/sso_authenticatable.rb:27-31`).
  Once impersonating, **all** of that user's conversation access applies → platform admin **can** read client
  messages. This must be restricted/audited for Bloomwire.
- **A super-admin can also self-add as an `AccountUser`** via `app/app/controllers/super_admin/account_users_controller.rb`,
  which would grant account-scoped access. (Controller present; create path exists.)
- **Token/credential leakage to logs:**
  - Facebook callback logs raw tokens at debug: `@/home/sameen/.windsurf/worktrees/bloomwire-saas-platform/bloomwire-saas-platform-058f1818/app/app/controllers/api/v1/accounts/callbacks_controller.rb:25-29`
    (`user_access_token` + `page_access_token`).
  - WhatsApp send-path error handler logs full provider response body: `@/home/sameen/.windsurf/worktrees/bloomwire-saas-platform/bloomwire-saas-platform-058f1818/app/app/services/whatsapp/providers/base_service.rb:44-45`
    (`Rails.logger.error response.body`) — can contain message content / identifiers.
  - Log filtering covers `password`/`secret`/`token`-like keys but **not message bodies**:
    `@/home/sameen/.windsurf/worktrees/bloomwire-saas-platform/bloomwire-saas-platform-058f1818/app/config/initializers/filter_parameter_logging.rb:4-13`.
    Inbound webhook payloads are enqueued whole (`params.to_unsafe_hash`) to Sidekiq (see D) → message text may
    surface in job args / logs depending on Sidekiq logging.

---

# D. Chatwoot WhatsApp / Meta model

### 1. Questions investigated
- Inbox creation, embedded signup, where tokens/config live, inbound webhook receipt, event→inbox mapping,
  outgoing send, delivery/read/failed status, and whether Bloomwire can own a global webhook and route in.

### 2. Evidence found
- **Channel model + credentials:** `Channel::Whatsapp` stores `phone_number` (UNIQUE), `provider`
  (`default` = 360dialog, or `whatsapp_cloud`), and **`provider_config` jsonb** holding `api_key`,
  `phone_number_id`, `business_account_id`, `webhook_verify_token`, `source`.
  `@/home/sameen/.windsurf/worktrees/bloomwire-saas-platform/bloomwire-saas-platform-058f1818/app/app/models/channel/whatsapp.rb:1-70,124-148`
- **Embedded signup flow:** `@/home/sameen/.windsurf/worktrees/bloomwire-saas-platform/bloomwire-saas-platform-058f1818/app/app/services/whatsapp/embedded_signup_service.rb:1-86`
  → exchanges `code` for token (`TokenExchangeService`), fetches phone info, then `ChannelCreationService`
  (`@/home/sameen/.windsurf/worktrees/bloomwire-saas-platform/bloomwire-saas-platform-058f1818/app/app/services/whatsapp/channel_creation_service.rb:33-72`)
  creates the `Channel::Whatsapp` + `Inbox`, storing the access token in `provider_config` and
  `source: 'embedded_signup'`. Auth endpoint: `POST /api/v1/accounts/:id/whatsapp/authorization` (routes `:341-343`).
- **Webhook registration is PER-CHANNEL, per-phone-number:** `Whatsapp::WebhookSetupService#build_callback_url`
  registers `FRONTEND_URL/webhooks/whatsapp/<phone_number>` and calls Graph `subscribe_waba_webhook` with fields
  `messages`, `smb_message_echoes` (+`calls` if enabled).
  `@/home/sameen/.windsurf/worktrees/bloomwire-saas-platform/bloomwire-saas-platform-058f1818/app/app/services/whatsapp/webhook_setup_service.rb:58-80`
- **Inbound webhook receipt:** routes `@/home/sameen/.windsurf/worktrees/bloomwire-saas-platform/bloomwire-saas-platform-058f1818/app/config/routes.rb:623-624`
  (`GET/POST webhooks/whatsapp/:phone_number`). Controller verifies Meta signature + verify-token and enqueues a job:
  `@/home/sameen/.windsurf/worktrees/bloomwire-saas-platform/bloomwire-saas-platform-058f1818/app/app/controllers/webhooks/whatsapp_controller.rb:6-55`.
- **Event → channel/inbox mapping:** `@/home/sameen/.windsurf/worktrees/bloomwire-saas-platform/bloomwire-saas-platform-058f1818/app/app/jobs/webhooks/whatsapp_events_job.rb:140-161`
  — for `object == 'whatsapp_business_account'` it resolves the channel from the **payload metadata**
  (`display_phone_number` + verifies `phone_number_id` against `provider_config`), otherwise falls back to the URL
  `:phone_number`. Then routes to `IncomingMessageWhatsappCloudService` / `IncomingMessageService` (`:79-86`).
- **Inbound persistence + status updates:** `@/home/sameen/.windsurf/worktrees/bloomwire-saas-platform/bloomwire-saas-platform-058f1818/app/app/services/whatsapp/incoming_message_base_service.rb:10-66`
  — `statuses` payloads call `process_statuses` → `find_message_by_source_id(status[:id])` then set
  `message.status` to sent/delivered/read/`failed` (+`external_error` from Meta error). Messages stored with
  `source_id = wamid`.
- **Outgoing send:** `Channel::Whatsapp` delegates `send_message`/`send_template` to a provider service
  (`whatsapp.rb:109-113`). `Whatsapp::Providers::WhatsappCloudService` POSTs to Graph
  `<phone_number_id>/messages` (`@/home/sameen/.windsurf/worktrees/bloomwire-saas-platform/bloomwire-saas-platform-058f1818/app/app/services/whatsapp/providers/whatsapp_cloud_service.rb:101-135`)
  and `process_response` returns the provider `messages[0].id` (`base_service.rb:34-42`).

### 3. What is proven
- Full WhatsApp Cloud lifecycle exists end-to-end: embedded signup → channel/inbox creation → token storage →
  inbound webhook → event mapping → outgoing send → delivery/read/failed status. The events job **already**
  routes a multi-number `whatsapp_business_account` payload by `phone_number_id` independent of the URL.

### 4. What is NOT proven / needs work for Bloomwire
- Today the **callback URL is per-phone-number** and registered by Chatwoot itself. A **single Bloomwire-owned
  global callback** is feasible (the events job already resolves channel from payload metadata) but is **not** how
  registration currently works — `build_callback_url` would need to point at a Bloomwire global endpoint, and a
  Bloomwire router would forward into Chatwoot's job/service. Not implemented.
- Provider routing keys live in `provider_config` **jsonb** (not indexed columns) except `phone_number` (UNIQUE).

---

# E. Multiple WABAs under one Bloomwire Meta App

### 1. Questions investigated
- Can one Bloomwire Meta App serve many client WABAs? Can one WABA have multiple phone numbers? What routing keys
  are needed and can they route to the right tenant/account/inbox?

### 2. Evidence found
- Meta delivers all of an app's WABA events to **one** app-level callback; Chatwoot's events job already handles the
  multi-number case by resolving on `display_phone_number` + `phone_number_id`:
  `@/home/sameen/.windsurf/worktrees/bloomwire-saas-platform/bloomwire-saas-platform-058f1818/app/app/jobs/webhooks/whatsapp_events_job.rb:146-161`
  (code comment cites Chatwoot issue #4712 "facebook cloud api support multiple numbers for a single app").
- Routing keys present in payload + stored config: `display_phone_number` → `channel.phone_number` (UNIQUE),
  `phone_number_id` and `business_account_id` (WABA) → `provider_config`. Channel → `inbox` (`Channelable`) →
  `account`. So `phone_number_id`/`phone_number` resolves channel → inbox → account/tenant.
- Signature verification supports **per-channel app secrets** plus a global `WHATSAPP_APP_SECRET`:
  `@/home/sameen/.windsurf/worktrees/bloomwire-saas-platform/bloomwire-saas-platform-058f1818/app/app/controllers/webhooks/whatsapp_controller.rb:25-42`.

### 3. What is proven
- The data model supports many WABAs / many numbers mapping to many tenants: the resolution chain
  `phone_number_id → Channel::Whatsapp → Inbox → Account` exists and is exercised by the webhook job.

### 4. What is NOT proven
- One **Bloomwire** Meta App fronting **all** client WABAs needs: (a) a global app secret/verify strategy, and
  (b) a global ingress that hands off to the per-channel resolution. Chatwoot has the per-channel resolution but
  not the single Bloomwire-owned front door. **(See WhatsWay's `webhook_configs` "global webhook for all channels"
  pattern in G — conceptual reference only.)**

---

# F. Outgoing message injection / API

### 1. Questions investigated
- Can Bloomwire inject outgoing messages from its own API? How to preserve inbox history for campaigns/automations/AI/
  external API? Where are provider message IDs stored? How do status webhooks map back? Can Chatwoot's send path be reused?

### 2. Evidence found
- **Injection entry point:** `POST .../conversations/:id/messages` →
  `@/home/sameen/.windsurf/worktrees/bloomwire-saas-platform/bloomwire-saas-platform-058f1818/app/app/controllers/api/v1/accounts/conversations/messages_controller.rb:8-14`
  builds via `Messages::MessageBuilder`. There is also a **Platform API** and an **`Channel::Api`** inbox type for
  programmatic flows.
- **Send dispatch:** outgoing messages trigger `SendReplyJob` → `Whatsapp::SendOnWhatsappService`
  (`@/home/sameen/.windsurf/worktrees/bloomwire-saas-platform/bloomwire-saas-platform-058f1818/app/app/services/whatsapp/send_on_whatsapp_service.rb:1-43`),
  which sets `message.source_id` to the provider `wamid` on success (`:37,:42`).
- **Loop/double-send guard:** `Base::SendOnChannelService#invalid_message?` skips re-sending a message that already
  has a `source_id` (originated from channel): `@/home/sameen/.windsurf/worktrees/bloomwire-saas-platform/bloomwire-saas-platform-058f1818/app/app/services/base/send_on_channel_service.rb:35-51`.
- **Provider message ID storage:** `messages.source_id` (text, **indexed**) holds the `wamid`;
  `messages.external_source_ids` jsonb also exists. `@/home/sameen/.windsurf/worktrees/bloomwire-saas-platform/bloomwire-saas-platform-058f1818/app/app/models/message.rb:10,23,38`
- **Status mapping back:** webhook `statuses` resolve by `find_message_by_source_id(status[:id])` →
  set delivered/read/failed (`incoming_message_base_service.rb:49-66`).

### 3. What is proven
- Bloomwire can inject outgoing messages through Chatwoot's own API/builder, history is preserved (messages live on
  the conversation/inbox), provider IDs are stored on `source_id`, and Meta status webhooks reconcile by `source_id`.
  The internal send path is reusable.

### 4. What is NOT proven
- A dedicated **Bloomwire outgoing gateway/API** (campaigns/automations/AI/external) with its own auth, rate limits,
  idempotency, and client webhooks does not exist in core — it would be additive (WhatsWay's `client_api_keys` /
  `client_webhooks` are a conceptual reference, G).

---

# G. WhatsWay comparison (reference only — no code copied)

| Dimension | WhatsWay (TS/Drizzle) | Chatwoot (Rails) | Note for Bloomwire |
|---|---|---|---|
| Tenant/business model | **No first-class account table**; tenancy is soft via `users.createdBy`, `users.channelId`, and a nullable `contacts.tenantId` string. Roles `superadmin/admin/team/manager/agent` (`shared/schema.ts:47-83,125-156`). | Strong `Account`/`AccountUser` tenancy (A). | Chatwoot's tenancy is far stronger; prefer it. |
| Multiple WA numbers/channels | `channels` table = one WA number (`phoneNumberId`, `accessToken`, `whatsappBusinessAccountId`, `appId`) (`schema.ts:247-267`); also a `whatsapp_channels` table with `wabaId`/`phoneNumberId`/`phoneNumber UNIQUE` (`:1017-1036`). WhatsApp-only. | Polymorphic generic channels (B). | Chatwoot's generic channel is better for multi-channel future. |
| One Meta App → many WABAs | **`whatsapp_business_accounts_config`** stores ONE Meta App (`appId`,`appSecret`,`configId`) used for embedded signup of many client channels (`schema.ts:304-329`). | Per-channel config in `provider_config` (D/E). | WhatsWay's single-app-config is a clean conceptual model for Bloomwire's one-app-many-WABA. |
| Global webhook | **Single global endpoint** `/webhook/global` + `/webhook/:id`; `webhook_configs.channelId` comment: *"No fk - global webhook for all channels"* (`server/routes/webhooks.routes.ts:42-46`, `schema.ts:1054-1065`). Handler routes inbound by `value.metadata.phone_number_id` → `channels.phoneNumberId` (`server/services/webhook-handler.ts:168-224`). | Per-phone-number callback today (D). | **Strong reference**: Bloomwire-owned global webhook routing by `phone_number_id`. |
| Inbox/chat model | `conversations` keyed by `channelId`+`contactPhone`, `type: whatsapp/chatbot/sms/email`; `messages` store `whatsappMessageId`, `direction`, `mediaId` (`schema.ts:339-406`). | Conversations/messages under account+inbox (A/F). | Comparable; Chatwoot richer. |
| Campaign model | `campaigns` + `campaign_recipients` + `message_queue` (per-recipient queue w/ `whatsappMessageId`, `sentVia`, cost, status) (`schema.ts:161-246,1067-1092`). | `Campaign` per account+inbox (B). | WhatsWay's per-recipient queue is a useful concept for bulk send. |
| Automation model | Visual flow: `automations`+`automation_nodes`+`automation_edges`+`automation_executions` (node/edge graph, triggers keyword/schedule/api_webhook) (`schema.ts:845-1000`). | `automation_rules` (rule-based). | WhatsWay = flow-builder; Chatwoot = rules. Bloomwire choice later. |
| Outgoing message API | **Client API**: `client_api_keys` (per user/channel, hashed secret, permissions, rate counters) + `client_api_usage_logs` + `client_webhooks` + `rest-api-v1.routes.ts` (`schema.ts:1756-1800`). | Platform API + `Channel::Api` (F). | Reference for Bloomwire's client-facing send API + outbound webhooks. |
| Token/security model | Access tokens stored in `channels.accessToken` (comment: *"Should be encrypted in production"* — i.e. plaintext), `api_logs` stores full request/response bodies (`schema.ts:1025,1095-1108`). | Tokens in `provider_config` jsonb; some token logging gaps (C). | Both have secret-handling gaps; Bloomwire must encrypt + scrub. |
| License | CodeCanyon/Envato proprietary (regular/extended). | Chatwoot MIT core + separate `enterprise/` license. | **WhatsWay code must NOT be copied** — concepts only. |

### What can be borrowed conceptually (NOT code)
- Single **global webhook** that routes inbound by `phone_number_id` (Bloomwire owns the Meta front door).
- A single **Meta App config** record fronting many client WABAs (embedded-signup orchestration).
- **Client API keys + outbound client webhooks** for a tenant-facing outgoing message gateway.
- **Per-recipient message queue** for campaign/bulk delivery with provider-id + status + cost columns.

---

# H. Customization estimate

Legend: **AS-IS** = use Chatwoot unchanged · **LIGHT** = light customization · **CUSTOM** = Bloomwire custom module · **AVOID** = out of scope for now.

| Area | Classification | Basis (evidence) |
|---|---|---|
| tenant/account | **AS-IS** | `Account`/`AccountUser` already multi-tenant (A). |
| users/staff | **AS-IS** | role + membership isolation (A); minor role nuance later. |
| generic channel registry | **LIGHT** | `Channelable` polymorphic channels already generic (B); optional Bloomwire registry is additive. |
| inbox | **AS-IS** | polymorphic inbox↔channel native (B). |
| contacts | **AS-IS** | account-scoped contacts (A). |
| conversations/messages | **AS-IS** | account/inbox scoped, `source_id` provider IDs, status reconcile (F). |
| WhatsApp embedded signup | **LIGHT** | full flow exists (D); needs Bloomwire Meta App config + callback indirection. |
| global webhook | **CUSTOM** | per-number callback today; Bloomwire-owned global front door + router needed (D/E; WhatsWay ref G). |
| multiple WABAs | **LIGHT→CUSTOM** | resolution chain exists (E); single-app fronting all WABAs needs work. |
| outgoing message gateway/API | **CUSTOM** | internal send reusable (F) but no tenant client API/webhooks/rate-limits. |
| privacy/access control | **CUSTOM** | impersonation + token logging gaps must be closed/audited (C). |
| campaigns | **LIGHT** | `Campaign` exists per inbox (B); bulk queue concepts from WhatsWay (G). |
| automation | **LIGHT** | `automation_rules` exist; flow-builder is a product decision (G). |
| tasks/issues | **AVOID** | not core to first slices. |
| calling | **AVOID** | WhatsApp/Twilio voice is Chatwoot **enterprise-licensed**; do not enable unlicensed (prior ADR 0002). |
| billing/pricing | **OUT OF SCOPE FOR NOW** | per request. |

---

# Cross-cutting: open questions

1. **Global webhook ownership** — does Bloomwire register its own callback with Meta and forward into Chatwoot's
   `WhatsappEventsJob`, or keep Chatwoot's per-number registration? (Affects D/E.)
2. **Single Bloomwire Meta App** — one app secret + verify-token strategy spanning all tenant WABAs vs per-channel
   secrets (`whatsapp_controller.rb:25-42`).
3. **Platform-admin message access** — policy for impersonation: disable, gate behind explicit consent, and/or audit
   log every impersonation + every cross-tenant access (C).
4. **Secret handling** — encrypt `provider_config` secrets at rest and scrub tokens/message bodies from logs (C).
5. **Outgoing gateway shape** — reuse `Channel::Api` + Platform API, or build a dedicated Bloomwire client API with
   keys/rate-limits/idempotency/webhooks (F, WhatsWay ref G).
6. **Provider strategy** — `whatsapp_cloud` only vs also `default` (360dialog); routing keys as indexed columns vs
   `provider_config` jsonb (D).

# Cross-cutting: runtime spikes needed (not yet run)
1. **Inbound multi-WABA routing spike:** POST a sample `whatsapp_business_account` webhook for two different
   `phone_number_id`s and confirm each lands in the correct account/inbox via `WhatsappEventsJob`.
2. **Global front-door spike:** stand up a Bloomwire endpoint that receives one Meta callback and forwards to
   Chatwoot's job; verify signature handling with a single app secret across multiple channels.
3. **Outgoing injection spike:** create an outgoing message via API for a WhatsApp inbox, confirm `source_id`
   (`wamid`) is stored and a delivered/read status webhook reconciles it.
4. **Impersonation/audit spike:** confirm what a super-admin can see/do after impersonation; measure what audit
   trail (if any) is produced.
5. **Embedded signup spike:** run embedded signup against a Bloomwire Meta App config and confirm token storage +
   webhook subscription path.

# Initial observations (NOT decisions)
- Chatwoot's **Account / AccountUser / polymorphic Channel / Inbox / Conversation / Message** model already matches
  Bloomwire's ownership intent and the "generic Channel = connected endpoint" abstraction. The conversation **engine
  is reusable as-is** for the customer-inbox core.
- The biggest **net-new** Bloomwire work is at the **edges**: a Bloomwire-owned **global Meta webhook + router**, a
  **single Meta App → many WABAs** onboarding layer, a **tenant outgoing message gateway/API**, and **privacy
  hardening** (impersonation policy + secret/log scrubbing).
- WhatsWay validates these edge concepts (global webhook routing by `phone_number_id`, single Meta-app config,
  client API keys/webhooks) but is WhatsApp-only with weak tenancy and proprietary — **concepts only, never code**.
- **No architecture decision is made here.** This is evidence for the architecture review that follows.
