# Bloomwire — Runtime Analysis Plan + Runtime Evidence / RCA Report

> **Status:** Analysis only. **No** final feature-toggle plan and **no** managed-onboarding plan here.
> **Purpose:** Define exactly what existing-Chatwoot runtime behavior must be inspected (Part 1), then record
> the executed evidence + root-cause explanation (Part 2), so the final feature-toggle managed-onboarding plan
> can be written on facts, not assumptions.
> **Sources:** [`bloomwire-evidence-collection-report.md`](./bloomwire-evidence-collection-report.md) ·
> [`bloomwire-evidence-review-and-decision-register.md`](./bloomwire-evidence-review-and-decision-register.md).
> **Scope:** Pricing / billing out of scope. Nothing implemented, branched, switched, migrated, or PR'd. No app code changed.
> **Core product rule being protected:** *Bloomwire/Unecast OFF → original Chatwoot behavior unchanged.
> Bloomwire/Unecast ON → managed onboarding + global webhook/router + routing registry + privacy controls active.*

## Execution mode + proof discipline (read first)

- **What was executed:** full **code-level runtime tracing** of the live Chatwoot source on `develop`
  (the base `app/` Rails app is present from the initial commit). Every claim below is anchored to a file:line.
- **What was NOT executed:** **live browser / DB / Meta runtime** verification. The dev server is **down**
  (no listener on `:3000`/`:3036` at analysis time) and the WhatsApp flows require a real Meta app + WABA.
  Per the Runtime Proof Gate, those are recorded as **follow-up spikes** (Part 2 §11), not as proof.
- **Proof labels used throughout:** **[CODE-PROVEN]** = verified by reading source; **[RUNTIME-TBD]** = needs a
  live spike. Code-proof and runtime-proof are kept strictly separate.
- **Baseline note:** `develop` currently contains **pure Chatwoot** (no Bloomwire wrapper code). So the current
  behavior *is* the "feature OFF" baseline by construction (Part 2, Area C).

---

# PART 1 — Runtime Analysis Plan (Task 1)

The exact runtime behavior that must be inspected before the final plan. Each area lists the questions and the
inspection method. (Part 2 answers them.)

### A. Super Admin "WhatsApp Embedded" settings — what to inspect
- Which controller/API saves these settings? Which model/table/config key stores App ID / App Secret /
  Configuration ID / API version?
- Where are these values read during embedded signup?
- Are the secrets masked / encrypted / logged?
- Does this page register or affect any webhook?
- **Method:** trace `super_admin` routes → controller → `InstallationConfig`/`GlobalConfigService`; trace readers
  in the WhatsApp signup + webhook code; inspect `filter_parameter_logging` + storage column type.

### B. Account Workspace "Settings → Inboxes → WhatsApp" — what to inspect
- Which UI route/component renders the form? Which API endpoint is called on submit?
- Which controller/service creates `Channel::Whatsapp`? Which creates the `Inbox`?
- What exactly is stored in `provider_config`?
- Does it auto-trigger webhook setup? What callback URL is generated/registered?
- **Method:** trace the FE channel components → Vuex action → REST route → `InboxesController#create` /
  `Whatsapp::AuthorizationsController` → `ChannelCreationService` / `WebhookSetupService`.

### C. Feature OFF baseline — what to prove
- Do the Super Admin embedded-config page and the account-level WhatsApp setup exist and operate unmodified?
- Are native Chatwoot routes/UI intact?
- Can the existing behavior remain unchanged when Bloomwire mode is OFF?
- **Method:** confirm the current `develop` tree has no Bloomwire wrapper over these paths; identify the seams a
  toggle must wrap (not replace).

### D. Feature ON boundary — what to identify
- Where would feature checks be inserted for: UI visibility of account WhatsApp setup; direct API restriction;
  a SuperAdmin/Ops-only setup path; webhook callback URL behavior; routing-registry write points; privacy hardening.
- **Method:** map each product requirement to the exact controller/component/service choke point.

### E. Global webhook feasibility — what to trace (no permanent implementation)
- How is a Meta webhook payload received? How is `phone_number_id` extracted? How does it resolve to
  `Channel::Whatsapp` / `Inbox` / `Account`? How does it forward into `WhatsappEventsJob` and land in the right inbox?
- **Method:** trace `webhooks/whatsapp` controller → `WhatsappEventsJob` resolution → incoming-message service.

