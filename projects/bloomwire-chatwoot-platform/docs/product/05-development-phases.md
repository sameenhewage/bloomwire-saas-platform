# 05 — Development Phases

This document is the execution source of truth for Bloomwire development phases.
It is not a marketing roadmap. It defines the current development phase, completed
work, allowed next slice, and work that must not start yet.

## Mandatory rule

Before any new coding slice starts, this document must show:

- the current phase,
- the next slice,
- what is in scope,
- what is out of scope,
- the required verification process.

Do not start implementation from chat memory alone.

## Status legend

- ✅ Done — implemented and merged into `version_1`.
- 🔄 Current — active development phase.
- ⏳ Later — planned direction, not active yet.
- ❌ Out of scope — do not implement without explicit approval.

---

## Phase 0 — Platform Foundation ✅ Done

### Goal

Prove Chatwoot CE can run as the embedded conversation engine and document the
Bloomwire source-of-truth rules before adding SaaS features.

### Completed

- PR #1 — Platform foundation and runtime baseline.
- Chatwoot CE baseline documented.
- Project context added.
- Source-of-truth rules documented.

### Key decisions

- Chatwoot owns conversations, messages, contacts, channels, accounts, users,
  account membership, inboxes, teams, labels, campaigns, automation rules, and
  reporting events.
- Bloomwire owns SaaS control-plane metadata around Chatwoot.
- No Chatwoot Enterprise code.
- No duplicated Chatwoot conversation, message, or contact history.

---

## Phase 1 — First Bloomwire SaaS Layer ✅ Done

### Goal

Add the first visible Bloomwire SaaS layer while keeping Chatwoot as the
conversation engine.

### Completed

- PR #2 — Bloomwire Account Overview page.
- PR #3 — Bloomwire Business Profiles + Super Admin Businesses List.
- PR #4 — Interactive Bloomwire System Overview living document.
- PR #5 — Independent TDD workflow agents.

### What exists now

- `/app/accounts/:accountId/bloomwire/overview`
- `bloomwire_business_profiles`
- `/super_admin/bloomwire/businesses`
- System Overview living document
- Independent TDD workflow for risky coding slices

### Not included yet

- No business profile create/edit/delete UI.
- No billing automation.
- No custom roles/permissions engine.
- No WhatsApp setup flow.
- No AI bot builder.
- No Chatwoot data duplication.

---

## Phase 2 — Tenant Readiness / Data Consistency ✅ Done

### Goal

Make tenant metadata consistent so every Chatwoot account can be represented as a
Bloomwire business without missing rows or duplicates.

### Delivered slice — Bloomwire Business Profile Backfill

