<!-- Docs only. Bloomwire-owned change log. Kept current per AGENTS.md -> "Bloomwire Documentation Governance". -->

# Bloomwire Change Log

Docs-first change log for **Bloomwire-owned** changes. The full implementation reference lives in
[`implementation-ledger.md`](./implementation-ledger.md); the rule that keeps this file current is
`AGENTS.md` → **"Bloomwire Documentation Governance"** (introduced in Phase 15E.1).

Every entry should record: **phase · PR · merge SHA (once known) · summary · why · what was NOT
changed · validation · residual risks**, and (for security/permission/WhatsApp changes) state
explicitly: **no secrets exposed · no provider-credential mutation unless authorized · whether live
Meta/WhatsApp calls were made · whether Enterprise code was touched.**

---

## Unreleased / Pending Merge

### Phase 17D.2 — WhatsApp Business App Coexistence webhook proof — OPEN (in-flight, not merged)
- **PR:** _pending_ · **in-flight (NOT merged)** · **Type:** backend/webhook proof (specs + one minimal safe
  guard) + proof doc. **No frontend enablement · no DB migration/schema · no real Meta/WhatsApp calls (fake
  payloads only) · no native `/whatsapp/authorization` carve-out · no per-channel webhook override · no app-side
  duplicate chat storage · no secrets · no deploy · no production.**
- **Why:** prove the existing global webhook router (ADR-0005) + stock `Webhooks::WhatsappEventsJob` safely handle
  WhatsApp Business App **Coexistence** traffic before frontend enablement (17D.3). The Coexistence card stays
  **disabled / "Coming soon"** until then.
- **What (proven):**
  1. **Global router routing — safe, no change.** The router keys only on `metadata.phone_number_id` + channel
     alignment; it never inspects `connection_mode`, so a coexistence-created channel
     (`source=bloomwire_managed`, `connection_mode=coexistence`) routes identically. Wrong `phone_number_id` fails
     closed; routing is account-scoped.
  2. **`smb_message_echoes` — safe, already supported (no change).** The job routes echoes to
     `IncomingMessageWhatsappCloudService(..., outgoing_echo: true)` — the **outgoing** path — so an echo is not a
     duplicate inbound customer message; stays account/inbox-scoped; no secrets logged.
  3. **`smb_app_state_sync` — was unhandled → now safely ignored (minimal change).** Added an
     `app_state_sync_event?` guard + `handle_app_state_sync` to `Webhooks::WhatsappEventsJob`: it logs one
     redacted, content-free line and returns — **no inbound message processing, no message/conversation, no
     crash**. Echo + inbound behavior unchanged.
  4. **No duplicate storage** — no app-side chat/message tables; existing Chatwoot processing only.
- **Files:** `app/app/jobs/webhooks/whatsapp_events_job.rb` (only production change — the app-state-sync guard) ·
  `docs/bloomwire/whatsapp-coexistence-webhook-proof.md` (proof) · specs
  (`spec/services/bloomwire/webhooks/whatsapp_router_spec.rb`, `spec/jobs/webhooks/whatsapp_events_job_spec.rb`,
  `spec/support/bloomwire_whatsapp_e2e_helpers.rb`).
- **Not done (future):** **17D.3** frontend enablement (Coexistence card stays disabled until then).
- **Validation:** targeted `rspec` router + events-job = **43 examples, 0 failures**; broader webhook regression
  (router, job, PII logging, request logging, inbound e2e) = **58 examples, 0 failures**; RuboCop clean. **No real
  Meta calls** (fake payloads, no HTTP). Native flows unchanged; `BloomwireWhatsapp.vue` untouched (still disabled).