### F. SuperAdmin vs Account Administrator — what to inspect
- Is a SuperAdmin automatically an Account Administrator, or added manually? Can a SuperAdmin self-add to an
  account? Can a SuperAdmin impersonate a tenant user? What conversations/messages become visible? Is there any
  audit trail?
- **Method:** trace `super_admin/account_users` create, `SsoAuthenticatable` impersonation, `ConversationPolicy`,
  and the `audited`/`Enterprise::AuditLog` wiring + feature gate.

### G. Token / log scrubbing — what to inspect
- Are WhatsApp/Facebook tokens logged? Are webhook payload message bodies logged? Are Sidekiq job args exposing
  message content? Which logs need scrubbing?
- **Method:** read `filter_parameter_logging`, explicit `Rails.logger` calls in the WhatsApp/Facebook paths, and
  how inbound payloads are enqueued.

---

# PART 2 — Runtime Evidence / RCA Report (Task 2)

## 1. What was inspected

Code-level trace of: the Super Admin app-config/settings path; the account-level WhatsApp setup (manual +
embedded); the inbound webhook controller + events job; the channel model lifecycle; the impersonation / account-
membership / audit surfaces; and the logging/scrubbing configuration. Files are listed in §4.

## 2. Browser / UI paths checked *(traced statically via routes + components; live browse = [RUNTIME-TBD])*

- **Super Admin → Settings → "WhatsApp Embedded":** `GET /super_admin/settings` (`SuperAdmin::SettingsController#show`,
  `app/config/routes.rb:700`) renders the settings page; the WhatsApp-Embedded section persists via
  `/super_admin/app_config` (`routes.rb:677`). Config group key = `whatsapp_embedded` (`app/app/controllers/super_admin/app_configs_controller.rb:50`).
- **Account → Settings → Inboxes → New → WhatsApp:** SPA route `GET /app/accounts/:account_id/settings/inboxes/new/whatsapp`
  (dashboard SPA). Provider chooser `channels/Whatsapp.vue`; manual form `channels/CloudWhatsapp.vue`; embedded
  `channels/WhatsappEmbeddedSignup.vue`; 360dialog `channels/360DialogWhatsapp.vue`
  (`app/app/javascript/dashboard/routes/dashboard/settings/inbox/channels/`).
- **Inbox configuration page** (existing inbox): `settingsPage/ConfigurationPage.vue` (shows embedded-signup reconfigure / verify token).

## 3. API endpoints observed *(from routes + controllers)*

| Endpoint | Maps to | Purpose |
|---|---|---|
| `GET/POST /super_admin/app_config` | `SuperAdmin::AppConfigsController#show/create` | Save the 4 WhatsApp-Embedded `InstallationConfig` keys (`app_configs_controller.rb:4-32,50`) |
| `POST /api/v1/accounts/:id/inboxes` | `Api::V1::Accounts::InboxesController#create` | **Manual** WhatsApp Cloud channel+inbox (`inboxes_controller.rb:33-46`) |
| `POST /api/v1/accounts/:id/whatsapp/authorization` | `Api::V1::Accounts::Whatsapp::AuthorizationsController#create` | **Embedded** signup create/reauth (`routes.rb:341-343`, `authorizations_controller.rb:7-24`) |
| `GET /webhooks/whatsapp/:phone_number` | `Webhooks::WhatsappController#verify` | Meta verify-token handshake (`routes.rb:623`) |
| `POST /webhooks/whatsapp/:phone_number` | `Webhooks::WhatsappController#process_payload` | Inbound message/status receipt (`routes.rb:624`, `whatsapp_controller.rb:6-15`) |
| `POST /super_admin/account_users` | `SuperAdmin::AccountUsersController#create` | Add a user to an account (self-add possible) (`routes.rb:705`, `account_users_controller.rb:12-18`) |

## 4. Controllers / services / models involved

- **Super Admin config:** `SuperAdmin::SettingsController`, `SuperAdmin::AppConfigsController`,
  `SuperAdmin::InstallationConfigsController`; `InstallationConfig` model; `GlobalConfigService` (`app/lib/global_config_service.rb`).
