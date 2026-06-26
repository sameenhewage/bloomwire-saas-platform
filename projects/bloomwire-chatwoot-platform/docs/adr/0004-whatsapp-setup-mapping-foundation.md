# ADR-0004 — Bloomwire WhatsApp Setup Mapping Foundation

- Status: Accepted (implemented)
- Extends: ADR-0001 / ADR-0002 / ADR-0003 (never overrides)
- Scope: the "Controlled Channel Readiness / WhatsApp Setup Mapping" slice. Foundation only — no global
  webhook router, no managed onboarding wizard, no routing registry, no real Meta E2E.

## Context

Business owners/staff must **not** configure technical Meta/WhatsApp settings; Bloomwire Ops/SuperAdmin owns
WhatsApp technical setup. Stock Chatwoot has **no** notion of per-account WhatsApp "setup readiness" — a
channel either exists or it does not. We need a place where Ops can view/track setup readiness per
account/inbox, and a foundation the later Global Meta WhatsApp Webhook Router can build on.

## Decision

### Source of truth — no duplicate secret store
Secrets (`api_key`, `webhook_verify_token`) remain **solely** in `Channel::Whatsapp#provider_config` (the
runtime source, protected by Phase 2A/2B/2C). The mapping **references** existing records and stores only
non-secret data. It never stores, permits, or renders credentials.

### New minimal model `Bloomwire::WhatsappSetup` (table `bloomwire_whatsapp_setups`)
Justified because the "readiness/status" concept (incl. a `pending` state that can exist *before* a channel)
does not exist in Chatwoot. Columns:
- `account_id` (required FK), `inbox_id` (nullable FK), `channel_whatsapp_id` (nullable, unique FK) — references
- `setup_status` — enum `pending` / `configured` / `ready_for_webhook` / `blocked` (default `pending`)
- `status_reason` (text)
- non-secret routing ids (nullable): `waba_id`, `phone_number_id`, `display_phone_number` — also the future
  router's lookup seed (`phone_number_id` indexed)
- **no secret/token columns**

### Surface — gated, SuperAdmin-only
Custom `SuperAdmin::BloomwireWhatsappSetupsController` (index/new/create/show/edit/update), mirroring the
existing custom Bloomwire SuperAdmin page. Strong params permit **only** non-secret fields.
- **Gating:** `before_action` requires `Bloomwire::Features.master_enabled?`. Master OFF ⇒ redirect to the
  SuperAdmin root (surface unavailable = stock) and the nav link is hidden. Master ON ⇒ surface available + a
  gated nav link is shown. (The resource is also added to the SuperAdmin auto-nav skip-list, like the other
  custom Bloomwire/app_config resources, since it has no Administrate dashboard.)
- **Access control:** the whole `/super_admin` area requires `authenticate_super_admin!` (a separate `SuperAdmin`
  Devise identity), so account users / business owners / staff cannot reach it (they are redirected to the
  SuperAdmin login).

## Alternatives considered
- **No new model (reuse provider_config only):** rejected — there is nowhere to record readiness/status or a
  pre-channel `pending` intent without a new row.
- **Administrate dashboard:** rejected for this slice — namespaced-model + gating/nav control is cleaner with a
  custom controller that matches the existing Bloomwire SuperAdmin page.
- **Duplicating secrets onto the mapping:** rejected — violates the source-of-truth rule; secrets stay in
  `provider_config`.

## Consequences
- Ops gets a single readiness surface; the future webhook router can resolve account/inbox via the mapping's
  non-secret `phone_number_id` / `waba_id` (indexed) or the channel.
- OFF ⇒ byte-for-byte stock Chatwoot (surface hidden + gated). No tenant-facing change.
- No secret duplication; privacy hardening behavior (2A/2B/2C) is unaffected and still protects credentials.

## Evidence (this slice)
- Tests: new request spec **12 examples / 0 failures** (access-control, OFF-gate, CRUD, invalid-status,
  privacy no-secret, data integrity); regression Phase 1/2A/2B/2C **53 / 0**. RuboCop: **no offenses**.
- Runtime (SuperAdmin, dev): unauthenticated ⇒ redirect to SuperAdmin login; master OFF ⇒ surface redirects +
  nav link hidden; master ON ⇒ index/new/edit/show render, browser create+update round-trip persists status,
  nav link shown; with privacy ON the surface shows non-secret routing ids/status and **does not** leak the
  linked channel's `api_key` / `webhook_verify_token`. Only pre-existing dev-tooling console errors observed.

## NOT done here (explicitly out of scope)
Global Meta webhook router/endpoint, managed onboarding wizard, routing registry, multi-tenant router, outgoing
gateway, AI bot, analytics, impersonation/audit, billing, and any real Meta send/receive E2E.
