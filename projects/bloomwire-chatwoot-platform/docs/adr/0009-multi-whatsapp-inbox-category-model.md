# ADR-0009 — Multiple WhatsApp Inbox per Account (Category = Team + Inbox)

- Status: **Proposed** (Phase 17E.0 discovery — docs-only). The underlying multi-inbox capability is **already SUPPORTED**
  in `version_1`; this ADR proposes formally adopting the **Category = Team + Inbox** model on native Chatwoot
  primitives and **defers the contacts-isolation policy to Phase 17E.2**. To be marked **Accepted** after the 17E.1
  contract tests land and the 17E.2 contacts-isolation decision is made.
- Extends: ADR-0001/0002/0003 (never overrides); ADR-0004 (`Bloomwire::WhatsappSetup` mapping foundation — unchanged);
  ADR-0005 (global WhatsApp webhook router — unchanged); ADR-0006 (provider secret at rest — unchanged);
  ADR-0008 (WhatsApp onboarding responsibility pivot — unchanged).
- Supersedes: nothing.

## Context

Bloomwire's business model needs one business (a single Chatwoot **Account** / tenant) to run several
**categories/departments**, each with its **own WhatsApp number** and its **own staff**, e.g. 5 categories ×
1 WhatsApp number × 10 agents (~50 employees). Admin/main agents manage and assign across all categories;
category agents should ideally see only their own category's conversations.

A full read of `version_1` (Phase 17E.0 discovery — see
[`docs/bloomwire/whatsapp-multi-inbox-discovery.md`](../../../../docs/bloomwire/whatsapp-multi-inbox-discovery.md))
established that this is **already supported** and that the Bloomwire feature toggle / channel-control work did
**not** block it:

- The managed embedded-signup services create a **new `Channel::Whatsapp` + `Inbox` + `Bloomwire::WhatsappSetup`
  on every call** and reject only a **duplicate `phone_number` / `phone_number_id`** (both globally unique —
  the correct routing key), never "account already has WhatsApp"
  (`app/app/services/bloomwire/whatsapp_embedded_signup_service.rb#persist`; Coexistence inherits it).
- There is **no per-account WhatsApp uniqueness** (`channel_whatsapp.phone_number` unique is global;
  `bloomwire_whatsapp_setups.account_id` index is **non-unique**; `phone_number_id` unique is global-partial —
  `app/db/schema.rb`).
- The WhatsApp "Add Inbox" card is gated by **role + managed mode** only (`canSelfServeManagedWhatsapp` —
  `app/lib/bloomwire/capabilities.rb`), **not** by inbox count, so it never disappears after the first inbox.
- The global router resolves inbound by `phone_number_id → exactly one setup → that setup's own inbox`,
  fail-closed (`app/app/services/bloomwire/webhooks/whatsapp_router.rb`).
- Native **Team / InboxMember / TeamMember / Conversation(`assignee_id`,`team_id`)** primitives + per-inbox
  round-robin and team-filtered assignment already express "Category = Team + Inbox, 10 agents each".
- Agent **conversation/inbox visibility is scoped in the backend** (policies + finder + `PermissionFilterService`),
  but **contact list/search is account-wide** (stock Chatwoot) — a cross-category contact-record leak.

The risk of *not* writing this down is that a future change (or a "fix") accidentally introduces a per-account
WhatsApp cap, relaxes the global-unique number constraint, weakens the router, or builds a parallel
WhatsWay-style store — any of which would break the model. This ADR locks the intended model + guardrails.

## Decision

1. **Multiple WhatsApp inboxes per account is a first-class Bloomwire capability.** Keep the create path that
   makes a new channel + inbox + setup per number; do **not** add any per-account WhatsApp-inbox cap.
2. **`phone_number` and `phone_number_id` stay globally unique.** Duplicate numbers/ids remain blocked
   (`:phone_number_taken` / `:phone_number_id_conflict`). This is what guarantees one line → one inbox and
   unambiguous routing; it must not be relaxed to per-account.
3. **Category = Team + Inbox** on **native** primitives (mapping table below). An employee is a `User`/agent;
   category staff are the same users added as **both** `TeamMember`s and `InboxMember`s; a customer thread is a
   `Conversation`; assignment uses `assignee_id` (person) and/or `team_id` (category). No new "Category" entity.
4. **Routing stays global-router-only** (ADR-0005): resolve by `phone_number_id`, hand off only when
   handoff-safe, fail closed. No per-channel callback override; native `/whatsapp/authorization` untouched.