- **Account WhatsApp setup:** FE `channels/Whatsapp.vue` + `channels/CloudWhatsapp.vue` + `channels/WhatsappEmbeddedSignup.vue`;
  `Api::V1::Accounts::InboxesController`; `Api::V1::Accounts::Whatsapp::AuthorizationsController`;
  `Whatsapp::EmbeddedSignupService`, `Whatsapp::ChannelCreationService`, `Whatsapp::WebhookSetupService`,
  `Whatsapp::FacebookApiClient`; models `Channel::Whatsapp`, `Inbox`.
- **Inbound pipeline:** `Webhooks::WhatsappController` (+ `MetaTokenVerifyConcern`); `Webhooks::WhatsappEventsJob`;
  `Whatsapp::IncomingMessageWhatsappCloudService` / `Whatsapp::IncomingMessageService`.
- **Privacy surfaces:** `SsoAuthenticatable` concern; `SuperAdmin::AccountUsersController`; `ConversationPolicy`;
  audit overlay `Enterprise::AuditLog` + `Enterprise::Audit::*` concerns; `Api::V1::Accounts::AuditLogsController`.
- **Logging:** `config/initializers/filter_parameter_logging.rb`; `Api::V1::Accounts::CallbacksController#log_additional_info`;
  `Whatsapp::Providers::BaseService#handle_error`.

## 5. DB / config storage found

- **Super Admin WhatsApp-Embedded keys** are `InstallationConfig` rows (`installation_configs` table), defined in
  `app/config/installation_config.yml:154-169`: `WHATSAPP_APP_ID`, `WHATSAPP_CONFIGURATION_ID`, `WHATSAPP_APP_SECRET`,
  `WHATSAPP_API_VERSION` (default `v22.0`). Saved via `InstallationConfig.first_or_create(value:, locked:false)`
  (`app_configs_controller.rb:22-24`); read via `GlobalConfigService.load(key, default)` →
  `GlobalConfig.get` → ENV fallback → auto-create (`global_config_service.rb:2-16`). **Stored as plaintext**
  (serialized `value`; no encryption). **[CODE-PROVEN]**
- **Per-channel WhatsApp credentials** live in `channel_whatsapp.provider_config` **jsonb** (`Channel::Whatsapp`,
  `app/app/models/channel/whatsapp.rb:1-17`): `api_key`, `phone_number_id`, `business_account_id`,
  `webhook_verify_token` (auto-generated, `:124-126`), `source`. `phone_number` is the only **UNIQUE** column. **[CODE-PROVEN]**
- **Source of truth stays Chatwoot:** accounts/inboxes/contacts/conversations/messages are unchanged core tables.
  No Bloomwire table exists on `develop`. **[CODE-PROVEN]**

## 6. Actual runtime behavior (by area)

### A. Super Admin WhatsApp-Embedded
- Saves exactly 4 `InstallationConfig` keys for the **Meta App** used by embedded signup (`app_configs_controller.rb:50`).
- These are consumed by `GlobalConfigService.load('WHATSAPP_APP_ID'/'WHATSAPP_APP_SECRET'/'WHATSAPP_API_VERSION'/...)`
  during token exchange (`Whatsapp::FacebookApiClient`) and as the **global signature-verify fallback**
  `GlobalConfigService.load('WHATSAPP_APP_SECRET', nil)` in `Webhooks::WhatsappController#meta_app_secrets`
  (`whatsapp_controller.rb:25-30`).
- **This page does NOT create or register any webhook.** It only stores Meta App credentials + the global app
  secret. Webhook *registration* is per-channel (Area B/E). **[CODE-PROVEN]** — confirms the premise that it does
  not manage a Bloomwire global webhook/router.
- Note: a legacy feature flag `whatsapp_embedded_signup` exists and is **deprecated** (`config/features.yml:181-184`).

### B. Account-level WhatsApp setup
- **Manual (`CloudWhatsapp.vue`):** fields **Inbox Name, Phone Number, Phone Number ID, Business Account ID, API key**
  (`CloudWhatsapp.vue:18-36`) → Vuex `inboxes/createChannel` → `POST /api/v1/accounts/:id/inboxes` with
  `channel:{type:'whatsapp', provider:'whatsapp_cloud', provider_config:{api_key, phone_number_id, business_account_id}}`
  (`CloudWhatsapp.vue:45-60`).
- `InboxesController#create` → `create_channel` builds `account.whatsapp_channels.create!(...)` then the `Inbox`
  (`inboxes_controller.rb:33-46,93-101`); `whatsapp` is in `allowed_channel_types` (`:100`).
