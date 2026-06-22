# CONTEXT — Bloomwire Chatwoot Platform

Project-specific contracts for the Bloomwire SaaS platform. These **extend**
(never override) the global engineering rules in the repo-root `AGENTS.md` and
`CLAUDE.md`. Read those first, then this file, before doing any work in this
project.

---

## What this project is

- **Bloomwire is an omnichannel customer service SaaS platform.**
- **Chatwoot Community Edition (CE) is the base engine.** Bloomwire is built
  *on top of* Chatwoot CE, not as a fork that diverges from it.
- Bloomwire adds a **SaaS / business control layer** on top of Chatwoot's
  conversation engine.

## Source of truth (non-negotiable)

- **Chatwoot remains the source of truth** for all messaging, conversation,
  contact, and channel data.
- Chatwoot owns: `accounts`, `users`, `account_users`, `inboxes`,
  `inbox_members`, `contacts`, `contact_inboxes`, `conversations`, `messages`,
  `teams`, `labels`, `campaigns`, `automation_rules`, `reporting_events`.
- **Bloomwire adds SaaS metadata and control surfaces only** — e.g. business
  profiles and onboarding steps (built), plus plans, subscriptions, feature
  flags, SaaS-specific roles/permissions, audit logs, usage analytics, and
  industry presets (future). Permissions today reuse Chatwoot `AccountUser`
  roles; Bloomwire roles tables are future-only.
- **Do not duplicate** Chatwoot conversation / message / contact history into
  Bloomwire tables. Reference Chatwoot data by its identifiers; do not copy it.

## Hard constraints

- **No Chatwoot Enterprise code** may be copied, imported, used, or depended on.
  Bloomwire builds only on Chatwoot **Community Edition**.
- **Bloomwire-owned tables must use the `bloomwire_` prefix.** Now in use:
  `bloomwire_business_profiles`, `bloomwire_onboarding_steps`.
- **Roles and permissions must be backend-enforced**, never frontend-only.
  Frontend hiding is **UX only, not security**.

## Enterprise boundary, calling & ChatwootHub telemetry (see ADR 0002)

Decision recorded in `docs/adr/0002-bloomwire-enterprise-boundary-and-telemetry.md`.
**ChatwootHub outbound isolation is now implemented** (see the telemetry bullet);
**Enterprise-overlay removal and any calling feature remain parked/future.**

- **No Enterprise calling code in production without a license.** The vendored
  Chatwoot build (`4.15.1`) ships Twilio Voice + WhatsApp Calling, but that code
  lives under `app/enterprise/` and is covered by the **Chatwoot Enterprise
  License** — production use requires a **valid Chatwoot Enterprise
  subscription**. Bloomwire holds no such subscription, so it must not run it.
- **Do not depend on the Enterprise calling surface:** `app/enterprise/` voice
  controllers, WhatsApp calling services, the Enterprise `Call` model, the
  `calls` table as Enterprise-owned runtime state, the `channel_voice` feature
  flag, or any Enterprise routes/services/controllers.
- **Future calling must be Bloomwire-owned (clean-room):** public Twilio Voice
  and Meta WhatsApp Cloud Calling APIs/SDKs, Bloomwire-owned
  services/controllers/`bloomwire_` tables, **no copied Enterprise logic**, and at
  most an **OSS-safe Chatwoot timeline note/activity** via the public messages
  API.
- **ChatwootHub telemetry (implemented):** Bloomwire production runs with
  **ChatwootHub outbound communication disabled by default** via the centralized
  `ChatwootHub.outbound_disabled?` guard (env `BLOOMWIRE_DISABLE_CHATWOOT_HUB`,
  secure-by-default in `production`; `BLOOMWIRE_ALLOW_CHATWOOT_HUB_PUSH` to permit
  the push relay). Under isolation, no `/ping`, installation-metadata sync,
  aggregate counts, pricing-plan sync, or telemetry events leave the instance.
  This is for **privacy, security, SaaS isolation, and customer-data
  protection** — it is **not** a licensing bypass and does **not** permit
  Enterprise feature use; **Enterprise features still require a valid
  license/subscription.**

## Security / safe DTO contract (extends global rule 8)

- **No raw phone numbers, contact IDs, vendor IDs, tokens, or internal IDs**
  should be exposed in browser APIs **unless explicitly approved**.
- Expose **safe DTOs** only. Sensitive Chatwoot internals stay server-side.

## Multi-tenancy model