5. **Conversation isolation relies on native inbox membership + policies** (already backend-enforced). Category
   agents are **not** administrators and are added only to their own inbox/team.
6. **Contacts-isolation is an explicit, deferred sub-decision (Phase 17E.2):** either (a) accept stock
   account-wide contact visibility, or (b) add an inbox-scoped contacts finder/policy. This ADR does not decide
   it; it records it as an open risk to resolve with the owner.
7. **Hardening is test-first and phased:** 17E.1 backend contract tests (multi-inbox), 17E.2 UI/permission +
   contacts decision, 17E.3 owner-operated runtime E2E (mocked Meta) **before** customer go-live.

## Consequences

- **No app-code change is required** to support multiple WhatsApp inboxes per account today; the work is
  (a) locking the contract with tests, (b) a small UX/pairing polish, (c) the contacts-isolation decision, and
  (d) runtime verification.
- **Kept / relied upon:** the managed signup services + `WhatsappSetupCreator`; the global router + handoff-safe
  resolution; encrypted `provider_config` (ADR-0006); native teams/inbox-members/assignment; native
  inbox/conversation policies + `Conversations::PermissionFilterService`.
- **Guaranteed by 17E.1 tests (new):** two numbers per account → two isolated inboxes; duplicate number → 422;
  wrong `phone_number_id` → fail closed; category agent cannot read another category's conversations.
- **Open until 17E.2:** whether contact records are isolated per inbox. Until then, treat account-wide contact
  visibility as known/accepted for internal use only.
- **Go-live gate:** no customer enablement until 17E.3 runtime E2E passes (owner-operated, no real Meta in tests).

### Mapping table — Bloomwire business concept → Chatwoot primitive

| Bloomwire business concept | Chatwoot primitive |
|---|---|
| Business / tenant | `Account` |
| Category / department | `Team` + `Inbox` (paired, one each) |
| Category WhatsApp number | `Channel::Whatsapp` + `Inbox` + `Bloomwire::WhatsappSetup` (`phone_number_id`) |
| Employee | `User` / `AccountUser` (role `agent`) |
| Admin / main agent | `AccountUser` (role `administrator`) |
| Category staff (10) | `TeamMember`s + `InboxMember`s (same users on both) |
| Customer message thread | `Conversation` |
| Assign to a person | `conversation.assignee_id` |
| Assign to a category | `conversation.team_id` |
| Access / visibility | Chatwoot policies + inbox membership (backend-scoped) |

## Non-goals

- **Do not rebuild WhatsWay** inside Chatwoot — no parallel category/number/agent machinery.
- **Do not duplicate the chat/message source of truth** — Chatwoot conversations/messages remain authoritative.
- **Do not bypass Chatwoot inbox/conversation primitives** — no custom routing tables beyond the existing
  non-secret `Bloomwire::WhatsappSetup` mapping.
- **Do not weaken global webhook routing** (ADR-0005) or add a native `/whatsapp/authorization` carve-out /
  per-channel callback override.
- **Do not expose secrets** — tokens stay in encrypted `provider_config`; safe DTOs only.
- **Do not add a per-account WhatsApp-inbox cap** or relax the global-unique `phone_number` / `phone_number_id`.

## Risks

- **Contacts visibility (medium):** stock Chatwoot contact list/search is account-wide, so a category agent can
  enumerate contact records (name/email/phone) belonging to another category (conversations stay hidden).
  Mitigation: decide accept-vs-scope in 17E.2; if scoping, add an inbox-scoped contacts finder + policy scope.
- **Missing multi-inbox tests (medium):** support is currently implicit/untested for the same-account
  multi-number case. Mitigation: 17E.1 contract tests before any UI/enablement claims.
- **Runtime not yet proven (medium):** no end-to-end run with 2+ numbers routing to 2 inboxes with
  category-only visibility. Mitigation: 17E.3 owner-operated runtime E2E (mocked Meta) before customer go-live.
- **Operational drift (low):** an admin could forget to pair a new inbox with a team / copy members, leaving
  agents unassigned. Mitigation: optional 17E.2 "create category" convenience step.

## Invariants preserved

No `users.type` for business roles · no `BusinessOwner` role · no duplicate chat/message source of truth · no
Enterprise dependency · WhatsApp-first · safe DTOs only · never expose secrets · global router owns inbound ·
Feature-OFF (Bloomwire mode) == stock Chatwoot.