- `Channel::Whatsapp` auto-adds `webhook_verify_token` (`:124-126`) and, for **manual** whatsapp_cloud, fires
  `after_commit :setup_webhooks, on: :create` (`:35-37,144-148`) → `WebhookSetupService`.
- **Embedded:** `POST /whatsapp/authorization` → `EmbeddedSignupService` → `ChannelCreationService` builds
  `provider_config{api_key:<access_token>, phone_number_id, business_account_id:<waba_id>, source:'embedded_signup'}`
  + `Inbox` (`channel_creation_service.rb:50-67`), then calls `channel.setup_webhooks` **explicitly**
  (`embedded_signup_service.rb:22`; the `source:'embedded_signup'` flag suppresses the after_commit, `:144-148`).
- **Callback URL is per-phone-number:** `"#{FRONTEND_URL}/webhooks/whatsapp/#{phone_number}"`
  (`webhook_setup_service.rb:75-80`), registered at Meta via `subscribe_waba_webhook(waba_id, callback_url,
  verify_token, fields:[messages, smb_message_echoes(+calls)])` (`:58-73`). **[CODE-PROVEN]**

### C. Feature OFF baseline
- The current `develop` tree IS pure Chatwoot for all of the above — there is **no** Bloomwire wrapper over the
  super-admin config page, the account setup, the webhook controller, or the channel model. So "OFF = original
  behavior" holds **by construction today**; the risk is entirely in how toggles are introduced later. **[CODE-PROVEN]**

### D. Feature ON boundary (insertion points) — see §8.

### E. Global webhook resolution
- `POST /webhooks/whatsapp/:phone_number` verifies the Meta signature (`verify_meta_signature!`, per-channel
  secrets + global `WHATSAPP_APP_SECRET`) then enqueues the **entire** payload:
  `Webhooks::WhatsappEventsJob.perform_later(params.to_unsafe_hash)` (`whatsapp_controller.rb:4-15,25-30`).
- The job resolves the channel **from payload metadata, independent of the URL**: for
  `object == 'whatsapp_business_account'` it reads `entry[0].changes[0].value.metadata.{display_phone_number,
  phone_number_id}`, finds `Channel::Whatsapp` by `phone_number`, and confirms `provider_config['phone_number_id']`
  matches (`whatsapp_events_job.rb:146-161`; mirror logic `whatsapp_controller.rb:44-55`). Then →
  `IncomingMessageWhatsappCloudService` under `channel.inbox` (`:79-86`).
- So the chain `phone_number_id → Channel::Whatsapp → Inbox → Account` already works and a Bloomwire front door
  could verify+forward into `WhatsappEventsJob`. **[CODE-PROVEN]** that the resolution exists; **[RUNTIME-TBD]** for a
  real two-WABA delivery + a Bloomwire-owned global ingress.

### F. SuperAdmin vs Account Administrator
- **A SuperAdmin is NOT automatically an Account Administrator.** `User#type == 'SuperAdmin'` (platform) is
  independent of `AccountUser` membership; nothing auto-creates an `AccountUser` for super admins. Account-scoped
  access requires either (a) membership or (b) impersonation. **[CODE-PROVEN]**
- **Self-add is possible:** `SuperAdmin::AccountUsersController#create` lets a super admin create an `AccountUser`
  (any role) for any account (`account_users_controller.rb:12-18`, `routes.rb:705`).
- **Impersonation exists:** `generate_sso_link_with_impersonation` mints a 5-minute SSO login link flagged
  `impersonation` (`sso_authenticatable.rb:27-31`), surfaced from the super-admin user page. After login the platform
  user has that tenant user's full access → with admin membership/impersonation, `ConversationPolicy#show?` returns
  true → **all** of the account's conversations/messages become readable.
- **Audit trail is weak/licensed:** audit logging is an **enterprise overlay** (`Enterprise::AuditLog <
  Audited::Audit`, `Enterprise::Audit::*` concerns; e.g. `AccountUser.include_mod_with('Audit::AccountUser')`,
  `account_user.rb:85`) loaded only when `ChatwootApp.enterprise?` (the `enterprise/` dir exists,
  `chatwoot_app.rb:14-18`), and **viewing** is gated behind the **premium** `audit_logs` feature
  (`audit_logs_controller.rb:17-28`, `app/enterprise/config/premium_features.yml:3`). Crucially:
  - **Impersonation is NOT audited at all** (no server-side record; only a frontend `sessionStorage` flag via
    `useImpersonation`). **[CODE-PROVEN]**
  - Audit (where active) records **model attribute writes**, never **message reads/views**, and never message content.
  - For Bloomwire CE (must avoid enterprise-licensed features per prior ADR 0002; may even set `DISABLE_ENTERPRISE`),
    there is effectively **no usable audit** of platform-admin access to tenant data.