- **One Chatwoot account = one Bloomwire business tenant.**
- **One Chatwoot inbox = one connected customer channel** (e.g. a WhatsApp
  number, a website widget, an email mailbox).
- Bloomwire SaaS metadata hangs off the Chatwoot account that represents the
  tenant; it never replaces it.

## Permission & channel-control boundary (see ADR 0003)

Decision recorded in `docs/adr/0003-bloomwire-permission-and-channel-control-boundary.md`.
**Decision only — parked/future (Phase 4.3–4.5 + Phase 5); nothing here is
implemented yet.** It separates platform responsibilities from tenant-admin
responsibilities and keeps raw Chatwoot setup surfaces platform-controlled.

- **Platform / Super Admin owns:** tenant/account creation, tenant activation,
  channel/inbox setup approval, channel enablement rules
  (WhatsApp/SMS/Email/Instagram/API), and enterprise/security/compliance config.
- **Client tenant admin owns:** their tenant's users/agents (if allowed),
  teams/departments, team memberships, and conversation workflow inside the tenant.
- **Client tenant admin does NOT own by default:** new tenant/account creation,
  arbitrary inbox/channel creation, API channel creation, WhatsApp/SMS/Facebook/
  Instagram/Telegram setup, WhatsApp Call / Enterprise-gated features, or
  platform-level settings.
- **Raw Chatwoot channel setup pages are not exposed to enterprise clients by
  default** (Settings → Inboxes → Add Inbox; API/WhatsApp/SMS/Facebook/Instagram/
  Telegram setup; WhatsApp Call Beta; New Account). They must be gated by
  Bloomwire permissions/capabilities.
- **Team management ≠ channel-creation permission.** A team is an internal
  department; an inbox/channel is an external customer communication connection.
  Creating a team must never automatically grant WhatsApp/SMS/API channel creation.
- **Future, opt-in self-service** is via a **planned** per-tenant capability model
  (`allow_new_account_creation`, `allow_team_management`, `allow_agent_management`,
  `allow_self_service_channel_setup`, `allow_whatsapp_setup`, `allow_sms_setup`,
  `allow_email_setup`, `allow_instagram_setup`, `allow_api_channel_setup`,
  `allow_whatsapp_calling`) — **no capabilities table or feature flags exist yet.**

> Dialog-style enterprise tenants should not receive raw Chatwoot account/channel
> setup access by default. Dialog admins may manage teams and users inside the
> Dialog tenant, but tenant creation and channel/inbox setup remain
> Bloomwire-controlled unless explicit tenant capabilities allow self-service setup.

## Global Meta/WhatsApp webhook routing (see ADR 0004)

Decision recorded in `docs/adr/0004-bloomwire-global-meta-whatsapp-webhook-router.md`.
**Decision only — parked/future (Phase 8); nothing here is implemented yet.**

- **Chatwoot native webhook behavior stays unchanged (default).** WhatsApp /
  Facebook / Instagram keep using Chatwoot's existing per-inbox webhook/channel
  setup; existing Chatwoot routes and behavior keep working.
- **A future Bloomwire-owned global webhook/router** (Phase 8) is **additive**, not
  a replacement: `Meta app → one Bloomwire global endpoint → Bloomwire router →
  correct Chatwoot account + inbox → Chatwoot conversations/messages`.
- **Behind a feature toggle, safe by default:**
  `BLOOMWIRE_GLOBAL_META_WEBHOOK_ENABLED=true|false` (**default `false`**). When
  off, native Chatwoot behavior is untouched. Tenant/channel-level config can
  **later** choose, per inbox, native vs global flow.
- **Routing by identifiers:** `phone_number_id`, `page_id`, `waba_id`, `provider`,
  `account_id`, `inbox_id`.
- **Source of truth unchanged:** Chatwoot still owns conversations / messages /
  contacts; the router only delivers events to the right account + inbox — **no
  duplication** into Bloomwire.

## External app configuration ownership (see ADR 0005)

Decision recorded in `docs/adr/0005-bloomwire-external-app-configuration-ownership.md`.
**Decision only — implementation parked/future (Phase 4.4); WhatsApp is the first
vertical; Dialog admins are NOT denied yet.**

- **Bloomwire owns all external app/channel configuration** (WhatsApp, SMS, Email,
  Instagram/Facebook, Shopify, later Telegram/Signal). Dialog (tenant) admins may
  **use** configured channels but may **not** connect/disconnect/create/
  reauthorize/register-webhook/edit provider credentials.
- **Setup is platform-owned** via a **dedicated Bloomwire Admin namespace/service**
  — the tenant `InboxesController` is **not** reused as the platform setup path.
