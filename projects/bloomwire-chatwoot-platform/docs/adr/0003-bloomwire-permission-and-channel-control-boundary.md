# ADR 0003 — Bloomwire Permission & Channel-Control Boundary

- **Status:** Accepted (decision) — **implementation parked / future** (Phase 4.3–4.5 + Phase 5)
- **Date:** 2026-06-21
- **Extends:** ADR 0001 (Technical Baseline) and ADR 0002 (Enterprise Boundary &
  Telemetry); builds on the Phase 4 permission foundation (`Bloomwire::AccessPolicy`).
- **Scope:** documentation-only. **No code, configuration, migration, schema,
  spec, feature flag, route, or runtime behavior is changed by this ADR.** It
  records a decision and a set of parked future tasks. Nothing described here is
  implemented yet.

## Context

Chatwoot Community Edition ships powerful **self-service setup surfaces** that are
appropriate for a single-operator install but **risky to expose directly to
enterprise client tenants** in a multi-tenant commercial SaaS. These include:

```text
Settings → Inboxes → Add Inbox
API channel setup
WhatsApp setup
SMS setup
Facebook/Instagram/Telegram setup
WhatsApp Call Beta
New Account
```

Leaving these raw Chatwoot surfaces open to tenant admins is a **control,
security, billing, and compliance** risk: a client could create channels,
connect external providers, or even create new accounts/tenants outside
Bloomwire's control.

> Dev-only observation (not a production claim): in the local/dev environment, an
> account administrator (e.g. the Dialog demo tenant) can reach Chatwoot's stock
> inbox-creation flow, and the "New Account" affordance is enabled via
> `CREATE_NEW_ACCOUNT_FROM_DASHBOARD`. This illustrates **why** the boundary below
> must be made explicit **before** building tenant-facing surfaces.

We therefore record an explicit, durable boundary separating **platform**
responsibilities from **tenant-admin** responsibilities, plus a **future**
capability model for optional, controlled self-service.

## Decision

### 1. Responsibility split (platform vs tenant)

**Bloomwire Platform / Super Admin owns:**

```text
- tenant/account creation
- tenant activation
- channel/inbox setup approval
- WhatsApp/SMS/Email/Instagram/API channel enablement rules
- enterprise/security/compliance configuration
```

**Client tenant admin owns:**

```text
- own tenant users/agents, if allowed
- teams/departments
- team memberships
- conversation workflow inside their tenant
```

**Client tenant admin does NOT own by default:**

```text
- new tenant/account creation
- arbitrary inbox/channel creation
- API channel creation
- WhatsApp/SMS/Facebook/Instagram/Telegram setup
- WhatsApp Call / Enterprise-gated features
- platform-level settings
```

### 2. Product rule — raw Chatwoot channel setup is not exposed by default

**Do not expose raw Chatwoot channel setup pages to enterprise clients by
default.** The raw Chatwoot pages listed in *Context* above must be **controlled
by Bloomwire permissions/capabilities**, not handed to every tenant by virtue of
the underlying Chatwoot account.

### 3. Team management ≠ channel-creation permission

```text
Team management does not imply channel creation permission.
A team is an internal department.
An inbox/channel is an external customer communication connection.
Creating a team must never automatically grant permission to create WhatsApp/SMS/API channels.
```

### 4. Dialog-style enterprise tenants

> Dialog-style enterprise tenants should not receive raw Chatwoot account/channel
> setup access by default. Dialog admins may manage teams and users inside the
> Dialog tenant, but tenant creation and channel/inbox setup remain
> Bloomwire-controlled unless explicit tenant capabilities allow self-service
> setup.

### 5. Future self-service capability model (parked / not implemented)

Some customers may later ask to manage their own channel setup. This will be
supported **later** through **tenant-level feature/capability toggles** — **not**
by giving every customer raw Chatwoot access by default. The intended capability
shape (illustrative; **no table, columns, or feature flags exist yet**):

```text
allow_new_account_creation: false
allow_team_management: true
allow_agent_management: true
allow_self_service_channel_setup: false
allow_whatsapp_setup: request_only | self_service | disabled
allow_sms_setup: request_only | self_service | disabled
allow_email_setup: request_only | self_service | disabled
allow_instagram_setup: request_only | self_service | disabled
allow_api_channel_setup: false
allow_whatsapp_calling: disabled
```

Default posture is **platform-controlled**; self-service is an explicit,
per-tenant opt-in granted by the platform.

## Phase placement

```text
Phase 4 locks down who can create tenants/channels.
Phase 5 builds the controlled customer-facing Channel Readiness / WhatsApp Setup flow.
```

- **Phase 4 — Roles, Permissions & Security Foundation**
  - Already completed: AccessPolicy foundation; ChatwootHub outbound isolation;
    Enterprise boundary / telemetry decision (ADR 0002).
  - Parked next: **Phase 4.3 — New Account / Tenant Creation Lockdown**,
    **Phase 4.4 — Channel / Inbox Creation Lockdown**,
    **Phase 4.5 — Tenant Feature Capabilities**.
- **Phase 5 — Controlled Channel Readiness / WhatsApp Setup Mapping** (builds the
  customer-facing flow on top of the Phase 4 lockdowns).

## Non-goals — explicitly out of scope of this ADR

This ADR records a decision only. It does **not** implement and must not be read
as implementing any of:

```text
- New Account lockdown
- inbox/channel lockdown
- tenant capabilities table
- new feature flags
- WhatsApp setup flow
- backend policy changes
- frontend hiding
- migrations
- app behavior changes
```

## Carried-forward constraints

- **Chatwoot CE / OSS remains the source of truth** for accounts, users,
  account membership, inboxes, channels, contacts, conversations, messages,
  teams, and labels.
- **No Chatwoot conversation / message / contact duplication** into Bloomwire
  tables — reference by identifier, read live.
- **Permissions are backend-enforced**; any future frontend hiding is **UX only,
  not security**.
- **No Chatwoot Enterprise / `custom_roles` dependency**; Bloomwire-owned tables
  use the `bloomwire_` prefix.
- Safe DTOs only (extends global rule 8 / CONTEXT.md security contract).

## Consequences

- **Positive:** an explicit control boundary is set **before** any tenant-facing
  setup surface is built; prevents accidental exposure of raw Chatwoot setup;
  gives a clean, opt-in path to self-service via the future capability model;
  keeps tenant creation and channel enablement billable/governable by the
  platform.
- **Trade-offs:** tenant admins cannot self-serve channels by default; enabling
  self-service later requires building Phase 4.5 (tenant capabilities) and the
  Phase 5 controlled flow. Until then, channel/inbox setup is a
  platform-performed action.

## References

- `0001-technical-baseline.md`, `0002-bloomwire-enterprise-boundary-and-telemetry.md`
- `../../CONTEXT.md`, `../product/05-development-phases.md`,
  `../system-overview/index.html`
- Phase 4 permission foundation: `app/app/services/bloomwire/access_policy.rb`
  (existing; referenced for context only — not modified by this ADR).
