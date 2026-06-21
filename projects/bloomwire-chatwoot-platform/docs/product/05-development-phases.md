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

### Delivered slice

`feature/bloomwire-business-profile-backfill`

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

## Phase 3 — Business Onboarding / Tenant Setup 🔄 Current

Phase 2 is complete. This is now the active phase.

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

### Current slice — Bloomwire Manual Tenant Activation

`feature/bloomwire-manual-tenant-activation` (off `version_1`)

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

**Status:** delivered on `feature/bloomwire-manual-tenant-activation` and verified
(acceptance RED, edge/security RED, GREEN 121 examples, RuboCop clean, DB + browser
proof). Awaiting review/integration into `version_1`.

### Later Phase 3 slices

- profile creation/attachment,
- staff invite preparation,
- industry preset selection.

---

## Phase 4 — Roles & Permissions Engine ⏳ Later

Do not implement yet.

Candidate scope later:

- platform roles,
- tenant roles,
- permission matrix,
- backend-enforced authorization.

Frontend hiding is UX only. Backend enforcement is mandatory.

---

## Phase 5 — Channels / WhatsApp Setup ⏳ Later

Do not implement yet.

Candidate scope later:

- channel setup status,
- WhatsApp checklist/setup flow,
- Chatwoot inbox/channel mapping,
- readiness checks.

One Chatwoot inbox = one connected channel.

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

## Current checkpoint

```text
Current phase: Phase 3 — Business Onboarding / Tenant Setup
Current slice: Bloomwire Manual Tenant Activation (delivered on branch, in review)
Last merged: Bloomwire Chatwoot Readiness Mapping (PR #11 -> version_1)
Required workflow: Independent TDD Workflow
Do not start yet: roles engine, WhatsApp setup, billing, analytics, operational polish
```
