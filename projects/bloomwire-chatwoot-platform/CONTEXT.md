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
- **Bloomwire adds SaaS metadata and control surfaces only** — business
  profiles, plans, subscriptions, feature flags, custom roles/permissions,
  audit logs, usage analytics, onboarding steps, industry presets.
- **Do not duplicate** Chatwoot conversation / message / contact history into
  Bloomwire tables. Reference Chatwoot data by its identifiers; do not copy it.

## Hard constraints

- **No Chatwoot Enterprise code** may be copied, imported, used, or depended on.
  Bloomwire builds only on Chatwoot **Community Edition**.
- **Bloomwire-owned tables must use the `bloomwire_` prefix** (applies later,
  when implementation begins).
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

## Ways of working

- **Work must happen in vertical slices.** One thin, end-to-end, testable piece
  of value at a time.
- **No application code in the documentation phase.** This phase is
  documentation + architecture context only.
- **Do not import Chatwoot source yet.** That is a later, separate decision.

## Branch workflow (see root memory / README)

- Work happens on `feature/*` branches created off `version_1`.
- Flow: `feature/*` → PR → `version_1` → PR → `develop` → PR → `main`.
- `version_1`, `develop`, and `main` are protected (PR + 1 approval required).
- Never push directly to a protected branch.
