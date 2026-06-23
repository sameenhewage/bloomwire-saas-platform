# ADR 0006 — Tenant Settings Ownership and Role Boundary

- **Status:** Accepted (decision) — **implementation parked / future (after Phase
  8).** **This lockdown is mandatory before real Dialog / customer admins receive
  production access.** Nothing here is implemented yet; do not claim any of it is
  enforced.
- **Date:** 2026-06-23
- **Extends:** ADR 0003 (Permission & Channel-Control Boundary) and ADR 0005
  (External App Configuration Ownership). Relates to ADR 0004 (Global Meta/WhatsApp
  Webhook Router, Phase 8) and ADR 0002 (Enterprise Boundary). **This ADR
  cross-references those decisions and does NOT replace them.**
- **Scope:** documentation-only. **No code, configuration, route, migration,
  schema, spec, or runtime behavior is changed by this ADR.** It records a decision
  and a parked future slice.

---

## Context

ADR 0003 set the durable boundary: **platform owns tenant/channel setup; Dialog
(tenant) admins do not by default.** ADR 0005 turned that into concrete WhatsApp
ownership and — in `4.4-b-WA.2A`–`2C` — shipped the `bloomwire_channel_integrations`
ownership model, the Bloomwire Admin setup path, and **backend deny** of tenant-side
WhatsApp setup/config + managed-inbox destroy for Bloomwire-managed tenants.

What is still missing is the **broad role / settings boundary across the whole
Chatwoot Settings surface** — not just WhatsApp. Bloomwire (the SaaS operator) and
Dialog (the tenant business) have different responsibilities, yet the raw Chatwoot
Settings menu still exposes platform-owned infrastructure (inboxes, bots,
integrations, automation, provider config, webhooks) to tenant admins. **Raw
Chatwoot settings must not be exposed directly to Dialog admins when those settings
can modify platform-owned infrastructure.**

This ADR records the **target ownership split, the per-role boundary, the
settings-menu filtering rule, and the three-layer enforcement requirement**, and
schedules implementation **after Phase 8** — the global webhook router finalizes the
Bloomwire-owned routing/admin surfaces that platform-owned controls move to.

## Decision

### 1. Ownership split

- **Dialog owns business operations** inside the tenant: staff/agents, teams,
  campaigns, labels, macros / canned responses, conversations, contacts, day-to-day
  customer handling, and reports/analytics views where enabled.
- **Bloomwire owns platform / infrastructure:** account/platform settings, external
  app/channel setup, inbox/channel creation + deletion/disconnection,
  WhatsApp/Meta/Instagram/Facebook + SMS/Email/API/Shopify/Telegram/Signal
  integrations, provider credentials, webhook configuration, bots / AI setup, the
  global webhook/router, plan/feature enablement, tenant lifecycle
  (create/activate/suspend), and support/debug access with an audit trail.
- **Raw Chatwoot settings that can modify platform-owned infrastructure must not be
  exposed directly to Dialog admins.**

### 2. Role boundary

#### Bloomwire SuperAdmin (platform plane)

Owns and manages: tenant creation/activation/suspension and platform status;
subscription / plan / feature enablement; external channel setup and ownership;
WhatsApp / Meta / Instagram / Facebook setup; SMS / Email / API / Shopify / Telegram
/ Signal and other integrations; provider credentials and webhook config; AI bot
setup and bot/integration config; Bloomwire-managed inbox/channel **creation**;
Bloomwire-managed inbox/channel **deletion or disconnection**; global webhook/router
config; support/debug access **with an audit trail**. **These controls live on the
Bloomwire/admin side, not inside the Dialog tenant settings UI.**

#### Dialog Business Owner / Dialog Admin (tenant plane)

**May manage (business operations only):** business staff/agents; teams such as
Sales, Enterprise, Marketing, Finance, Support, Returns; campaigns; labels; macros /
canned responses (if enabled); conversation assignment + customer-handling
workflows; contacts and customer operations; reports/analytics views (if enabled).

**Must NOT manage:** account ownership / platform settings; external app/channel
setup; raw inbox/channel creation; WhatsApp / Meta reconnect or reauthorization;
provider credentials; webhook registration; integrations; bots / AI setup; raw
automation or workflow configuration that can affect platform-owned behavior;
Bloomwire-managed inbox deletion.

> **Workflow carve-out (platform vs tenant).** "Raw automation/workflow
> configuration" above means **platform-owned** automation (provider / webhook /
> routing behavior). Dialog Admin **retains tenant-owned conversation assignment and
> customer-handling workflow** — consistent with ADR 0003 (tenant admins own
> conversation workflow inside their tenant) and the "May manage" list above. The
> raw `Automation` / `Conversation Workflow` **settings surfaces** are denied to the
> **Agent** role (below); they are **not** used to strip the Admin's tenant workflow
> ownership.

#### Dialog Agent / Staff (tenant plane)

**May access (day-to-day support only):** conversations / assigned inboxes; contacts
(if enabled); labels / macros / canned-response usage (if enabled); personal profile
/ preferences.

**Must NOT access:** Account Settings; Agents management; Teams management; Inboxes
settings; Bots; Integrations; Automation; Conversation Workflow; Custom Attributes;
external channel setup / configuration.

### 3. Settings menu rule

For Bloomwire-managed tenants, the raw Chatwoot Settings menu must be **filtered by
role**:

- **Dialog Admin** sees only business-operation settings that are safe for tenant
  self-service — **not** the full Chatwoot settings menu.
