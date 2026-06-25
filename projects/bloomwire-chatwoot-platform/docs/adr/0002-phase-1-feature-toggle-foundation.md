# ADR 0002 — Phase 1: Feature-Toggle Foundation Contract

- **Status:** Accepted
- **Date:** 2026-06-26
- **Context source:** `../research/bloomwire-final-feature-toggle-architecture-plan.md` (§4 toggles, §5 super-admin
  surface, §12 Phase 1), `../product/04-prd-first-slice.md`, and ADR-0001.

## Context

Phase 1 ships the Bloomwire control surface **dark** (every toggle OFF → zero tenant-facing change). The architecture
plan §4.1 lists the toggle keys as **"suggested"** and §5 **recommends** a separate SuperAdmin page (Option B). Turning
those into an implementable contract requires pinning the **exact** key names, the storage mechanism, the route/auth
boundary, and the precise "master OFF / sub-feature inert" semantics. Per the project process these concrete choices
are recorded here instead of being made silently. This ADR **extends** (never overrides) ADR-0001.

## Decision

1. **Toggle keys** (`InstallationConfig` names), all default **OFF**:
   `BLOOMWIRE_MODE_ENABLED` (master), `BLOOMWIRE_MANAGED_WHATSAPP_ONBOARDING`, `BLOOMWIRE_GLOBAL_WEBHOOK_ROUTER`,
   `BLOOMWIRE_RESTRICT_NATIVE_WHATSAPP_SETUP`, `BLOOMWIRE_PRIVACY_HARDENING`, `BLOOMWIRE_OUTGOING_GATEWAY`,
   `BLOOMWIRE_CUSTOM_BRANDING`.
2. **Service API** — `Bloomwire::Features` (`app/lib/bloomwire/features.rb`) is the **single** place toggles are read
   (plan §4.2; no scattered `ENV` reads). Public surface: `enabled?(feature)` for
   `:mode | :managed_whatsapp_onboarding | :global_webhook_router | :restrict_native_whatsapp_setup |
   :privacy_hardening | :outgoing_gateway | :custom_branding`; `master_enabled?`; `raw_enabled?(feature)` (stored value
   **without** the AND-gate, for the bootstrap page UI). An unknown feature raises `ArgumentError`.
3. **Storage** — values are read via `GlobalConfigService.load(KEY, false)` (`InstallationConfig` + Redis cache; the same
   mechanism `WHATSAPP_*`/`FB_*` already use). Keys are registered in `config/installation_config.yml` as
   `type: boolean`, `locked: false`, `value: false` so they seed OFF and typecast to real booleans.
4. **Master AND-gate** — `enabled?(sub)` is **false whenever master is OFF**, regardless of the stored sub value.
   `enabled?(:mode)` returns the master value.
5. **Privacy-hardening prerequisite** (managed-data dependency, plan §4.1) —
   `enabled?(:managed_whatsapp_onboarding)` and `enabled?(:global_webhook_router)` are additionally **false unless
   `privacy_hardening` is ON** (fail-closed). Included in the Phase 1 service contract.
6. **SuperAdmin bootstrap page** — `namespace :super_admin` → `resource :bloomwire_config, only: [:show, :create]` →
   `SuperAdmin::BloomwireConfigsController < SuperAdmin::ApplicationController` (inherits `authenticate_super_admin!`,
   Devise `:super_admin` scope) + view `app/views/super_admin/bloomwire_configs/show.html.erb`. The page itself is
   **not** gated by `Bloomwire::Features` — it is the bootstrap surface that hosts the master toggle, so it is reachable
   to a SuperAdmin **even when master is OFF**. The `/super_admin` Devise scope is **separate** from the tenant `:user`
   scope, so tenant workspace users and unauthenticated requests are redirected (forbidden).
7. **Master OFF / sub-feature inert** — three layers: (a) `Bloomwire::Features.enabled?(sub)` returns false (the
   behavioral guarantee); (b) the page renders sub-feature controls inside a `disabled` `<fieldset>` while master is
   OFF; (c) the controller **ignores sub-feature params while master is OFF**, so a crafted POST cannot store a
   sub-feature ON during master-OFF. Managed-data toggles are likewise disabled in the UI while privacy hardening is OFF.

## Consequences

- Every later phase reads ON/OFF only through `Bloomwire::Features`; **rollback = master OFF**.
- Phase 1 adds **no tenant-facing seam**: OFF = stock Chatwoot for tenants (the only additive surface is the
  SuperAdmin-only page).
- Boolean configs reuse the plan-cited `GlobalConfigService` path, so the proven admin + cache mechanism is reused.

## Alternatives rejected

- Scattered `ENV['BLOOMWIRE_*']` reads — plan §4.2 mandates one seam.
- Folding toggles into the existing `app_config` page (Option A) — the dedicated page keeps OFF = stock and rollback
  trivial (plan §5 Option B).
- Gating the page itself behind the master toggle — impossible: the page **hosts** the master toggle (bootstrap surface).
