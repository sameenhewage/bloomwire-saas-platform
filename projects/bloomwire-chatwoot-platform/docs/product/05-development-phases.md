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

### Current slice — Bloomwire Tenant Setup Foundation

`feature/bloomwire-tenant-setup-foundation`

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

**Status:** delivered on `feature/bloomwire-tenant-setup-foundation` and verified
(acceptance RED, edge/security RED, GREEN 48 examples, DB + browser proof).
Awaiting review/integration into `version_1`.

### Later Phase 3 slices

- profile creation/attachment,
- onboarding step tracking,
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
Current slice: Bloomwire Tenant Setup Foundation (delivered on branch, in review)
Required workflow: Independent TDD Workflow
Do not start yet: roles engine, WhatsApp setup, billing, analytics, operational polish
```