- **Proposed ownership table** `bloomwire_channel_integrations` (design only, no
  migration) maps `profile → inbox → channel → account` plus **non-secret**
  routing metadata (`phone_number`, `phone_number_id`, `waba_id`, `routing_key`):
  unique per inbox, unique routing key where present.
- **Secrets are not duplicated** into the ownership/routing table; WhatsApp
  credentials stay in `Channel::Whatsapp#provider_config` (encryption is a
  separate future ADR). **Raw provider credentials are never exposed to Dialog
  users.**
- **The PR #19 seam** (`Bloomwire::WhatsappSetupGuard` /
  `Bloomwire::ChannelControlPolicy`) is the choke point; it stays
  **behavior-neutral** until the deny slice (4.4-b-WA.2C) lands **after** the
  Bloomwire Admin setup path (4.4-b-WA.2B).

## Implemented so far (current state)

Phases 0–4 Slice 1 are merged into `version_1`. What exists today:

- **Chatwoot CE remains the engine and source of truth.** Bloomwire is built on
  top of it and never forks its conversation data model.
- **Bloomwire does not duplicate Chatwoot conversations, messages, or contacts.**
  It references Chatwoot by identifiers and reads it live.
- **Business profiles** exist as Bloomwire tenant metadata
  (`BloomwireBusinessProfile`, table `bloomwire_business_profiles`, one per
  Chatwoot account); `Bloomwire::BusinessProfileBackfill` keeps every account
  represented.
- **A tenant setup foundation** exists (`Bloomwire::TenantSetupInitializer`).
- **Onboarding steps are tracked** (`BloomwireOnboardingStep`, table
  `bloomwire_onboarding_steps`; `Bloomwire::OnboardingStepTracker`).
- **Onboarding progress is visible in Super Admin**
  (`BloomwireBusinessProfile#onboarding_progress`, safe label only).
- **Chatwoot readiness is visible in Super Admin** (`Bloomwire::ChatwootReadiness`,
  `BloomwireBusinessProfile#chatwoot_readiness`, computed live, label only).
- **A manual tenant activation gate exists and is backend-enforced**
  (`Bloomwire::TenantActivation`,
  `SuperAdmin::BloomwireBusinessProfilesController#activate`).
- **`Bloomwire::AccessPolicy` is the first Phase 4 permission foundation**
  (backend, tenant-scoped, `can?(action)`).

### Roles & permissions: current vs future

- **The current permission foundation uses Chatwoot `AccountUser` roles**
  (`administrator` / `agent`), **not Bloomwire roles tables**.
- **No Chatwoot Enterprise / `custom_roles` dependency.**
- **Bloomwire roles/permission tables are future-only** — to be added when
  SaaS-specific custom staff permissions become necessary.
- **Tenant/channel-control lockdowns are decided but parked** (ADR 0003):
  platform-vs-tenant ownership of tenant/channel creation, the "raw Chatwoot
  setup not exposed by default" rule, and a future per-tenant capability model —
  **documentation only, not implemented.**

### Implementation map (names)

- Services: `Bloomwire::BusinessProfileBackfill`, `Bloomwire::TenantSetupInitializer`,
  `Bloomwire::OnboardingStepTracker`, `Bloomwire::ChatwootReadiness`,
  `Bloomwire::TenantActivation`, `Bloomwire::AccessPolicy`.
- Models: `BloomwireBusinessProfile`, `BloomwireOnboardingStep`.
- Super Admin: `SuperAdmin::BloomwireBusinessProfilesController`
  (`/super_admin/bloomwire/businesses`, list/show + `activate`).

See `docs/product/05-development-phases.md` (execution source of truth) and
`docs/system-overview/index.html` (living overview + changelog).

## Ways of working

- **Work must happen in vertical slices.** One thin, end-to-end, testable piece
  of value at a time.
- **Implementation is underway.** Chatwoot CE source lives in `app/` and Bloomwire
  SaaS features are built on top of it. Keep changes additive; do not fork or
  diverge from Chatwoot core behavior.
- **Risk-sensitive slices use the Independent TDD workflow** (failing acceptance +
  edge/security tests before implementation).

## Branch workflow (see root memory / README)

- Work happens on `feature/*` branches created off `version_1`.
- Flow: `feature/*` → PR → `version_1` → PR → `develop` → PR → `main`.
- `version_1`, `develop`, and `main` are protected (PR + 1 approval required).
- Never push directly to a protected branch.
