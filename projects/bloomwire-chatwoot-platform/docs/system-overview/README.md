# Bloomwire System Overview

An interactive, self-contained **living document** that explains the whole
Bloomwire + Chatwoot system end-to-end: what Bloomwire is, what Chatwoot does
inside it, tenants, accounts, roles, the white console vs the black workspace,
data ownership, what has been built, and the changelog.

It is **not** a marketing page — it is an architecture/product understanding
document for the founder/developer team.

## How to open it locally

The document is a single self-contained `index.html` (HTML + CSS + JavaScript,
**no external/CDN dependencies**), so you can open it directly:

- **Easiest:** double-click `index.html`, or drag it into any browser.
- **From a file URL:** open
  `projects/bloomwire-chatwoot-platform/docs/system-overview/index.html`.
- **Via a local static server (optional):**
  ```bash
  # from this folder
  python3 -m http.server 8000
  # then visit http://localhost:8000/index.html
  ```

No build step, no install, no network access is required.

## What's inside

- **Mental model** — `Bloomwire = SaaS layer`, `Chatwoot = conversation engine`,
  `Chatwoot account = tenant`, `business profile = SaaS metadata`.
- **Tenants** — Dialog / Mobitel / Hutch isolation example.
- **Why there are multiple admins** — Super Admin vs Owner/Admin vs Supervisor
  vs Agent vs Customer.
- **White Console vs Black Workspace** — `/super_admin/...` vs
  `/app/accounts/:accountId/...`.
- **Data ownership** — what Chatwoot owns vs what Bloomwire owns (no data
  duplication).
- **Current build state** — every completed slice (Phases 0–4 Slice 1):
  platform foundation, account overview, business profiles, tenant readiness
  backfill, tenant setup, onboarding tracking + progress UI, Chatwoot readiness,
  manual tenant activation, and the permission foundation (`Bloomwire::AccessPolicy`).
- **Permission matrix** — role × capability (backend-enforced; `AccessPolicy` is
  the first live slice, using core Chatwoot `AccountUser` roles, no Enterprise/custom_roles).
- **Request flow** — a message's journey from customer to tenant health.
- **Architecture decisions** — see `../adr/`; notably **ADR 0002** records the
  **Enterprise calling boundary** and the **ChatwootHub telemetry** decision: no
  Chatwoot Enterprise calling code in production without a valid Enterprise
  subscription, ChatwootHub outbound communication disabled/removed in production
  (privacy / security / SaaS isolation), and any future calling built
  Bloomwire-owned on public Twilio / Meta APIs. Decision only — implementation is
  parked/future. **ADR 0003** records the **permission & channel-control
  boundary**: the platform owns tenant/account creation, activation, and
  channel/inbox enablement; tenant admins manage their own teams/users only; raw
  Chatwoot setup pages (Add Inbox; API/WhatsApp/SMS/Facebook/Instagram/Telegram;
  WhatsApp Call Beta; New Account) are not exposed by default; a future per-tenant
  capability model enables opt-in self-service. Decision only — parked/future
  (Phase 4.3–4.5 + Phase 5). **ADR 0004** records the **global Meta/WhatsApp
  webhook router** (future Phase 8): a Bloomwire-owned, toggle-gated
  (`BLOOMWIRE_GLOBAL_META_WEBHOOK_ENABLED`, default off) global webhook that routes
  Meta events to the correct Chatwoot account + inbox by identifiers
  (`phone_number_id` / `page_id` / `waba_id` / `provider` / `account_id` /
  `inbox_id`) — **additive; Chatwoot native webhook behavior stays unchanged.**
  Decision only — parked/future.
- **Changelog** — timeline of every completed slice.

## Maintenance rule (important)

This is a **living document**. When the system changes, update this document in
the **same PR**. No major architecture, role, tenant, permission, or route
change is allowed without updating this overview — and every change must add a
**changelog** entry (date, slice name, what changed, files/areas touched, what
was intentionally not changed).