- **Dialog Agent** sees no Settings menu except personal preferences/profile if
  required.
- Platform / infrastructure settings are **hidden from Dialog users** and moved to
  **Bloomwire SuperAdmin surfaces**.

### 4. Inboxes rule

Dialog users work from the main **Conversations / shared-inbox** area for daily
work. Dialog Admin does **not** need raw `Settings → Inboxes` access for business
operations — raw inbox/channel setup is Bloomwire-owned because it can **create,
connect, disconnect, or modify external customer-communication infrastructure**.

If channel visibility is needed later, provide a **safe read-only `Connected
Channels` page**, for example:

- WhatsApp — Active — Managed by Bloomwire
- Instagram — Pending — Managed by Bloomwire
- Facebook — Active — Managed by Bloomwire

That page must **not** expose provider credentials, webhook tokens, phone number
IDs, business account IDs, routing keys, or raw provider configuration (consistent
with the ADR 0005 safe-DTO / no-credential-exposure rule).

### 5. Teams rule

Teams are **Dialog-owned** business operations. Dialog Admin must be able to create
and manage teams such as Sales, Enterprise, Marketing, Finance, Support, and Returns
**without asking Bloomwire** — manual tenant-team management by Bloomwire would make
the product service-heavy and would not scale as SaaS. **Agents** may not
create/edit/delete teams; they only work inside assigned conversations/teams.

### 6. Bots and integrations rule

Bots and integrations are **Bloomwire-owned** platform/infrastructure
configuration. Dialog Admin must not access raw Bots or Integrations settings. AI bot
setup, external integrations, Shopify, Meta, WhatsApp, SMS, Email, API credentials,
and webhooks are configured **from Bloomwire-side admin surfaces**.

### 7. Enforcement requirement (not UI-only)

Every restricted area needs **three layers** of enforcement:

1. **Sidebar / menu hiding** (UX).
2. **Direct route / URL guard** (a Dialog user typing the settings URL is blocked).
3. **Backend API authorization deny** (a manual API call is rejected).

Frontend hiding alone is **UX, not security** (global backend-enforcement rule; see
ADR 0005). A Dialog user must not be able to bypass restrictions by directly entering
a settings URL or calling the API manually.

## Relationship to existing ADRs (cross-reference, not replacement)

- **ADR 0003 — Permission & Channel-Control Boundary.** 0006 is the concrete
  role / settings-menu expression of 0003's platform-vs-tenant boundary across the
  whole Settings surface. 0003's future per-tenant **capability model** still
  governs any opt-in self-service exceptions.
- **ADR 0005 — External App Configuration Ownership.** 0005 already enforces
  WhatsApp setup/destroy deny for managed tenants (backend, `2C`) plus `2D`
  frontend hiding (merged in PR #25). 0006 **generalizes** that boundary to all platform-owned settings
  (bots, integrations, automation, inboxes, account settings) and **reuses** 0005's
  safe-DTO / no-credential-exposure rule for the read-only `Connected Channels` page.
- **ADR 0004 — Global Webhook Router (Phase 8).** 0006 is sequenced **after** Phase 8
  because the router finalizes the Bloomwire-owned routing/admin surfaces that the
  platform-owned controls move to.
- **0006 does not replace 0003, 0004, or 0005.**

## Timing

- The full Tenant Settings / Role Lockdown is implemented **after Phase 8** (Global
  WhatsApp Webhook Router), which clarifies the final Bloomwire-owned routing/admin
  surfaces.
- **This lockdown is mandatory before real Dialog / customer admins receive
  production access.**
- **Development order.** `4.4-b-WA.2D` (WhatsApp frontend hiding / disabled UX) is
  already **merged (PR #25)**; the remaining sequence is:
  1. Complete Phase 8 — Global WhatsApp Webhook Router.
  2. Implement Tenant Settings Menu Lockdown + Dialog Admin Capability Cleanup.
  3. Run a final security review before production / client access.

## Future slice

**Name:** `Tenant Settings Menu Lockdown + Dialog Admin Capability Cleanup`

**Scope:**

- Hide platform-owned Settings menu items from Dialog Admin and Agent.
- Deny direct URL access to those settings.
- Deny backend API access to those settings.
- Move platform-owned controls to Bloomwire Admin surfaces.
- Keep Teams, Agents, Campaigns, Labels, Macros, and business-operation tools
  available to Dialog Admin where appropriate.
- Keep normal conversation / inbox usage available.
- Ensure the Agent role has day-to-day support access only.

## Consequences

- A clear, role-filtered tenant experience: **Dialog runs the business; Bloomwire
  runs the platform.** Reduced risk of a tenant admin breaking platform-owned
  infrastructure (channels, webhooks, bots, integrations).
- Requires **backend authorization** (policies / route guards) in addition to menu
  hiding, so there are more enforcement points to test (three layers per restricted
  area).
- Some Chatwoot-native settings affordances are removed for Dialog users; any
  genuinely tenant-safe settings must be explicitly **allow-listed**.

## Non-goals / out of scope (for this ADR)

- **Not implemented.** No code, route guard, policy, menu change, migration, schema,
  spec, or frontend change ships with this ADR. **Do not claim enforcement exists.**
- No new capability table or feature flags are created here (the per-tenant
  capability model remains ADR 0003's parked future work).
- Does not change Chatwoot as the conversation engine / source of truth, and does
  not duplicate Chatwoot data.
- Does not re-open or change the WhatsApp `2A`–`2C` behavior already shipped under
  ADR 0005.