### Phase 17D.1 — WhatsApp Business App Coexistence backend contract — MERGED
- **PR:** #107 · **merge SHA** `ebdcba2831fd40330eaefd5a6dfe87f97a00b867` · **approved head**
  `67b63cdf3b5cd15c1ac0ec0271cf75d992ca1fc4` · **Status:** merged into `version_1` (final tip `ebdcba2`, after
  PR #106). **Type:** backend contract (account-scoped endpoint + service). **No frontend enablement · no DB
  migration · no real Meta/WhatsApp calls (mocked in tests) · no native `/whatsapp/authorization` carve-out · no
  per-channel webhook override · no secrets exposed · no deploy · no production.** (Dev remains at `9b09f9e`.)
- **Why:** the backend for **"Connect Existing WhatsApp Business App" (Coexistence)** — the option the 17C.3
  wizard shows **disabled / "Coming soon"**. This slice lands the endpoint + service contract only; the UI card
  stays disabled until a later frontend phase (17D.3).
- **What:**
  - **Endpoint** `POST /api/v1/accounts/:account_id/bloomwire/whatsapp/coexistence_embedded_signup`
    (`Api::V1::Accounts::Bloomwire::Whatsapp::CoexistenceEmbeddedSignupsController`), wired under the **same**
    account-scoped Bloomwire WhatsApp namespace as the 17C.2 `embedded_signup` route. Admin-only; **404/inert**
    unless native WhatsApp restricted AND `managed_whatsapp_onboarding` enabled; `Current.account`-scoped; safe
    DTO + sanitized errors. Native `/whatsapp/authorization` untouched.
  - **Service** `Bloomwire::WhatsappCoexistenceEmbeddedSignupService < Bloomwire::WhatsappEmbeddedSignupService`
    (17C.2). It **inherits the entire safe 17C.2 seam** — fail-closed readiness + encryption-before-token-storage,
    token exchange + phone info + **`subscribe_app_to_waba` only** (global router; never
    `override_waba_callback`/`subscribe_waba_webhook`/`channel.setup_webhooks`), encrypted token via
    `Bloomwire::WhatsappCredentialWriter`, non-secret `Bloomwire::WhatsappSetup` mapping — and only overrides two
    things: it marks the channel `provider_config['connection_mode'] = 'coexistence'` (source still
    `bloomwire_managed`) and adds `connection_mode: 'coexistence'` to the `channel` + `setup` sections of the safe
    DTO so Standard vs Coexistence are distinguishable without exposing any secret.
- **Not done (future slices):** **17D.2** webhook/coexistence proof; **17D.3** frontend enablement (the wizard
  Coexistence card stays **disabled/"Coming soon"** until then). No `WhatsappSetupRequest` removal.
- **Validation:** service spec (Meta stubbed — coexistence channel + `ready_for_webhook` mapping the router
  resolves; token only in provider_config; app-to-WABA subscribe, never per-channel override; fail-closed
  not-ready/encryption persist nothing) + request spec (admin allowed with `connection_mode: coexistence` on
  channel + setup; agent denied; 404 when Bloomwire OFF / onboarding OFF / native unrestricted; 422 not_ready /
  encryption; cross-account denied; body has no token/api_key/provider_config). **14 targeted examples, 0
  failures**; RuboCop clean; route resolves. **No real Meta calls** (service/client instance-doubles — no HTTP).

### Phase 17D.0 — WhatsApp Business App Coexistence discovery contract — MERGED
- **PR:** #106 · **merge SHA** `f9aeac7245bb6e9869c25233ed68377f77062e90` · **approved head**
  `1b8ae29dfb5183456548623c44e54e698fcd9994` · **Status:** merged into `version_1` (before PR #107). **Type:**
  discovery / docs only (`docs/bloomwire/whatsapp-coexistence-discovery.md`). **No code · no route · no frontend ·
  no DB migration · no real Meta/WhatsApp calls · no secrets · no deploy · no production.** (Dev remains at `9b09f9e`.)
- **Why:** lock the Coexistence backend contract (safe seam, credential/DTO boundary, global-router handoff) via an
  evidence/report-only discovery before enabling the disabled "Connect Existing WhatsApp Business App" card — so
  17D.1 could implement it without leaking credentials, duplicating messages, or weakening the native flow.
- **What:** the discovery document — current-`version_1` evidence, the intended `connection_mode=coexistence`
  contract, open questions, and the 17D.1/17D.2/17D.3 plan. No behavior change.
- **Validation:** docs-only (CI docs governance green on PR #106). No tests/code touched.

### Phase 17C.3 — Customer frontend WhatsApp connection wizard (connection-choice + number registration) — MERGED
- **PR:** #104 · **merge SHA** `bf81c7c62f5c9f8621142250e37b47e51b86ed82` · **approved head**
  `1bc432fcc127a5b78cf7c2bb6ca4c8ce4301f4bd` · **Status:** merged into `version_1` (new tip `bf81c7c`).
  **Type:** frontend feature (Vue). **No backend Ruby/routes/services/controllers change · no DB migration · no
  real Meta/WhatsApp calls (mocked in tests) · no native `/whatsapp/authorization` carve-out · no manual
  credentials UI · no "Add Agents" step · no secrets exposed · no deploy · no production.** (Dev remains at
  `9b09f9e`.)
- **Why:** the customer-facing UI on top of the 17C.2 endpoint — Settings → Inboxes → Add Inbox → WhatsApp
  Business → **choose a connection method** → register the number with Meta → ready inbox. Managed mode only;
  native flows untouched.
- **What:**
  - **Connection-choice screen (first step):** "Connect WhatsApp Channel" presents **two** options —
    (1) **Connect Existing WhatsApp Business App** (badge **Coexistence**) shown **disabled / "Coming soon"** with
    its prerequisites listed; it **never calls the backend** (no coexistence backend support yet); and
    (2) **Register New Number** (badge **Standard**, "Available now") which continues into the number-registration
    flow. Wording uses "Connect with Meta" / "Register WhatsApp number" / "Register New Number" — no "Connect
    Facebook" primary label.
  - **Capability plumbing:** `useBloomwireCapabilities` now exposes **`canSelfServeManagedWhatsapp`** — an opt-in
    capability that **defaults to FALSE** (unlike the stock-safe-true capabilities), so it only appears on an
    explicit server `true` (admin + native WhatsApp restricted + `managed_whatsapp_onboarding`); hidden in stock.
  - **Card + factory gate:** `ChannelList` shows the WhatsApp card in managed mode (even though native WhatsApp /
    inbox-creation are restricted), and `ChannelFactory` renders the new `BloomwireWhatsapp.vue` wizard **in place
    of** the native WhatsApp setup when the capability is granted. Agents (no capability) never see it.
  - **Wizard `BloomwireWhatsapp.vue`:** an optional inbox-name + WhatsApp-number **confirmation** form (NO App
    Secret / Verify Token / Webhook URL / API token / provider_config fields) → **"Register WhatsApp number" /
    "Connect with Meta"** launches Meta Embedded Signup (`useWhatsappEmbeddedSignup`) and posts **only** the
    non-secret signup credentials (code/business_id/waba_id/phone_number_id) to the 17C.2 endpoint via the new
    `inboxes/createBloomwireWhatsAppEmbeddedSignup` action + `WhatsappChannel.createBloomwireEmbeddedSignup`.
    Success renders a **safe DTO only** (inbox id/name, masked number from the backend/Meta source of truth,
    status Ready) with **Open inbox** + **Inbox settings** — and deliberately **no "Add Agents" step** (Chatwoot's
    existing inbox-agent management owns that). A customer-entered inbox name is applied best-effort via the
    existing inbox-update API (no endpoint contract change). Failures show a single sanitized generic message —
    "We couldn’t complete WhatsApp registration. Please try again or contact Bloomwire support." — never a raw
    Meta/server payload or token.
- **Not done (later slices):** **Coexistence backend** (the disabled card is UI-only until then); 17C.4
  verify/go-live UX; removal of the parked `WhatsappSetupRequest`.
- **Validation:** Vitest — `useBloomwireCapabilities` (default-false + explicit-true), `ChannelFactory` (wizard
  renders in managed mode / native otherwise / whatsapp_call unaffected), `ChannelList` (card shown only with the
  capability), and `BloomwireWhatsapp` (**choice screen: exactly two options; Coexistence disabled/coming-soon +
  8 prerequisites + never calls the backend; Register New Number continues to the form**; no credential fields;
  posts only signup credentials; success shows Open inbox + Inbox settings + **no Add-Agents route**; sanitized
  error hides raw payloads; cancel → no call; custom name → existing update API). **36 new/updated tests pass**;
  ESLint clean; i18n JSON valid. **No real Meta calls** (Meta SDK + store mocked). Native `Whatsapp.vue` and the
  native embedded-signup component are unchanged; stock behavior preserved (capability defaults false).

### Phase 17C.2 — Dedicated Bloomwire WhatsApp Embedded Signup endpoint + service — MERGED
- **PR:** #102 · **merge SHA** `84481ed1eeceadf91860f03a1515b01bb7d7abd4` · **approved head**
  `c8bd01e4b78165060539014d93a13f431dc1a12e` · **Status:** merged into `version_1` (new tip `84481ed`).
  **Type:** feature (account-scoped endpoint + service). **No DB migration · no frontend wizard · no real
  Meta/WhatsApp calls (all stubbed in tests) · no native `/whatsapp/authorization` carve-out · no
  `channel.setup_webhooks` / `override_callback_uri` · no secrets printed/returned · no deploy · no production.**
  (Dev remains at `9b09f9e`.)
- **Why:** implement the customer-side Embedded-Signup backend (ADR-0008) on the 17C.1 foundation, WITHOUT
  touching native embedded signup and WITHOUT weakening any native flow.
- **What:**
  - **Endpoint** `POST /api/v1/accounts/:account_id/bloomwire/whatsapp/embedded_signup`
    (`Api::V1::Accounts::Bloomwire::Whatsapp::EmbeddedSignupsController`). Admin-only (`check_admin_authorization?`);
    **404/inert** unless native WhatsApp is restricted AND `managed_whatsapp_onboarding` is enabled (the feature
    half of `canSelfServeManagedWhatsapp`); `Current.account`-scoped (no cross-account). Safe DTO only; sanitized
    generic error messages (never raw Meta payloads).
  - **Service** `Bloomwire::WhatsappEmbeddedSignupService`: fail-closed preflight (platform readiness via
    `GlobalWhatsappConfig#platform_ready`; **encryption required outside dev/test before any token storage**;
    code/waba present) → Meta steps (`Whatsapp::TokenExchangeService` + `Whatsapp::PhoneInfoService` +
    `FacebookApiClient#subscribe_app_to_waba` — **app-to-WABA subscription only, the GLOBAL router; never
    `override_waba_callback`/`subscribe_waba_webhook`/`channel.setup_webhooks`**) → atomic DB (a
    `source:'bloomwire_managed'` Cloud channel shell saved `validate:false` so no live `validate_provider_config`
    / no auto webhook / no template sync, then the encrypted token written via `Bloomwire::WhatsappCredentialWriter`,
    an `Inbox`, and the `ready_for_webhook` mapping via `Bloomwire::WhatsappSetupCreator`). Meta errors are
    sanitized to `:meta_error` (class-only logs) and persist nothing.
  - **Token/credential** stored ONLY in encrypted `Channel::Whatsapp#provider_config`; `Bloomwire::WhatsappSetup`
    holds only non-secret routing ids. Chatwoot remains source of truth for account/user/inbox/channel.
- **Not done (later slices):** frontend wizard (17C.3), verify/go-live UX (17C.4), manual fallback; no removal of
  `WhatsappSetupRequest`.
- **Validation:** service spec (Meta stubbed — bloomwire_managed channel + inbox + ready mapping the router
  resolves; token only in provider_config; app-to-WABA subscribe, no per-channel webhook/override; fail-closed
  not-ready/encryption/meta-error persist nothing) + request spec (admin allowed; agent denied; 404 when
  Bloomwire OFF / onboarding OFF / native unrestricted; 422 not_ready / encryption; cross-account denied; DTO has
  no token/api_key/provider_config). Native regression (embedded signup + inbox) **31 ex, 0 fail**; **full
  Bloomwire scope 700 examples, 0 failures (1 pre-existing pending)**; RuboCop clean. **No real Meta calls** (all
  stubbed via service/client doubles — no WebMock/HTTP).

### Phase 17C.1 — Backend foundation for customer WhatsApp Embedded Signup — MERGED
- **PR:** #100 · **merge SHA** `ac79a888e825f3c018924685c79c2bb47695e325` · **Status:** merged into `version_1`
  (new tip `ac79a88`; approved head `47b8b5e`). **Type:** backend foundation (capability + service + readiness).
  **No DB migration · no new store · no secrets stored/printed · no Meta/WhatsApp calls · no frontend wizard · no
  native `/whatsapp/authorization` carve-out · no deploy · no production.** (Dev remains at `9b09f9e`.)
- **Why:** first backend slice (C1 only) of the customer self-serve WhatsApp onboarding (Embedded Signup first,
  ADR-0008). Adds the seams a later wizard will use, with no behavior change to native flows.
- **What:**
  1. **New capability `canSelfServeManagedWhatsapp`** (`Bloomwire::Capabilities`) — `admin &&
     restrict_native_whatsapp_setup? && Bloomwire::Features.enabled?(:managed_whatsapp_onboarding)` (administrator
     **and** Bloomwire mode ON with native WhatsApp restricted **and** the explicit `managed_whatsapp_onboarding`
     feature enabled — which is master-gated **and privacy-dependent**, so privacy hardening is required too).
     Mutually-exclusive counterpart of `canManageNativeWhatsappSetup`; agents → false; Bloomwire OFF / feature OFF
     / privacy OFF / native-not-restricted → false. Existing capabilities (`canManageNativeWhatsappSetup`,
     `canCreateInbox`, …) unchanged. _(Review Blocker 1: gate on the existing managed-onboarding feature, not just
     the native restriction.)_
  2. **New service `Bloomwire::WhatsappSetupCreator`** — creates/updates the internal **non-secret**
     `Bloomwire::WhatsappSetup` router mapping (account/inbox/channel/phone_number_id/waba_id/display, status
     `ready_for_webhook`) for an **already-existing** channel+inbox. Accepts only explicit non-secret inputs
     (**no api_key/token/provider_config** — raises on such kwargs); idempotent per `channel_whatsapp_id`;
     fails closed (safe symbol errors) on cross-account inbox/channel, missing `phone_number_id`, or a
     `phone_number_id` already claimed by another channel. **When `ready_for_webhook`, it also enforces
     router handoff-safety** (mirrors `WhatsappRouter.channel_aligned_with_payload?`): Cloud (`whatsapp_cloud`)
     provider + `provider_config['phone_number_id']` match + `channel.phone_number == "+<display>"`, else
     `:unsupported_provider` / `:phone_number_id_mismatch` / `:display_phone_number_mismatch` (no value leaked) —
     so no "ready" row the global router would refuse is ever persisted. _(Review Blocker 2.)_ Creates **no**
     account/user/inbox/channel; **no** Meta call; never mutates `provider_config`.
  3. **Readiness:** `WHATSAPP_CONFIGURATION_ID` is now a **presence-only** Embedded-Signup prerequisite in
     `Bloomwire::GlobalWhatsappConfig` — missing → named blocker ("WHATSAPP_CONFIGURATION_ID is missing") + gates
     `platform_ready`; surfaced on the 17B page as Present/Missing (value never shown; it is not a secret). App
     Secret / verify token remain presence-only, values never rendered.
- **Not done (out of C1 scope):** no dedicated embedded-signup endpoint, no token exchange, no Meta API client
  calls, no app-to-WABA subscription, no frontend wizard, no Channel::Whatsapp/Inbox creation here, no manual
  fallback, no native `/whatsapp/authorization` carve-out, no `channel.setup_webhooks`.
- **Validation:** capability specs (feature ON→admin true when native restricted, feature OFF→false, privacy OFF→
  false, agent→false, OFF→stock, native caps not weakened) + `WhatsappSetupCreator` specs (create/idempotent/
  cross-account-reject/missing-pnid/pnid-conflict/**router-alignment: unsupported-provider + pnid-mismatch +
  display-mismatch fail closed**/no-secret/router resolves) + readiness specs (configuration_id present→no blocker,
  missing→blocker+not-ready). **Full Bloomwire scope 683 examples, 0 failures (1 pre-existing pending)**; RuboCop
  clean. Regression: SuperAdmin Global Config stays read-only; native `/whatsapp/authorization` stays blocked under
  managed restrictions; router + setup #1 unchanged.

### Phase 17B — SuperAdmin "Global WhatsApp Config" page (read-only) — MERGED
- **PR:** #98 · **merge SHA** `6eac9faf2cf50bf9910da4ae62179c73cfb96957` · **Status:** merged into `version_1`
  (new tip `6eac9fa`). **Type:** read-only SuperAdmin UI. **No DB migration · no new store · no secrets stored ·
  no deploy · no production · no Meta/WhatsApp calls.** (Dev remains at `9b09f9e`.)
- **Why:** complete ADR-0008 by turning the post-17A read-only WhatsApp Setups surface into a clean **Global
  WhatsApp Platform Config** page (webhook front-door + Meta-app credential *status* + router + readiness +
  connected-inbox list), instead of anything resembling customer setup/provisioning.
- **What:** new `Bloomwire::GlobalWhatsappConfig` (secret-free read-only summary) drives a rebuilt setups
  `index` → **Global WhatsApp Config**: global webhook callback URL · Meta App ID (public; **required
  readiness prerequisite** — Embedded Signup needs it, so a missing `WHATSAPP_APP_ID` blocks `platform_ready`) ·
  **App Secret / verify token = Present/Missing only** · router enabled/disabled · platform readiness + named blockers ·
  **"Last webhook received: Not tracked yet"** · read-only connected-inbox list (account, inbox, masked
  phone/`phone_number_id`, setup status, readiness). Nav → "WhatsApp › Global Config".
- **Secret-storage decision (owner-approved):** there is **no encrypted global-secret store** (InstallationConfig
  is plaintext; App Secret + verify token are **ENV/ops-managed** deployment secrets, read via
  `GlobalConfigService`). PR B is therefore **read-only**: it shows **presence only** via `config_present?`,
  **never displays or saves** App Secret / verify token, adds **no plaintext storage, no migration, no new store**.
  (Future editable secrets would need a separate encrypted `Bloomwire::PlatformConfig` design/ADR — parked.)
- **Not changed / not reintroduced:** no customer provisioning, no manual "New setup mapping", no account/user/
  inbox creation, no `Bloomwire::WhatsappSetup` create/edit here; router + webhook + setup #1 unchanged. Feature
  toggles stay on the existing "Bloomwire Features" page (linked, not duplicated). `WhatsappSetupRequest` still parked.
- **Validation:** new service spec (presence-only, never leaks values, callback URL, blockers, inbox count) +
  request specs (page renders; **secrets shown Present/Missing, values never rendered even when configured**;
  non-platform-admin blocked; master-OFF hides surface). **Full Bloomwire scope = 657 examples, 0 failures (1
  pre-existing pending)**; RuboCop clean. No deploy · no production · **no Meta/WhatsApp calls** · no secrets printed.

### Phase 17A — Remove SuperAdmin customer-provisioning + manual setup-mapping UI (architecture pivot)
- **PR:** #97 · **merge SHA** `8719de2` · **Type:** removal / dead-code. **No DB migration · no table drops · no data deleted.**
- **Why:** the SuperAdmin "Provision new WhatsApp customer" flow and the standalone "New setup mapping" CRUD
  were over-engineered and duplicated Chatwoot's native account/user/inbox responsibilities. New architecture
  (see ADR-0008): **SuperAdmin WhatsApp = Global WhatsApp Platform Config only; account/user creation stays
  native (SuperAdmin → Accounts/Users); customers complete WhatsApp setup from Account Settings → Inboxes → Add
  Inbox; the internal `phone_number_id → inbox/channel` mapping remains but is created by the customer-side
  wizard (PR C), not manual Ops UI.**
- **Removed:** `bloomwire_customer_provisionings` controller/route/view + `Bloomwire::CustomerProvisioningService`;
  the `new/create/edit/update` actions + `new`/`edit`/`_form` views of `bloomwire_whatsapp_setups` (route →
  `only: [:index, :show]`); the 16C `send_owner_activation` action + `Bloomwire::BusinessOwnerActivator` + the
  "Business owner access" card (redundant — native Devise invite/reset covers owner access now that provisioning
  is gone); nav "New Provision" link + index "Provision/New mapping/Edit" links + empty-state button; obsolete
  specs. Boundary/CRUD specs refactored off `CustomerProvisioningService`.
- **Kept intact:** global webhook + `Bloomwire::Webhooks::WhatsappRouter`; `Bloomwire::WhatsappSetup`
  model+table (**router mapping** — `ready_for_webhook.where(phone_number_id:)`); encrypted
  `Channel::Whatsapp#provider_config` + `Bloomwire::WhatsappCredentialWriter`; readiness calculator; the
  read-only setups index/show/readiness/credentials surfaces (transitional → Global Config in PR B). **Existing
  setup #1 / account #1 data untouched; router still resolves it.**
- **Parked:** `Bloomwire::WhatsappSetupRequest` intake queue is **deprecated** (superseded by the PR C wizard) —
  **not removed in 17A**; kept read/update-only, table retained (future removal = a separate data-cleanup migration).
- **Validation:** new routing spec proves removed routes are absent (create/edit/update/provision/activation) while
  index/show/readiness/credentials + parked setup-requests stay routable; **full Bloomwire spec scope = 647
  examples, 0 failures (1 pre-existing pending)**; router + whatsapp_events_job regression green; RuboCop clean.
  No deploy · no production · no Meta/WhatsApp calls · no secrets · no DB drops.

### Phase 16C — Business-owner activation (set-password after provisioning)
- **PR:** #95 · **merge SHA** `9b09f9e` · **Type:** owner-only SuperAdmin/Ops action. **No DB migration.**
- **Why:** `CustomerProvisioningService` creates the business owner **confirmed with a throwaway password and no
  email**, so a provisioned owner had no way to log in. This adds the missing activation step.
- **What:** a **"Send activation email"** action on the WhatsApp **setup detail** page
  (`POST .../bloomwire_whatsapp_setups/:id/send_owner_activation`). It sends Devise **set-password (reset)
  instructions** to the setup account's **administrator(s) only** (never agents) via the new
  `Bloomwire::BusinessOwnerActivator` (mirrors `PlatformAdminInviter#send_password_setup`, best-effort/rescued).
  Owner then sets a password and signs in to the **native** Chatwoot WhatsApp inbox.
- **Reuse, not duplication:** uses native `Account#administrators` + Devise `recoverable`. Creates **no new**
  accounts/users/account_users/inboxes/conversations/messages; changes **no roles**; creates **no** `PlatformAdmin`
  grant; **no** global `BusinessOwner`; does not duplicate data. **The only intended mutation** is Devise's
  recoverable/reset-password fields (`reset_password_token` digest + `reset_password_sent_at`) on the targeted
  administrator user(s), needed to send the set-password instructions.
- **Security:** gated by the existing `/super_admin` platform-admin boundary + master-mode (`ensure_bloomwire_mode_enabled`);
  **never** exposes the reset token/password/link in UI, logs, or audit; safe audit via `AdminUserAudit`
  (field-names only); SMTP failure is rescued (no 500).
- **Validation:** service spec + request spec (admin-only targeting, authorization, master-OFF unavailable,
  no-platform-grant, no-new-records / no-role-change, safe audit, no-secret, SMTP-failure) — **15 examples, 0 failures** on the
  new specs; setups/readiness/provisioning/credentials regression green; RuboCop clean. No deploy; no Meta/WhatsApp
  calls; no secrets.
- **Files:** `app/services/bloomwire/business_owner_activator.rb` (new) · `super_admin/bloomwire_whatsapp_setups_controller.rb`
  · `config/routes.rb` · `views/super_admin/bloomwire_whatsapp_setups/show.html.erb` · specs · docs.
- **DEV runtime (2026-06-30 → 2026-07-01) — `DEV PASS` (end-to-end):** deployed `version_1 @ 9b09f9e` to dev
  (deploy run `28461253274`; rails+sidekiq `/app/.git_sha` match · health 200 local+public · 0×5xx · postgres/redis
  volumes preserved · no pending migrations). **Feature end-to-end verified on dev:** the setup-detail **"Business
  owner access"** card renders, **"Send activation email"** works and targeted the **real account administrator**
  `User #2` / `sameen@bloomwire.lk` (account #1 admin). The owner **received the email, set a password, logged in,
  and reached the native Chatwoot inbox** — confirmed. `reset_password_sent_at` was set at send-time then **cleared
  by Devise after the successful reset** (expected; `reset_password_token` also cleared = consumed). Safe audit row
  written (`action=send_owner_activation`, field-names only: `changed_fields=[]`, `blocked_fields=[]`); **no** reset
  token/password/link exposed in UI/audit/docs; **no** `PlatformAdmin` grant created by the activation (`User #2`'s
  pre-existing `owner` grant is old — **0** new grants in the last 30m/12h); roles unchanged (`User #2`=administrator;
  `sameen.android@gmail.com` / `User #50`=agent, SMTP sender/dev only, never made admin); **no** Meta/WhatsApp calls;
  **no** production deploy. SMTP verified with booleans/masked output only — no secrets printed. (Devise tokens do
  appear in Sidekiq job-arg logs for all Devise emails — pre-existing Chatwoot behavior, not 16C.)
- **Mailer root cause & fix (why the earlier block cleared):** the earlier `PASS-BUT-BLOCKED` was caused by the dev
  **global SMTP env being empty**, so stock Chatwoot `config/initializers/mailer.rb` correctly fell back to
  `:sendmail`, which had no working MTA → `Errno::EPIPE` (no delivery). Phase 15F **templated** emails worked because
  they use the **DB-backed `Bloomwire::EmailSetting`** SMTP path; Devise/16C use the **global ActionMailer (ENV)**
  path. **Fix (operational, dev only):** populated the dev global `SMTP_*` env from the owner's local
  `#PERSONAL EMAIL SETTINGS` block (`SMTP_PORT=587`, STARTTLS on) and **recreated rails + sidekiq** →
  `delivery_method=:smtp` on both. **No `Bloomwire::EmailSetting` change · no code change · no credential values
  printed · no production deploy.**

### Docs — Product framing correction
- **PR:** _pending_ · **Type:** docs-only (no code, no runtime behavior, no deploy).
- **What:** corrected the misleading "WhatsApp-first SaaS product" wording to the canonical framing —
  **Bloomwire is a managed business messaging SaaS platform built additively on the Chatwoot engine.**
  Chatwoot remains the technical engine + source of truth (accounts, users, account_users, inboxes, contacts,
  conversations, messages). **WhatsApp is the first go-to-market managed channel / current implementation
  priority — not the permanent product boundary;** future channels (SMS, Microsoft, Instagram, Telegram, …) may
  be added later without replacing the Chatwoot foundation. WhatsWay/WhatsAway = inspiration/benchmark only.
  Also corrected the ledger §1 "WhatsWay / Chatwoot-derived OSS base" wording to "built additively on the
  Chatwoot engine."
- **Files:** `docs/bloomwire/PROJECT-CONTEXT.md`, `docs/bloomwire/SESSION-LOG.md`, `AGENTS.md`, `CLAUDE.md`,
  `docs/bloomwire/implementation-ledger.md` + `.html`, `docs/bloomwire/change-log.md`.
- **Preserved invariants:** Chatwoot Accounts/Users; business owner/admin = `account_users.role administrator`;
  staff/agent = `account_users.role agent`; Bloomwire adds managed channel setup/binding/control-plane (not a
  duplicate account/user system); no global `BusinessOwner`; no duplicate conversations/messages/contacts; no
  overbuilding multi-channel now. **No code, no migration, no deploy, no secrets.**

### Phase 15F.UI — Email Templates UI Polish & Responsive Upgrade
- **PR:** #90
- **Merge SHA:** `88e07010ddd7cea743cf1f02a91b5851ee8e43ac` (merged into `version_1`)
- **Dev status:** **DEV PASS** — deployed to dev (`88e0701`), runtime QA passed 2026-06-30: responsive CSS rules
  live — **1440 = 3 columns** (library | editor | sample preview); **1280/1024 = 2 columns + sample preview
  full-width below**; **768 = stacked**. Owner-only gate intact; no migration; SMTP unchanged; no
  DNS/SMTP/WhatsApp/Meta changes; no secrets.
- **Type:** Owner-only SuperAdmin **UI/UX + responsive** polish for Email Settings → Email Templates.
  **CSS + view-wrapper only — no behavior, controller, model, route, or DB change.**
- **Why:** the flow worked but felt cramped/dense, the panels competed, the Send-from-Template composer sat too
  low and under-emphasised, the toolbar was cramped, the preview read like a debug area, and the 3-panel grid
  jumped straight from 3 columns to 1 at 1200px (no graceful medium/tablet reflow).
- **What changed (all in `super_admin/index.scss` + 3 ERB partials; every form/link/id/validation/button-state
  preserved):**
  - **Responsive 3 → 2 → 1 grid:** `bw-email-grid` is `library | editor | sample-preview` on desktop; at
    ≤1280px it becomes `library | editor` with the sample preview reflowing full-width below; at ≤880px it stacks.
  - **Toolbar:** search takes its own row, then category + Filter wrap below — never crowded in the narrow column.
  - **Template list:** scrollable list, hover lift, and an accent left-bar on the active row.
  - **Polished preview:** both the Sample preview and the composer's Final preview render inside an email-client
    "window" frame (`bw-preview-frame`) so they read as product previews, not a debug dump. (Same shared
    branded-email partial — preview still equals delivered email.)
  - **Prominent Send section:** a clearly separated section header ("Send a real email from this template") above
    an **accent-topped** composer card (`bw-card--composer`); the composer's form/preview split is now a
    responsive `bw-composer-grid` (2-col → 1-col ≤980px).
  - **Spacing/hierarchy:** larger panel padding + grid gaps for breathing room.
- **Not changed:** no SMTP credential/provider change; no DNS; no WhatsApp/Meta; no DB migration; no controller/
  model/route change; owner-only gate intact; CTA-label interpolation + send-feedback banner + button states
  unchanged.
- **Validation:** Bloomwire email request specs (render the templates tab + composer + previews) green
  (**53 examples, 0 failures** on the render specs); SCSS compiles (Vite build CI); **dev runtime QA passed**
  on `88e0701` (responsive grid rules live at 1440/1280/1024/768, owner-only gate intact). Before/after
  screenshots = owner-assisted (MCP browser had no authenticated owner session).
- **Scope note:** Templates tab + shared page shell/status cards only; other Email Settings tabs untouched.

### Phase 15F.6 — Email CTA Button Rendering Fix
- **PR:** #89
- **Merge SHA:** `53e3e7bffacbede7f0515ed82cffbd04c9693fca` (fast-forwarded into `version_1`)
- **Dev status:** **DEV PASS** — deployed to dev (`53e3e7b`), runtime QA passed 2026-06-30: scheme-less CTA URL
  blocked before SMTP; valid `https://` renders the email-safe purple button (absolute href); delivered HTML has
  no `[www.google.com]Accept Invitation`; text fallback `Accept Invitation: https://…`; preview == delivered.
- **Type:** Owner-only SuperAdmin email-rendering + validation bugfix (Send from Template CTA). **No DB migration.**
- **Root cause:** the template's stored `cta_url` (`{{invitation_link}}`) passed the template-level
  `cta_url_safe_scheme` validation (placeholder is allowed), but the **RESOLVED** CTA URL (after the owner fills a
  variable) was **never validated**. A scheme-less value like `www.google.com` flowed through `SendTemplateEmailService`
  to the mailer, producing a **relative `<a href="www.google.com">`**. Email clients (e.g. Gmail) neutralize a
  relative/scheme-less href in HTML email, so the styled button collapsed to raw text and the URL leaked —
  delivered as `[www.google.com]Accept Invitation` instead of a purple button.
- **What changed:**
  - **Resolved-URL validation:** new `Bloomwire::EmailTemplate.absolute_cta_url?` (requires absolute
    `http(s)://`). `SendTemplateEmailService` now **blocks before SMTP** with `invalid_cta_url` when a CTA link is
    present but not absolute — message: *"Enter a full URL starting with https:// for the button link
    (e.g. https://example.com)."* (Also blocks `javascript:`/`data:` injected via a variable value.)
  - **Email-safe button:** the shared `_branded_email.html.erb` now renders the CTA as a **table + `td bgcolor`**
    button (robust across Outlook/Gmail/Apple Mail), inline styles only, label + href HTML-escaped, and only when
    the URL is absolute — so a broken/relative button is never emitted.
  - **Preview == delivered:** the composer disables Send + shows a *"Button link must be a full URL"* block when
    the resolved link is not absolute, and the Final preview (same shared partial) hides the button — matching the
    blocked send (no fake working button).
  - **Text fallback** unchanged and correct: `Accept Invitation: https://…` (never `[url]label`).
- **Not changed:** no DB migration; no SMTP secret/credential change; no DNS; no WhatsApp/Meta; no auth/audit
  (15G.2/15G.3) behavior; CTA label interpolation (15F.2) and send-feedback UX (15F.3) preserved.
- **Validation:** model unit (`absolute_cta_url?`), service (scheme-less blocks pre-SMTP, absolute sends, no-CTA
  sends), mailer (table button + absolute href + no `[url]label`; defense-in-depth skip for non-absolute), request
  (composer block + message, valid send, preview block-state). Full Bloomwire email + 15G.2 + 15G.3 suite
  **123 examples, 0 failures**; RuboCop clean. No SMTP secret in body/logs.

### Phase 15F.3 — Email Send Feedback UX Polish
- **PR:** #86
- **Merge SHA:** `bf6aa15d8816a2276365ca6e0451e16e6023ba0c` (fast-forwarded into `version_1`)
- **Dev status:** **DEV PASS** — deployed to dev (`bf6aa15`), runtime QA passed 2026-06-30: composer-local
  success/blocked/invalid banners visible at `#bw-composer`, redirect keeps `template_id`, Email Logs success +
  blocked rows recorded, double-send guard present, no SMTP secret in any rendered HTML.
- **Type:** Owner-only SuperAdmin UX (Send-from-Template feedback). **No DB migration.**
- **Why:** After a template send the only feedback was a flash at the **top** of the page; the page appeared to
  just refresh, so the owner couldn't tell whether the email was sent, blocked, or failed.
- **What changed:**
  - **Composer-local result banner:** the "Send from Template" composer now renders a visible
    success/blocked/failed banner (`#bw-send-result`) right at the composer — success → *"Email sent
    successfully to <recipient>"*, blocked/failed → *"Email was not sent: <safe reason>"* (colour-coded by
    status; `role="status"`/`aria-live`). The global flash still shows too.
  - **Land on the composer:** `send_email` redirects to the Email Templates tab with the selected
    `template_id` **and `#bw-composer` anchor**, so the owner lands on the result without scrolling. CRUD redirects
    unchanged.
  - **Status + Email Logs link:** the banner shows the latest delivery-log status/time/recipient for the template
    and a **"View Email Logs"** link.
  - **Double-send guard:** the Send button uses `data-disable-with="Sending…"` (rails-ujs/Turbo) so a second
    click during submit is avoided.
  - **Consistent messaging:** `SendTemplateEmailService` result messages standardised to the
    "sent successfully" / "was not sent: <reason>" shape; Email Log status (success/blocked/failed) matches the
    banner. No SMTP secret or raw exception secret is ever shown (errors stay sanitized).
- **Not changed:** no DB migration, no SMTP secret/credential change, no WhatsApp/Meta, no auth/audit (15G.2/15G.3)
  behavior; existing successful send/log behavior preserved (all three outcomes still write an Email Log row).
- **Deferred follow-ups:** (a) **composer "Update preview" GET query-string hardening** (POST-based preview) →
  **Phase 15F.5** (future); (b) **Email deliverability / domain authentication** → **Phase 15F.4** (PR #87,
  report-only / docs-only); (c) optional **auth-audit polish** → **Phase 15G.4** (future).
- **Validation:** send request specs (incl. visible-result-near-composer for success/blocked/invalid, composer
  anchor, template stays selected, Email Log row, no-secret); full Bloomwire email + 15G.2 + 15G.3 suite
  **113 examples, 0 failures**; RuboCop clean.

### Phase 15F.4 — Email Deliverability + Domain Authentication (investigation, report-only)
- **PR:** _pending_
- **Merge SHA:** _pending merge_
- **Type:** **Investigation / documentation only.** No code · no DB migration · **no DNS change** · **no SMTP
  credential change** · **no production deploy** · **no WhatsApp/Meta/provider credentials touched**.
- **Why:** Email send + template UX are DEV PASS and mail is actually delivered, but messages to the owner's
  `bloomwire.lk` mailbox land in **junk/spam** instead of the inbox. This entry documents the current dev sending
  behavior, why it can be junked, and the recommended production setup. (Formalises the deliverability follow-up
  noted under Phase 15F.3; tracked separately so 15F.3 stays scoped to the Send Feedback UX.)
- **Current dev SMTP behavior (read-only, masked):** `smtp.gmail.com:587`, `login` auth + STARTTLS; SMTP username
  **and** `from_email` are both `@gmail.com` (**personal Gmail**, not Google Workspace for `bloomwire.lk`); From
  display-name is `"Bloomwire"`; no Reply-To and no Return-Path override (envelope sender = the gmail.com username).
  Password present (length only) — never printed.
- **Why it can land in junk (diagnosis):** This is **not** an SPF/DKIM/DMARC *failure*. Sending *as* `gmail.com`
  through Gmail's own authenticated servers means SPF passes, DKIM is signed `d=gmail.com`, and DMARC is aligned for
  `gmail.com` → auth passes. The spam-foldering is a **brand-identity / reputation / content** problem:
  (1) brand display-name `"Bloomwire"` on a **free `@gmail.com`** address (display-name impersonation heuristic);
  (2) branded content whose CTA/invite links point to **dev.unecast.com** (sender domain ≠ link domain; a
  low-reputation dev host) — a classic phishing signal; (3) **no sending reputation** for the `bloomwire.lk` brand
  because the brand domain is not the actual sender. _(Pending owner confirmation from the junked message's
  `Authentication-Results` / `Received-SPF` / DKIM `d=` / `From` / `Return-Path` headers.)_
- **Recommended production setup (NOT applied — requires owner DNS/provider action):**
  - **Dedicated sending subdomain:** `mail.bloomwire.lk` or `notify.bloomwire.lk`.
  - **Transactional provider:** Postmark / Resend / AWS SES / Mailgun / SendGrid / Brevo.
  - **SPF (do not replace existing):** put SPF on the **subdomain only** — `v=spf1 include:<provider> -all`; leave
    the root `bloomwire.lk` SPF untouched.
  - **DKIM:** publish the provider's DKIM selector CNAME/TXT on the subdomain.
  - **DMARC:** start `_dmarc.bloomwire.lk` `v=DMARC1; p=none; rua=mailto:dmarc@bloomwire.lk` (monitor), then tighten
    to `quarantine` → `reject` after alignment is confirmed.
  - **From == authenticated domain:** e.g. `noreply@mail.bloomwire.lk` (From domain == DKIM domain → alignment +
    brand match); set a real **Reply-To** if replies are wanted.
  - **Links:** production CTA/links use the real brand/app domain (not `dev.unecast.com`).
  - **Bounce/complaint handling:** enable provider webhooks → record into the Email Logs.
- **App send flow:** unchanged and still **PASS** — this is a deliverability/DNS/provider matter, not an app bug.
- **Impact:** **Does NOT block Phase 16 dev work** (dev mail is delivered). **Blocks production / client email
  readiness** until the DNS/provider setup above is completed.
- **Validation:** read-only SMTP-config inspection on dev (masked, no secrets printed); no code/tests changed;
  docs-only.

### Dev QA Sign-off — 2026-06-30 (owner-confirmed)
Independent dev-server runtime QA on `version_1` @ `ea3487b624d896601247fd0baf2c574e4f11820b`. Owner confirmed
receipt of both dev QA emails: **"You're invited to join QA Biz Ltd on Bloomwire"** and **"Hello there"** (CTA
"Open Globex"). Sign-off:

| Area | Status |
|---|---|
| Auth Integrity (Phase 15G.2) | **DEV PASS** |
| Auth Go-Live Guardrails (Phase 15G.3 — admin-edit audit + auth smoke) | **DEV PASS** |
| Email Settings / SMTP (Phase 15F) | **DEV PASS** |
| Email Templates UX Completion (Phase 15F.2) | **100% DEV PASS** |

- **No production deploy** was performed; **audit rows were not purged**; **no WhatsApp/Meta/provider
  credentials** were touched.
- **Phase 16 is READY to start** (all auth + email flows are DEV PASS and the email receipts are confirmed).

**Phase roadmap / numbering (authoritative):**

| Phase | Scope | Status |
|---|---|---|
| **15F.2** | Email Template UX Completion | **100% DEV PASS** (PR #84, merged `ea3487b`) |
| **15F.3** | Email **Send Feedback UX Polish** | PR #86 — **pending review/deploy** (held for review) |
| **15F.4** | Email **Deliverability + Domain Authentication** | PR #87 — **report-only / docs-only** |
| **15F.5** | **POST-based composer preview / query-string hardening** | **future follow-up** (not yet started) |
| **15G.4** | Optional **auth-audit polish** (record `type` in `blocked_fields`, trim `changed_fields` noise) | **future follow-up** |

> Note: the POST-based composer preview / query-string hardening is **Phase 15F.5** — it is **not** 15F.3
> (15F.3 is the Send Feedback UX Polish). Earlier drafts that called it "15F.3" have been corrected.

### Phase 15F.2 — Email Template UX Completion + QA Findings Polish
- **PR:** #84
- **Merge SHA:** `ea3487b624d896601247fd0baf2c574e4f11820b` (fast-forwarded into `version_1`)
- **Dev status:** **100% DEV PASS** — deployed to dev (`ea3487b`), runtime QA passed, owner confirmed receipt of
  both dev QA emails on 2026-06-30 (see "Dev QA Sign-off" below).
- **Type:** Owner-only SuperAdmin UX/correctness (Email Templates composer + send + logs). **No DB migration.**
- **Why:** Dev QA passed core flows on `ba76e21`, but Email Templates was **not 100% done** — the composer
  only generated 6 fixed inputs, the preview silently used SAMPLE data for blank variables while the real send
  sent blank (preview ≠ delivered), invalid emails were only caught by SMTP, and Email Logs showed the template
  name but not the literal sent subject. This PR closes those gaps to make Email Templates production-usable
  before Phase 16.
- **What changed:**
  - **Dynamic composer variables:** `Bloomwire::EmailTemplate#used_variables` now parses **every** `{{variable}}`
    in subject + body + CTA link (de-duplicated, custom variables supported), and the composer generates one
    input per detected variable with a humanized label (`recipient_name → Recipient name`,
    `custom_order_id → Custom order id`).
  - **One resolver for preview + send:** new `EmailTemplate#composition_for` / `#resolved_variables` /
    `#missing_variables` are the SINGLE source both the live "Final preview" and the real send use, so the
    preview equals the delivered email. Blank variables are **never** silently filled with SAMPLE data — they
    stay as visible `{{placeholders}}` and the send is blocked.
  - **Blank-on-first-load (review fix):** the composer opens with **empty** variable inputs — `SAMPLE_VARS` are
    shown only as **placeholder/helper text** (and in the separate "Sample preview"), never prefilled as real
    values. The Send button stays disabled until the owner intentionally fills every required variable, so
    sample data can never be accidentally sent.
  - **CTA button label (review fix):** the CTA **label** is now included in variable detection
    (`used_variables`), interpolation (`composition_for`), and the leftover-`{{placeholder}}` block
    (`SendTemplateEmailService`). A `{{variable}}` used **only** in the button label now generates a composer
    input, renders identically in the preview and the delivered email, and **blocks the send** if left unfilled —
    completing the "no raw `{{placeholder}}` is ever delivered" guarantee (subject/body/CTA URL unchanged).
  - **Validation (pre-send):** `SendTemplateEmailService` now blocks an **invalid recipient email** and **any
    leftover `{{placeholder}}`** (subject, body, CTA label, CTA URL) before opening SMTP (in addition to missing
    recipient / SMTP not ready), with a blocked Email Log + clear message. The composer shows an inline "fill
    these in" warning and disables Send.
  - **Email Logs:** the tab now shows the **literal sent subject** (already stored per-send) alongside
    template, recipient, status, actor, timestamp.
  - **Sample preview** (editor Panel 3) relabeled "Sample preview / Sample data only — not the send preview".
- **Template CRUD:** create / edit / duplicate / deactivate(archive) / reactivate behavior preserved; a new
  custom-variable template now flows create → save → generated input → preview → send → log.
- **Not changed:** no DB migration, no SMTP secret/credential change, no WhatsApp/Meta, no Auth-Integrity
  (15G.2) or admin-audit (15G.3) behavior. Existing successful send/log behavior preserved (now requires all
  variables filled).
- **Deferred follow-ups:** (a) the composer's "Update preview" uses a GET round-trip, so composer values appear
  in the preview URL query string — tracked as **Phase 15F.5** (POST-based preview / query-string hardening); not
  fixed here (out of scope, not risk-free). (b) optional auth-audit polish (record `type` in `blocked_fields`,
  trim `changed_fields` noise) → **Phase 15G.4**.
- **Validation:** model + service + send-request specs (incl. dynamic vars, custom vars, CTA-label vars,
  preview==send, blank-blocks, invalid-email-blocks, blank-on-first-load); full Bloomwire email + 15G.2 + 15G.3
  suite **109 examples, 0 failures**; RuboCop clean. No secrets in code/logs/specs (fake values only).
- **Phase 16 remains BLOCKED** until this PR is merged, deployed to dev, and runtime QA passes.

### Phase 15G.3 — Auth Go-Live Guardrails (audit + smoke + runbook)
- **PR:** _pending_
- **Merge SHA:** _pending merge_
- **Type:** Security/audit guardrails (SuperAdmin console + ops; one additive table; no behavior change to
  business/account roles, WhatsApp, or secrets)
- **Why:** finalize auth guardrails before go-live, building on 15G.2. The prior RCA had **no provable trail**
  of who/what mutated a user; this adds one, plus a documented login smoke and runbook rules.
- **What changed:**
  - **Audit trail:** new Bloomwire-owned table `bloomwire_admin_audit_logs` + `Bloomwire::AdminAuditLog` +
    `Bloomwire::AdminUserAudit`. Every `super_admin/users#update` records one row: `actor_id`, `target_user_id`,
    `controller`, `action`, `changed_fields` (columns changed), `blocked_fields` (auth-sensitive params that were
    submitted but stripped by 15G.2). **Field NAMES only — never values.** Auditing never breaks the request.
  - **Auth smoke:** `.github/scripts/auth-smoke.sh` — optional, operator-run dev/staging login smoke using a
    **dedicated disposable test admin**. Enforces a **host allowlist (default-deny)** — only `dev.unecast.com`
    (+ `SMOKE_ALLOWED_HOSTS` for a future staging host) is allowed; every unknown host, incl. production, is
    refused. Also refuses the owner account; password read from a file (never argv/`ps`); `SMOKE_VALIDATE_ONLY=1`
    runs just the guards; verifies sign-in + deployed `/app/.git_sha`. Not auto-wired (no test-admin secret in
    CI). Guard contract is covered by `spec/scripts/bloomwire_auth_smoke_spec.rb`.
  - **Runbook §7:** password changes only via Devise reset (never the generic Users edit), the audit
    fields/exclusions, and the auth-smoke procedure.
- **Auth fields never stored in the audit:** `password`, `password_confirmation`, `encrypted_password`,
  `reset_password_token`, `reset_password_sent_at`, raw hashes, secrets.
- **Dev runtime verification (15G.3 task 1):** dev deployed SHA `f140717…`; owner account login-ready
  (SuperAdmin, confirmed, owner active, recovery reset applied — fingerprint changed); `/super_admin/sign_in`
  = 200; the deployed code carries the 15G.2 edit-form/param protections (CI spec green on `f140717`).
- **Not changed:** no rollback, no password reset (recovery already done separately), no production change, no
  WhatsApp/Meta/provider credentials, no business/account role semantics, no Devise/secret/session config.
- **Validation:** RuboCop clean; new audit request spec (3) + 15G.2 auth-integrity (10) + user-flow (6) green;
  `bash -n` on the smoke script OK. No secrets/hashes printed (specs assert no secret value lands in the audit).
- **Migration:** `20260630000001_create_bloomwire_admin_audit_logs` (additive). **Deploy required:** Yes after
  review/merge (runs the migration); not performed here.

### Phase 15G.2 — Auth Integrity Hardening (before go-live)
- **PR:** _pending_
- **Merge SHA:** _pending merge_
- **Type:** Security hardening (SuperAdmin console; no DB data change, no deploy)
- **Why:** Forensic RCA of an owner login failure (`sameen@bloomwire.lk` rejected with "Invalid Password")
  found **no** deploy/permissions/secret cause (secret + Devise pepper stable; `grant!`/`revoke!`/`reactivate!`/
  inviter(existing)/`EnsurePlatformOwnerService` never touch user auth; no migration/seed mutates the hash). The
  **only** code path that could change an existing SuperAdmin's password was the **generic Administrate User
  edit form's password field** (a non-blank submit, e.g. **browser autofill**). This PR closes that vector.
- **What changed (minimal):**
  - `UserDashboard#form_attributes` drops **`:password`** and **`:confirmed_at`** from the **edit** form (new-user
    create still sets an initial password). The edit form no longer renders a password input.
  - `SuperAdmin::UsersController#resource_params` strips an auth-sensitive denylist **on update only** —
    `password, password_confirmation, encrypted_password, reset_password_token, reset_password_sent_at,
    confirmed_at` — defense-in-depth so the generic edit can never mutate them even if a field is force-posted.
    `:type` remains stripped in Bloomwire Mode (unchanged). Password changes go **only** through the Devise
    reset flow.
- **Auth-sensitive fields now protected from the generic Users edit:** `encrypted_password`, `password`,
  `password_confirmation`, `reset_password_token`, `reset_password_sent_at`, `confirmed_at`, `type`.
- **Not changed:** no DB data, no password reset, no rollback, no migrations, no deploy, no Devise/secret/session
  config, no platform-admin/account-role logic. New-user create + the platform-admin invite (new email) still set
  an initial password as before.
- **Security:** no secrets/hashes printed; specs compare only SHA-256 fingerprints of the stored hash.
- **Validation:** RuboCop clean; **new auth-integrity request spec (10 examples)** + regression on the related
  super_admin specs (**48 examples**) green. Tests: generic edit (name) keeps hash · force-posted password on
  update ignored (original still valid, injected rejected) · edit form renders no password field · confirmed_at
  not settable via generic update · grant/revoke/reactivate leave hash/type/confirmed_at · inviter(existing) keeps
  hash · account-role assignment leaves hash/type/confirmed_at · non-owner access unchanged.
- **Deploy required:** Yes (after review/merge; not performed here). Owner login recovery (password reset) is a
  separate, approval-gated step — **not** in this PR.

### Phase 15G.1 — Fix false-success dev deploy (stdin-consumed deploy script)
- **PR:** _pending_
- **Merge SHA:** _pending merge_
- **Type:** CI/CD bugfix (infra-only; no application runtime code)
- **Summary:** The manual Dev/Staging deploy could report **success while leaving the app on the OLD build**.
  `deploy-remote.sh` is piped to the server via `ssh … bash -s`, and `docker compose run --rm rails db:migrate`
  attached **stdin** — so it **consumed the rest of the piped script**. After `db:migrate`, bash hit EOF and
  exited `0`, silently skipping **step 4 (recreate rails+sidekiq)**, **step 5 (smoke: health + SHA verify)**, and
  step 6. The migration applied, but the running containers were never swapped and the smoke checks never ran.
- **Fix (one line):** `… run --rm -T rails bundle exec rails db:migrate </dev/null` — `-T` disables stdin/TTY
  attach and `</dev/null` guarantees the command cannot read the piped script. (`up -d` is detached and the
  smoke `exec -T` was already safe; this was the only `compose run`.)
- **Why it matters:** prevents a false-positive deploy where dev silently runs stale code; smoke now actually
  gates success (health 200 + in-container `/app/.git_sha` == target SHA).
- **Observed once on dev:** deploy of `version_1` (`3bf260f`) created the `bloomwire_email_delivery_logs` table
  but left `app-rails-1` on `fdf94d8`; caught by independent `/app/.git_sha` verification. A corrected re-deploy
  is required to actually run `3bf260f` (migration is idempotent; no rollback needed — additive table).
- **Not changed:** no application code, no migrations, no compose files, no `.env`, no secrets, no production
  path. Postgres/redis volumes untouched.
- **Security:** no secrets read or printed; no live Meta/WhatsApp calls; Enterprise untouched.
- **Validation:** `bash -n .github/scripts/deploy-remote.sh` OK; PR CI green (see PR). Runtime re-deploy is
  gated on review/merge (not performed in this PR).
- **Deploy required:** Yes — after merge, re-run Deploy Dev/Staging (`dev`, `version_1`, `run_migrations=true`).

### Phase 15F.1 — Send-from-Template composer (owner-only)
- **PR:** _pending_
- **Merge SHA:** _pending merge_
- **Type:** Feature (SuperAdmin / Bloomwire owner console; builds on Phase 15F)
- **Summary:** Added an owner-only **"Send from Template"** composer on the Email Templates tab. Discovery
  confirmed the prior "Send Test Email" button only linked to the Test Email tab (a generic sample send) — there
  was no way to fill template variables and send the rendered template. The composer exposes 9 fields (recipient,
  the 6 `{{variables}}`, plus button label/link), an **"Update preview"** round-trip that renders the final
  branded email with the entered values, and a **"Send Email"** action.
- **Review fix pass (this PR):**
  - **Delivered email now matches the preview.** A single shared partial
    (`app/views/bloomwire/email/_branded_email.html.erb`) is rendered by BOTH the composer preview AND the
    mailer, so they cannot drift. The mailer's new `template_email` sends **multipart HTML + plain-text** — the
    HTML carries the branding, CTA **button**, and footer; the text part is a fallback with the same key values.
    Placeholders are interpolated before sending; no raw `{{...}}` remains for supplied values.
  - **Per-send Email Logs.** New Bloomwire-owned table `bloomwire_email_delivery_logs` + model; every template
    send writes one row (**success / failed / blocked**) with recipient, template, status, timestamp, actor, and
    a **sanitized** error. The Email Logs tab now shows these rows (plus the latest test-email result).
  - New `Bloomwire::SendTemplateEmailService` owns the template send (preflight + enabled-gate + logging);
    `SendTestEmailService` was reverted to its original Test-Email-only role. Preflight + secret-filtering are
    now centralized on `Bloomwire::EmailSetting` (`block_reason` + `sanitize_secret`).
- **Why:** Owners need to send a real, variable-filled, on-brand email from a chosen template and audit each
  send — ahead of Phase 16 onboarding emails.
- **Honesty / safety:** Preflight + **enabled-gated** — blocks honestly (and records a `blocked` log) when the
  recipient is blank, SMTP is incomplete, or outbound email is disabled; **never fakes success**; the Send button
  is disabled until SMTP is ready. The SMTP password is never rendered, logged, or stored (errors sanitized).
- **Access:** owner-only via the existing `Bloomwire::RequiresPlatformOwner` gate on both controllers; non-owner
  platform admins and customer/business users are blocked (send + Email Logs).
- **Not changed:** no WhatsApp/Meta/provider credentials or code, no Enterprise code, no `BusinessOwner` role, no
  `users.type` for business roles, no chat/message tables, Devise/password-reset mailers untouched, no new
  dependencies, no production deploy.
- **Security:** no secrets exposed · no provider-credential mutation · **no** live Meta/WhatsApp calls (mailer
  stubbed on delivery paths; the suite makes no real SMTP connection) · Enterprise code untouched · the new log
  table never stores credentials and only stores sanitized errors.
- **Validation:** RuboCop clean on all changed Ruby; **71 examples, 0 failures** for the Bloomwire email suite,
  including: owner can send (→ success log) · non-owner blocked (send + logs) · missing recipient → blocked log ·
  incomplete SMTP → blocked log · disabled SMTP → blocked log · failed send → failed log with sanitized error ·
  HTML **and** text parts contain replaced values + CTA, no raw `{{...}}` · Email Logs renders recipient/template/
  status · password never in logs/response/HTML · final-preview round-trip uses the shared branded shell.
- **Residual:** SMTP password remains plaintext-at-rest (documented Phase 15F debt, encryption still parked);
  Office365 SMTP AUTH may still be blocked by tenant Security Defaults (a Microsoft-365 config matter, not code).
- **Migration:** `20260629000003_create_bloomwire_email_delivery_logs` (additive; new Bloomwire-owned table).
- **Runtime impact:** new owner-only UI action + new table · **Deploy required:** Yes — run the migration
  (after review/merge; not done here).

### Phase 15G — CI/CD Foundation (PR CI + manual Dev/Staging deploy)
- **PR:** _pending_
- **Merge SHA:** _pending merge_
- **Type:** CI/CD / process (infra-only; no application runtime code)
- **Summary:** Added repo-root GitHub Actions. `ci.yml` validates PRs targeting `version_1` — RuboCop,
  ESLint, Vitest, Vite asset build (`assets:precompile`), a curated Bloomwire RSpec suite (52 spec files)
  on ephemeral Postgres+Redis, a migration/schema-sync check, a docs-governance check, and a
  self-contained basic secret scan. `deploy-dev.yml` is a manual (`workflow_dispatch`) Dev/Staging deploy
  over SSH that builds the image with the exact `GIT_SHA`, optionally migrates, recreates only
  `rails`+`sidekiq` (`--no-deps`, preserving postgres/redis volumes), and runs post-deploy smoke
  (health 200, in-container SHA match, postgres/redis still Up). Remote logic lives in
  `.github/scripts/deploy-remote.sh`; full guide in [`deployment-runbook.md`](./deployment-runbook.md).
- **Why:** Safer, auditable, less-manual dev/staging deploys and consistent PR gating before Phase 16.
- **Runner:** GitHub-hosted only (Option A). No self-hosted runner this phase.
- **Not changed:** no application runtime code, no migrations, no Enterprise code, no provider/credentials,
  no production deploy path, no Docker/compose files, no `.env`. The server-local
  `docker-compose.bloomwire-production.yaml` overlay is untouched (gitignored).
- **Security:** CI reads **no** secrets and makes **no** live Meta/WhatsApp calls (specs WebMock-blocked);
  deploy credentials are per-environment GitHub Environment secrets, never printed; the SSH key is written
  `600` and removed after the run; Postgres/Redis volumes are never destroyed.
- **Validation:** YAML parse OK (`ci.yml` 8 jobs, `deploy-dev.yml` 1 job); all embedded shell + the remote
  script pass `bash -n`; the Bloomwire spec selector resolves to 52 files. Live CI/deploy runs happen on the
  PR / on first manual dispatch (after secrets are configured).
- **Residual:** `dev`/`staging` GitHub Environments + SSH secrets must be configured before the deploy
  workflow can run; `actionlint`/`shellcheck` were not available locally (validated via YAML parse + `bash -n`).
- **Runtime impact:** None (infra/docs only) · **Deploy required:** No (it enables deploys; it does not perform one).

### Phase 15F — Owner-only Email Settings (DB-backed SMTP + templates)
- **PR:** #78
- **Merge SHA:** _pending merge_
- **Type:** Feature (SuperAdmin / Bloomwire owner console)
- **Summary:** Added an owner-only `Bloomwire → Email Settings` page (Overview / Configuration /
  Email Templates / Test Email / Email Logs) inside the existing SuperAdmin shell. Two Bloomwire-owned
  tables: `bloomwire_email_settings` (DB-backed SMTP config; ENV `SMTP_*` only as bootstrap defaults) and
  `bloomwire_email_templates` (6 seeded system templates with `{{variable}}` preview + create / edit /
  duplicate / deactivate / reactivate). Preflight-validated Test Email (real send when complete, honest
  "blocked" otherwise — never fakes success).
- **Why:** Phase 16 onboarding needs configurable outbound email + reusable transactional templates owned
  by the Bloomwire Platform Owner.
- **Access:** owner-only (`Bloomwire::PlatformAdmin` active owners); platform admin/support + customer/
  business users blocked; `/super_admin` boundary unchanged.
- **Not changed:** no WhatsApp/Meta/provider credentials, no Enterprise code, no `BusinessOwner` role, no
  `users.type` for business roles, no chat/message tables, Devise/password-reset mailers untouched.
- **Validation:** model + service + mailer + request specs (52 examples, 0 failures); RuboCop clean;
  existing SuperAdmin specs regression-green (39/0). Browser QA on dev pending (post-approval).
- **Review fixes (post-#78 review):** (1) Overview tab copy made honest — it no longer implies password
  resets/transactional emails already use the DB-backed SMTP; it states Devise/password-reset is unchanged
  and transactional sending is parked. (2) System-template **keys are immutable** — `:key` is not permitted
  on update and a model validation blocks changing a system template's key (future routing depends on stable
  keys); keys are auto-generated on create. (3) CTA URL scheme validation (http/https or `{{placeholder}}`
  only) — closes the previously-flagged non-blocking CTA href concern.
- **Security:** SMTP password is **write-only** in the UI (masked, never rendered/logged/printed). No live
  Meta/WhatsApp calls (tests never send real mail). No provider-credential mutation. No Enterprise touched.
- **Residual / SECURITY DEBT:** `smtp_password` is stored **plaintext** in DB because Active Record
  encryption is not configured on this install. **Encryption-at-rest is a parked Phase 15F follow-up.**
  Also parked: transactional wiring of business-invitation/welcome/plan-change/receipt/ticket mailers to
  the DB-backed config; per-message delivery logging (Email Logs shows the last test result only).
- **Runtime impact:** New owner-only page + 2 new tables (migration). **Deploy required:** Yes (after approval).

### Phase 15E.1 — Documentation Governance Guardrail
- **PR:** #77 (docs-only; amends the Phase 15E PR)
- **Type:** Docs / process
- **Summary:** Added a mandatory **Bloomwire Documentation Governance** rule to `AGENTS.md` and
  `CLAUDE.md`, a **Documentation Governance** section (§10) + Definition of Done to the implementation
  ledger (`.md` + `.html`), and created this change log.
- **Why:** Every Bloomwire-owned change must stay transparent and documented; future agents must not
  make hidden/undocumented changes.
- **Not changed:** no runtime application code, no migrations, no Enterprise, no provider/credentials.
- **Validation:** docs-only diff; HTML self-contained + well-formed; ledger and changelog agree.
- **Residual:** none.
- **Runtime impact:** None · **Deploy required:** No

### Phase 15E — Implementation Ledger
- **PR:** #77
- **Type:** Docs
- **Summary:** Added the Bloomwire Implementation Ledger (`docs/bloomwire/implementation-ledger.md`
  + `.html`): ownership, stable baseline, phase-by-phase log (13B–15D), permission model, WhatsApp
  architecture, OSS/Enterprise stance, intentionally-not-changed list, parked/residual items,
  operational rules.
- **Why:** A clear internal reference before Phase 16 customer onboarding.
- **Baseline documented:** `4084a23eb4a83b1ee41e298811a91d52d6fb6044` (after Phase 15C).
- **Not changed:** no runtime application code, no migrations, no Enterprise, no provider/credentials.
- **Validation:** docs-only diff; HTML self-contained (no CDN/JS).
- **Residual:** none.
- **Runtime impact:** None · **Deploy required:** No

---

## Released

_(none yet — entries move here when the `version_1` line is tagged/released, with their merge SHAs.)_

---

<sub>Bloomwire Change Log · docs only, no runtime behavior · baseline `4084a23eb4a83b1ee41e298811a91d52d6fb6044`.</sub>