### G. Token / log scrubbing
- `filter_parameter_logging.rb:4-13` redacts request params whose keys match `password/secret/_key/auth/.../` and a
  regex for any `token` (except `website_token`). This covers **only** Rails' automatic request-param logging.
- **Explicit logger statements bypass that filter:**
  - `CallbacksController#log_additional_info` logs raw `user_access_token` + `page_access_token` at **debug**
    (`callbacks_controller.rb:25-30`).
  - `BaseService#handle_error` logs the **full provider response body** at **error** on send failure
    (`base_service.rb:44-45`) — may contain identifiers/content.
- **Sidekiq job args:** the inbound webhook enqueues `params.to_unsafe_hash` (whole payload incl. message text)
  (`whatsapp_controller.rb:13`); job args are stored in Redis and visible in the Sidekiq UI / retry / dead sets.
- `filter_parameters` has **no** message-body key (`:body`/`:text`/`:content`) → message content is **not scrubbed**
  anywhere. **[CODE-PROVEN]**

## 7. Root cause / explanation for each key behavior

- **Why the Super-Admin page doesn't touch webhooks:** it is a generic `InstallationConfig` editor (config groups in
  `app_configs_controller.rb:40-60`); webhooks are a *channel-lifecycle* concern handled by `WebhookSetupService` at
  channel creation, not a global config concern. The two are deliberately decoupled.
- **Why callbacks are per-number:** `WebhookSetupService#build_callback_url` hardcodes `/webhooks/whatsapp/<phone_number>`
  (`:75-80`) and registration runs per channel (`Channel::Whatsapp` create hooks). There is no global front door because
  Chatwoot registers each number's callback itself.
