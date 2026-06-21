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