`feature/bloomwire-business-profile-backfill` (merged into `version_1` via PR #7)

- Idempotent `Bloomwire::BusinessProfileBackfill` service + `bloomwire:business_profiles:backfill`
  rake task.
- Creates exactly one `BloomwireBusinessProfile` per account missing one, with defaults
  `status = setup_pending` and `onboarding_status = not_started`.
- Verified: acceptance RED, edge/security RED, GREEN (29 examples, 0 failures), DB proof
  (missing profiles -> 0, no duplicates), and MCP/browser proof (Super Admin Businesses lists
  all tenants). Chatwoot conversation/message/contact counts unchanged.

### Acceptance truth

- User expects every Chatwoot business tenant to appear in Bloomwire Super Admin
  business views with safe default metadata.
- Current system supports business profiles, but accounts without a
  `bloomwire_business_profile` can be missing from Bloomwire business views.
- Done means existing accounts can be backfilled safely, repeat runs do not create
  duplicates, and default metadata is correct.

### In scope

- Backfill missing `bloomwire_business_profiles` for existing accounts.
- Ensure one profile per account.
- Preserve defaults:
  - `status = setup_pending`
  - `onboarding_status = not_started`
- Make the backfill idempotent.
- Confirm Super Admin Businesses can represent all expected tenants.

### Out of scope

- No onboarding wizard.
- No profile edit UI.
- No billing enforcement.
- No custom roles/permissions engine.
- No WhatsApp setup.
- No AI workflow changes.
- No Chatwoot conversation/message/contact copying.

### Required process

This is a coding slice. Use the independent TDD workflow:

```text
Acceptance Test Agent -> Edge & Security Test Agent -> Fullstack Builder Agent
-> QA Review Agent -> Code Review Agent -> Handoff Agent
```

Required RED tests before implementation:

- missing profile backfill,
- default values,
- idempotency,
- duplicate prevention,
- no copied Chatwoot conversation/contact/message data.

---

## Phase 3 — Business Onboarding / Tenant Setup ✅ Done

Phase 2 is complete. All Phase 3 slices below are merged into `version_1` — tenant
setup foundation (PR #8), onboarding step tracking (PR #9), onboarding progress
UI (PR #10), Chatwoot readiness mapping (PR #11), and manual tenant activation
(PR #12). Phase 4 is now the active phase.

### Completed slice — Bloomwire Tenant Setup Foundation

`feature/bloomwire-tenant-setup-foundation` (merged into `version_1` via PR #8)

Smallest backend foundation so a platform operator can initialize tenant setup
for one Chatwoot account that has (or should have) a `BloomwireBusinessProfile`.
This is **not** the full onboarding wizard.

**Acceptance truth**

- User expects operators to start preparing a business tenant for onboarding
  once the business profile exists.
- Current system has profiles + `onboarding_status` but no safe initializer that
  moves a tenant from `not_started` to `in_progress`.
- Done means a platform-safe service initializes setup for one account/profile,
  ensures the profile exists, moves `onboarding_status` `not_started -> in_progress`,
  stays idempotent, never downgrades `completed`, and never copies Chatwoot data.

**In scope**

- `Bloomwire::TenantSetupInitializer` service +
  `bloomwire:tenant_setup:initialize[ACCOUNT_ID]` rake task.
- Ensure exactly one profile per account (Phase 2 defaults when creating).
- `not_started -> in_progress`; `in_progress` and `completed` left unchanged.
- Returns a safe summary result only.

**Out of scope**

- Full onboarding wizard, WhatsApp/channel setup, billing, roles/permissions
  engine, AI/human workflow, profile edit UI, staff invite flow, industry preset
  engine, Chatwoot conversation/message/contact duplication.

**Status:** ✅ merged into `version_1` (PR #8). Verified — acceptance RED,
edge/security RED, GREEN, DB + browser proof.

### Completed slice — Bloomwire Onboarding Step Tracking

`feature/bloomwire-onboarding-step-tracking` (merged into `version_1` via PR #9)

Backend-only tracking of onboarding steps for a `BloomwireBusinessProfile`, so an
operator can see and advance where a tenant is in setup. This is **not** the
onboarding wizard UI.

**Acceptance truth**

- User expects each business profile to have a known, ordered set of onboarding
  steps whose completion can be tracked and advanced safely.
- Current system tracks only a coarse `onboarding_status`; there is no per-step
  record of what is done.
- Done means a backend service seeds the default ordered steps for a profile
  (idempotently), can advance to the next pending step, is tenant-scoped, and
  returns a safe summary only.

**In scope**

- `bloomwire_onboarding_steps` table + `BloomwireOnboardingStep` model
  (`has_many` from `BloomwireBusinessProfile`), with `step_key`, `status`,
  `position`, unique per profile.
- `Bloomwire::OnboardingStepTracker` service (ensure default steps, advance,
  safe summary) + `bloomwire:onboarding:*` rake tasks.
- Idempotent seeding/advancement; safe failures for missing account/profile.

**Out of scope**

- Onboarding wizard UI, WhatsApp/channel setup, billing, roles/permissions,
  AI/human workflow, staff invite flow, industry preset engine, and any
  Chatwoot conversation/message/contact duplication.

**Status:** ✅ merged into `version_1` (PR #9). Verified — acceptance RED,
edge/security RED, GREEN 70 examples, RuboCop clean, DB + browser proof.

### Completed slice — Bloomwire Onboarding Step Status UI

`feature/bloomwire-onboarding-step-status-ui` (merged into `version_1` via PR #10)

Smallest Super Admin UI surface that makes the existing onboarding step tracking
visible to platform operators. This is **not** the onboarding wizard.

**Acceptance truth**

- User expects operators to see a tenant's onboarding step progress from the
  Super Admin Bloomwire Businesses area.
- Current system tracks steps in the backend (PR #9) but never surfaces them in
  the UI.
- Done means the Bloomwire Businesses index/show pages display a safe onboarding
  progress summary (total, completed, current step, all-completed), missing steps
  are handled safely, and no Chatwoot data is exposed.

**In scope**

- Read-only `BloomwireBusinessProfile#onboarding_step_summary` (value object) and
  `#onboarding_progress` (safe label) computed from existing steps.
- `onboarding_progress` column on the Administrate index + show pages; controller
  eager-loads `:onboarding_steps` to avoid N+1.
- Safe summary only (counts + humanized current step); no raw records/ids.

**Out of scope**

- WhatsApp/channel setup, inbox/channel engine, full onboarding wizard, billing,
  roles/permissions, AI/human workflow, staff invite flow, industry preset
  engine, Chatwoot conversation/message/contact copy, dev DB cleanup.

**Status:** ✅ merged into `version_1` (PR #10). Verified — acceptance RED,
edge/security RED, GREEN 83 examples, RuboCop clean, DB + browser proof.

### Completed slice — Bloomwire Chatwoot Readiness Mapping

`feature/bloomwire-chatwoot-readiness-mapping` (merged into `version_1` via PR #11)

Read-only mapping that shows operators whether a tenant's underlying Chatwoot
setup is ready. Chatwoot still owns accounts/inboxes/channels/conversations/
contacts/messages — this slice only reads existing state.

**Acceptance truth**

- User expects operators to see, per Bloomwire business, whether the underlying
  Chatwoot tenant setup is ready.
- Current system surfaces onboarding progress but nothing about Chatwoot setup
  readiness.
- Done means the Bloomwire Businesses index/show pages show a safe readiness
  label computed read-only from existing Chatwoot data, with no creation/config
  of inboxes/channels and no exposure of conversation/message/contact data.

**In scope**

- Read-only `Bloomwire::ChatwootReadiness` service returning a safe status label
  (Ready / Needs inbox/channel / No Chatwoot account / No Bloomwire profile).
- `BloomwireBusinessProfile#chatwoot_readiness` delegate; `chatwoot_readiness`
  column on the Administrate index + show pages; controller eager-loads
  `account: :inboxes` to avoid N+1.
- Tenant isolation + safe DTO (label only, no ids/records).

**Out of scope**

- WhatsApp/channel/inbox/webhook creation or configuration, billing,
  roles/permissions, AI/human workflow, staff invite flow, full onboarding
  wizard, Chatwoot conversation/message/contact copy, dev DB cleanup.

**Status:** ✅ merged into `version_1` (PR #11). Verified — acceptance RED,
edge/security RED, GREEN 99 examples, RuboCop clean, DB + browser proof.

### Completed slice — Bloomwire Manual Tenant Activation

`feature/bloomwire-manual-tenant-activation` (merged into `version_1` via PR #12)

The final Phase 3 readiness-lifecycle step: a backend-enforced Super Admin action
that lets operators activate a tenant only once it is actually ready. Activation
is a control-plane status change only — it never builds Chatwoot functionality.

**Acceptance truth**

- User expects a safe way to manually activate a tenant from the Super Admin
  Bloomwire business detail page once setup is complete.
- Current system shows readiness/onboarding but has no activation action; nothing
  enforces "only activate when ready".
- Done means activation is backend-enforced (not just UI): it succeeds only when
  the profile exists, Chatwoot is Ready, and onboarding steps exist and are all
  completed; on success `status: setup_pending -> active` and
  `onboarding_status -> completed`; an already-active tenant is idempotent; a
  blocked activation mutates nothing and shows a safe reason; no Chatwoot
  inbox/channel/webhook is created and no conversation/message/contact data is
  copied or exposed.

**In scope**

- Backend `Bloomwire::TenantActivation` service (safe reason codes:
  profile_not_found / chatwoot_not_ready / onboarding_steps_missing /
  onboarding_incomplete).
- `POST .../bloomwire/businesses/:id/activate` member route + controller action
  with safe success/failure flash.
- Show-page activation panel/button (Administrate show override).
- Tenant isolation + safe DTO (no raw ids/data in flashes).

**Out of scope**

- WhatsApp setup, channel/inbox/webhook creation, billing, roles/permissions,
  AI/human workflow, staff invite flow, full onboarding wizard, Chatwoot
  conversation/message/contact copy, dev DB cleanup.

**Status:** ✅ merged into `version_1` (PR #12). Verified — acceptance RED,
edge/security RED, GREEN 121 examples, RuboCop clean, DB + browser proof.

### Later Phase 3 slices

- profile creation/attachment,
- staff invite preparation,
- industry preset selection.

---

## Phase 4 — Roles, Permissions & Security Foundation � Current

Backend enforcement is mandatory; frontend hiding is UX only.

### Completed slice — Bloomwire Permission Foundation / Access Policy

`feature/bloomwire-permission-foundation` (merged into `version_1` via PR #13)

The smallest backend foundation for Bloomwire roles & permissions: define and
enforce who may use Bloomwire tenant features, without building any
role-management UI yet. Membership is read from the existing core Chatwoot
AccountUser role — no Enterprise/custom_roles.

**Acceptance truth**

- User expects the system to know who can access Bloomwire tenant features and
  what they may do, before tenant dashboard features are built.
- Current system has tenant setup/readiness/activation but no access policy.
- Done means a backend, tenant-scoped permission policy exists: Super Admin is
  platform-level; an account administrator may view only their own *active*
  tenant's metadata; agents, non-members, and cross-tenant access are denied;
  tenant users cannot activate tenants; missing user/account/profile denies
  safely; no frontend-only enforcement; no Enterprise/custom_roles; no Chatwoot
  conversation/message/contact data copied or exposed.

**In scope**

- Backend `Bloomwire::AccessPolicy` (`user:` / `profile:` -> `can?(action)`),
  actions `view_business_profile` / `view_onboarding_status` /
  `view_chatwoot_readiness` / `activate_tenant`.
- Wire the policy into the Super Admin activate endpoint (backend-enforced).
- Acceptance + edge/security specs (allowed/denied, tenant isolation,
  cross-tenant denial, safe failures, no Enterprise/custom_roles, no Chatwoot
  data copy/expose).

**Out of scope**

- No roles table, no role-management UI, no staff invite flow, no billing, no
  WhatsApp/channel setup, no AI workflow, no Enterprise/custom_roles, no Chatwoot
  conversation/message/contact copy, no dev DB cleanup.

**Status:** ✅ merged into `version_1` (PR #13). Verified — acceptance RED,
edge/security RED, GREEN 142 examples, RuboCop clean, DB + browser proof.

The current permission foundation reuses the **core Chatwoot `AccountUser` role**
(`administrator` / `agent`) — there are **no Bloomwire roles tables** and **no
Chatwoot Enterprise / `custom_roles` dependency**. Bloomwire-specific
roles/permission tables are **future-only**, to be added when SaaS-specific custom
staff permissions become necessary (see *Next / later Phase 4 slices*).

### Already completed in Phase 4 (security foundation)

- **AccessPolicy foundation** (PR #13) — backend, tenant-scoped permission policy
  using the core Chatwoot `AccountUser` role.
- **ChatwootHub outbound isolation** — production runs with outbound telemetry off
  by default (see ADR 0002 and the cross-cutting section below).
- **Enterprise boundary / telemetry decision** (ADR 0002).

### Parked next — tenant & channel control lockdowns (decision: ADR 0003)

Decision recorded in `../adr/0003-bloomwire-permission-and-channel-control-boundary.md`.
**Documentation/decision only — not implemented.** These slices lock down *who*
may create tenants and channels, **before** any tenant-facing setup surface is
built. Default posture is platform-controlled; raw Chatwoot setup pages are not
exposed to enterprise clients by default.

- **Phase 4.3 — New Account / Tenant Creation Lockdown** ⏳ Parked
  - Tenant/account creation is **platform / Super-Admin-owned**; tenant admins do
    **not** get Chatwoot's "New Account" affordance by default.
- **Phase 4.4 — Channel / Inbox Creation Lockdown** ⏳ Parked
  - Raw Chatwoot inbox/channel setup (Add Inbox; API / WhatsApp / SMS / Facebook /
    Instagram / Telegram; WhatsApp Call Beta) is **not** exposed to enterprise
    clients by default — it is Bloomwire-controlled.
  - **Team management ≠ channel-creation permission.** A team is an internal
    department; an inbox/channel is an external customer communication
    connection. Creating a team must never automatically grant permission to
    create WhatsApp/SMS/API channels.
- **Phase 4.5 — Tenant Feature Capabilities** ⏳ Parked
  - A **future** per-tenant capability model enabling controlled, opt-in
    self-service (e.g. `allow_new_account_creation`, `allow_team_management`,
    `allow_agent_management`, `allow_self_service_channel_setup`,
    `allow_whatsapp_setup`, `allow_sms_setup`, `allow_email_setup`,
    `allow_instagram_setup`, `allow_api_channel_setup`, `allow_whatsapp_calling`).
    **No capabilities table or feature flags exist yet.**

> Dialog-style enterprise tenants should not receive raw Chatwoot account/channel
> setup access by default. Dialog admins may manage teams and users inside the
> Dialog tenant, but tenant creation and channel/inbox setup remain
> Bloomwire-controlled unless explicit tenant capabilities allow self-service
> setup.

### Next / later Phase 4 slices (not started)

- surface `Bloomwire::AccessPolicy` checks in tenant-facing UI (UX hiding only;
  the backend already enforces access),
- platform roles,
- tenant roles,
- permission-matrix surfaces,
- per-action granular permissions,
- Bloomwire roles/permission tables (only when SaaS-specific custom staff
  permissions are required).

---

## Phase 5 — Controlled Channel Readiness / WhatsApp Setup Mapping ⏳ Later

Do not implement yet. **Builds on the Phase 4 lockdowns (decision: ADR 0003):**

> Phase 4 locks down who can create tenants/channels.
> Phase 5 builds the controlled customer-facing Channel Readiness / WhatsApp Setup flow.

Candidate scope later:

- channel setup status,
- WhatsApp checklist/setup flow,
- Chatwoot inbox/channel mapping,
- readiness checks.

One Chatwoot inbox = one connected channel.

**Relationship to the future webhook router (ADR 0004):** Phase 5 prepares the
controlled channel readiness and WhatsApp setup mapping needed for the future
**Phase 8 — Bloomwire Global Meta/WhatsApp Webhook Router**. Phase 5 must **not**
implement the router itself.

**Calling note (see ADR 0002):** if voice / WhatsApp calling ever enters scope, it
must be **Bloomwire-owned** (public Twilio / Meta APIs, `bloomwire_` tables) and
must **not** use Chatwoot's Enterprise calling code, the `channel_voice` flag, or
the Enterprise `Call` model. Chatwoot Enterprise calling in production would
require a valid Chatwoot Enterprise subscription.

---

## Phase 6 — Analytics / Usage / Billing Metadata ⏳ Later

Do not implement yet.

Candidate scope later:

- usage summaries sourced from Chatwoot,
- plan metadata,
- subscription status metadata,
- audit-log preparation.

Summaries are allowed. Raw Chatwoot conversation/message/contact data must not be
copied into Bloomwire tables.

---

## Phase 7 — Operational Workflow Polish ⏳ Later

Do not implement yet.

Candidate scope later:

- assistant status surfaces,
- operator controls,
- escalation monitoring UX,
- workflow visibility.

---

## Phase 8 — Bloomwire Global Meta/WhatsApp Webhook Router ⏳ Later

Do not implement yet. **Decision recorded in ADR 0004**
(`../adr/0004-bloomwire-global-meta-whatsapp-webhook-router.md`). A **future,
Bloomwire-owned** feature behind a config/feature toggle. It is **additive** and
must **not** replace or change Chatwoot's native webhook/channel behavior.

**Why:** SaaS customers should not be forced to wire up and maintain
Chatwoot-generated per-inbox webhook URLs forever. For scalable SaaS, Bloomwire
should eventually expose **one global webhook endpoint** and route events
internally.

**Target flow:**

```text
Meta / Facebook / WhatsApp App
  → Bloomwire Global Webhook (one endpoint)
  → Bloomwire Router
  → correct Chatwoot Account + Inbox
  → Chatwoot conversations / messages
```

**Two flows (must coexist):**

- **Chatwoot native webhook flow (today, default):** Meta app → Chatwoot per-inbox
  webhook URL → Chatwoot inbox → conversations/messages. **Unchanged.**
- **Bloomwire global webhook/router flow (future, toggle-gated):** Meta app → one
  Bloomwire global endpoint → Bloomwire router resolves the destination → hands
  off to Chatwoot → conversations/messages.

**Config / feature toggle:**

- `BLOOMWIRE_GLOBAL_META_WEBHOOK_ENABLED=true|false` — **default `false` (safe)**;
  native Chatwoot behavior is untouched when off.
- Tenant/channel-level config can **later** decide, **per inbox**, whether it uses
  the native Chatwoot webhook flow or the Bloomwire global webhook flow.

**Routing identifiers:** `phone_number_id`, `page_id`, `waba_id`, `provider`,
`account_id`, `inbox_id`.

**Constraints:** Chatwoot stays the conversation engine / source of truth; the
router only delivers events to the correct Chatwoot account + inbox. No
conversation/message/contact duplication in Bloomwire. Bloomwire-owned
(clean-room), `bloomwire_` config/tables if/when built.

**Risks / open questions:**

- How to proxy/route events into Chatwoot **safely** (signature validation,
  payload integrity, idempotency, retries, ordering).
- Whether to **proxy to native Chatwoot webhook endpoints first** (reuse existing
  handlers) or **call internal Chatwoot services later** (tighter integration).
- **Runtime test needed** for multi-inbox / multi-number Meta app behavior (one
  app, many numbers/pages → correct routing).
- **Meta verification should stay stable** by using the Bloomwire global webhook
  from the beginning, so the verified callback URL does not have to change later.

---

## Cross-cutting parked decision — Enterprise boundary & ChatwootHub telemetry (ADR 0002)

Recorded in `../adr/0002-bloomwire-enterprise-boundary-and-telemetry.md`. The
**ChatwootHub outbound isolation** part of this decision is now **implemented**
(slice below); **Enterprise-overlay removal and any calling feature remain
parked/future.**

- **Chatwoot CE / OSS stays the source of truth** for accounts, inboxes, contacts,
  conversations, messages, labels, teams, and the normal support workflow.
- **No Chatwoot Enterprise calling code in production without a valid Chatwoot
  Enterprise subscription** (the calling code under `app/enterprise/` is
  Enterprise-licensed).
- **No dependency** on `app/enterprise/` voice controllers, WhatsApp calling
  services, the Enterprise `Call` model, the `calls` table as Enterprise runtime
  state, the `channel_voice` flag, or any Enterprise routes/services/controllers.
- **Any future calling is Bloomwire-owned (clean-room)** via public Twilio /
  Meta APIs, with at most an OSS-safe Chatwoot timeline note/activity.
- **ChatwootHub outbound telemetry (implemented)** is disabled by default in
  Bloomwire production via the centralized `ChatwootHub.outbound_disabled?` guard
  (`BLOOMWIRE_DISABLE_CHATWOOT_HUB`, secure-by-default in production;
  `BLOOMWIRE_ALLOW_CHATWOOT_HUB_PUSH` to allow the push relay) — for **privacy,
  security, SaaS isolation, and customer-data protection**. This is **not** a
  licensing bypass and does **not** permit Enterprise feature use; **Enterprise
  features still require a valid license.**

### Delivered slice — ChatwootHub outbound isolation ✅

`feature/bloomwire-chatwoothub-outbound-isolation`

- **A. ✅** ChatwootHub call sites audited (`sync_with_hub`, `register_instance`,
  `send_push`, `emit_event`, daily `Internal::CheckNewVersionsJob`).
- **B. ✅** `BLOOMWIRE_DISABLE_CHATWOOT_HUB` (secure-by-default in production) +
  `BLOOMWIRE_ALLOW_CHATWOOT_HUB_PUSH`; one centralized
  `ChatwootHub.outbound_disabled?` predicate gates every outbound method.
- **C. ✅** the daily job returns early under isolation (no ping / plan sync).
- **D. ✅ (simulated)** runner + `RestClient.post` spy: zero posts to
  `hub.2.chatwoot.com` under isolation; real-prod network check is an ops item.
- **E. ✅** OSS account/inbox/contact/conversation/message verified (specs +
  Super Admin Accounts/Businesses pages in-browser).
- Verified: acceptance RED → GREEN, edge/security RED → GREEN (25 examples, 0
  failures), RuboCop clean, runtime runner + browser proof. Enterprise overlay
  and `channel_voice` untouched.

### Still parked (not started)

- **F.** Remove/disable the Enterprise overlay from the production build while not
  licensed and not using Enterprise features.
- **G.** Design a Bloomwire-owned calling architecture separately if calling
  becomes required.

---

## Current checkpoint

```text
Current phase: Phase 4 — Roles, Permissions & Security Foundation
Current position: Phase 4 Slice 1 (Permission Foundation / AccessPolicy) merged; Phase 4.3–4.5 tenant/channel-control lockdowns decided but parked (ADR 0003); next Phase 4 coding slice not started
Last merged: Bloomwire Permission Foundation / Access Policy (PR #13 -> version_1)
Required workflow: Independent TDD Workflow
Do not start yet: New Account / tenant-creation lockdown, channel/inbox-creation lockdown, tenant feature capabilities (parked — see ADR 0003), WhatsApp setup, billing, analytics, operational polish, Bloomwire global Meta/WhatsApp webhook router (parked — see ADR 0004), Bloomwire roles tables / full roles-permissions UI, Enterprise calling / channel_voice, Enterprise-overlay removal (parked — see ADR 0002; ChatwootHub outbound isolation now implemented)
```