- **Why multi-WABA routing already works logically:** Meta sends one app's events to one callback; the events job was
  written for that (issue #4712) and resolves by payload `phone_number_id` rather than the URL (`whatsapp_events_job.rb:146-161`).
- **Why platform admins can read tenant messages:** there is no platform-level message browser, but **impersonation**
  and **super-admin self-add** both cross the account boundary, and `ConversationPolicy` authorizes by *account-scoped*
  role — so once "inside" an account, full read access follows.
- **Why audit is insufficient:** audit is an enterprise+premium overlay focused on model writes; impersonation and
  message *reads* were never in scope of the `audited` macros.
- **Why secrets/content leak to logs:** filtering acts on the auto-logged params hash only; explicit
  `Rails.logger.{debug,error}` interpolations and Sidekiq job args are outside that mechanism, and no body-scrubbing exists.

## 8. Feature-toggle insertion points (where ON/OFF must branch)

All of these are **wrap-not-replace** seams; OFF must leave them at current behavior.

| Concern | Insertion point (file:line) | ON behavior |
|---|---|---|
| Hide account WhatsApp UI | `channels/Whatsapp.vue`, `CloudWhatsapp.vue`, `WhatsappEmbeddedSignup.vue`, `360DialogWhatsapp.vue` + SPA route `settings/inboxes/new/whatsapp` | Hide/disable tenant-facing technical setup (read-only DTO flag drives it) |
| Restrict manual create API | `InboxesController#create` / `create_channel` (`inboxes_controller.rb:33-46,93-101`) | Deny `channel.type == 'whatsapp'` for tenant callers |
| Restrict embedded API | `Whatsapp::AuthorizationsController#create` (`authorizations_controller.rb:7-24`) | Deny tenant-initiated embedded signup |
| Ops-only setup path | new Bloomwire admin/ops service reusing `ChannelCreationService` / inbox create internally | Bloomwire performs setup on behalf of the customer |
| Webhook callback URL | `WebhookSetupService#build_callback_url` (`webhook_setup_service.rb:75-80`) | Point to Bloomwire global front door; reuse payload-metadata resolution |
| Routing registry writes | channel creation paths (`ChannelCreationService`, `InboxesController#create`) | Upsert additive Bloomwire routing row (no message/conversation duplication) |
| Privacy hardening | `SsoAuthenticatable` impersonation (`:27-31`), `SuperAdmin::AccountUsersController#create` (`:12-18`), log points (`filter_parameter_logging.rb`, `callbacks_controller.rb:25-30`, `base_service.rb:44-45`, `whatsapp_controller.rb:13`) | Restrict/audit impersonation + self-add; scrub tokens/bodies |
| Tenant DTO secret scrub | `app/app/views/api/v1/models/_inbox.json.jbuilder` (provider_config exposure) | Stop leaking `provider_config` to managed-tenant admins |

**Recommendation (for the later plan, not decided here):** a single central **feature-check service** consumed at
each seam, rather than scattered `ENV`/`feature_enabled?` checks.

## 9. What is proven [CODE-PROVEN]

1. Super-Admin WhatsApp-Embedded = 4 `InstallationConfig` keys, plaintext, read via `GlobalConfigService`; **no
   webhook generated** by that page.
2. Account WhatsApp setup has two paths (manual `CloudWhatsapp.vue` → `/inboxes`; embedded → `/whatsapp/authorization`),
   both creating `Channel::Whatsapp` + `Inbox`, both triggering **per-phone-number** webhook registration.
3. `provider_config` (jsonb) holds `api_key`/`phone_number_id`/`business_account_id`/`webhook_verify_token`/`source`;
   `phone_number` is the only unique key.
4. Inbound resolution `phone_number_id → Channel::Whatsapp → Inbox → Account` works independent of the URL, and the
   forward target (`WhatsappEventsJob` → incoming-message service) is reusable for a Bloomwire front door.
5. SuperAdmin ≠ Account Admin automatically; but SuperAdmin can **self-add** as `AccountUser` and can **impersonate**;
   either yields full account-scoped message access.
6. **Impersonation is unaudited**; audit logging is enterprise-overlay + premium-gated and never covers message reads/content.
7. Token/message-body leakage exists via explicit log calls + Sidekiq job args; param-filtering does not cover them.
8. The current `develop` baseline is pure Chatwoot, so OFF-preservation is achievable by wrapping these seams.

## 10. What is NOT proven [RUNTIME-TBD]

1. Live rendering/behavior of both UI pages (dev server was down) — no screenshots/DOM captured.
2. A real two-WABA inbound delivery actually landing in two different inboxes at runtime.
3. A Bloomwire-owned global ingress verifying signature with one app secret and forwarding without loss/dup.
4. An end-to-end outgoing injection preserving history + reconciling status at runtime.
5. The exact super-admin behavior/visibility after a live impersonation, and whether any audit row appears.
6. Whether secrets/bodies actually surface in the running app's logs/Sidekiq UI at production log levels.
7. Whether the super-admin settings form masks secret inputs in the rendered UI (controller returns raw values; UI
   masking not verified).

## 11. Required follow-up spikes (map to decision register)

| Spike | Goal | Register ref |
|---|---|---|
| **S-01** Multiple WA inboxes / one account | Create 2+ WA inboxes under one account; confirm no collision + correct routing | P-01 |
| **S-02** Multi-WABA webhook routing | POST two `phone_number_id`s; confirm each lands in the right inbox | P-02 |
| **S-03** Global webhook front-door | Bloomwire endpoint verifies one app secret + forwards to `WhatsappEventsJob` | P-03 |
| **S-04** Outgoing injection | API-inject outgoing; confirm `source_id` stored + status reconciles | P-04 |
| **S-05** Impersonation / privacy audit | Live-measure what a super-admin sees after impersonation + audit trail produced | P-05 |
| **S-06** Token/log scrubbing check | Trigger the debug/error/Sidekiq paths; capture exactly what leaks | P-05 |
| **S-07** *(new)* UI runtime smoke | Boot dev stack; confirm both pages render + secret masking; confirm OFF-baseline intact | C / Area A,B |

---

## Next step (not done here)

After this RCA is reviewed (and ideally S-01..S-07 run), proceed to the **final feature-toggle managed-onboarding
plan** (`bloomwire-feature-toggle-managed-whatsapp-onboarding-plan.md`) covering: feature-toggle strategy, Super
Admin console placement, account-workspace behavior, managed onboarding statuses, the additive routing registry,
the global webhook/router, and upgrade-safety/rollback. **No toggles implemented; no managed-onboarding plan written here.**
