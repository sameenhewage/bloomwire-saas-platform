# ADR 0004 — Bloomwire Global Meta/WhatsApp Webhook Router

- **Status:** Accepted (decision) — **implementation parked / future** (Phase 8)
- **Date:** 2026-06-22
- **Extends:** ADR 0001 (Technical Baseline); sits alongside ADR 0002 (Enterprise
  boundary) and ADR 0003 (permission & channel-control boundary). Relates to
  Phase 5 (channel readiness) and Phase 8 (this router).
- **Scope:** documentation-only. **No code, configuration, migration, schema,
  spec, route, or runtime behavior is changed by this ADR.** It records a decision
  and a set of parked future tasks. Nothing here is implemented yet.

## Context

Today, Meta channels (WhatsApp / Facebook / Instagram) connect to Chatwoot using
Chatwoot's **native, per-inbox webhook setup**: each inbox/channel has its own
Chatwoot-generated webhook URL configured in the Meta app, and Chatwoot's existing
routes handle inbound events. **This works and must keep working.**

For a scalable SaaS, forcing every tenant/inbox to wire up and maintain
Chatwoot-generated webhook URLs forever does not scale:

- one Meta app with many inboxes/numbers means many webhook URLs to manage;
- Meta app webhook verification/config should stay stable — churn risks breakage;
- Bloomwire wants **one global endpoint** and to route events internally.

## Decision

Add a **new Bloomwire-owned global Meta/WhatsApp webhook router** as a **future**
feature (Phase 8). It is **additive** and **does not replace** Chatwoot's native
webhook behavior.

### 1. Chatwoot native webhook behavior stays unchanged (default)

- WhatsApp / Facebook / Instagram continue to use Chatwoot's existing
  webhook/channel setup.
- Existing Chatwoot routes and behavior continue working.
- This is the default; nothing about it changes.

### 2. New global webhook/router (future, additive)

Target flow:

```text
Meta / Facebook / WhatsApp App
  → Bloomwire Global Webhook (one endpoint)
  → Bloomwire Router
  → correct Chatwoot Account + Inbox
  → Chatwoot conversations / messages
```

### 3. Feature toggle / safe default

- Controlled by config: `BLOOMWIRE_GLOBAL_META_WEBHOOK_ENABLED=true|false`.
- **Default is `false` (safe)** — native Chatwoot behavior is untouched when off.
- Later, **tenant/channel-level config** decides, **per inbox**, whether it uses
  the native Chatwoot webhook flow or the Bloomwire global webhook flow.

### 4. Routing identifiers

The router resolves the destination Chatwoot account + inbox using identifiers
such as: `phone_number_id`, `page_id`, `waba_id`, `provider`, `account_id`,
`inbox_id`.

### 5. Constraints

- **Chatwoot remains the conversation engine / source of truth.** The router only
  delivers events to the correct Chatwoot account + inbox.
- **No conversation/message/contact duplication** into Bloomwire tables.
- **Bloomwire-owned (clean-room)** — `bloomwire_` prefixed config/tables if/when
  built; no dependency on Chatwoot Enterprise code.

## Two flows (clear difference)

**Chatwoot native webhook flow — today, default:**

```text
Meta app → Chatwoot per-inbox webhook URL → Chatwoot inbox → conversations/messages
```

Each inbox's webhook URL is configured manually in the Meta app. Unchanged.

**Bloomwire global webhook/router flow — future, toggle-gated:**

```text
Meta app → one Bloomwire global endpoint → Bloomwire router (resolves account+inbox
by identifiers) → hands off to Chatwoot → conversations/messages
```

One stable endpoint; routing is internal to Bloomwire.

## Risks / open questions

- **Safe proxying/routing into Chatwoot** — how to forward events while preserving
  signature validation, payload integrity, idempotency, retries, and ordering.
- **Proxy first vs. internal services later** — whether to **proxy to native
  Chatwoot webhook endpoints first** (reuse existing handlers, lowest risk) or
  **call internal Chatwoot services later** (tighter integration). Proxying to the
  native endpoints first is the likely safer starting point.
- **Runtime test for multi-inbox / multi-number Meta apps** — one Meta app with
  many numbers/pages must route each event to the correct account + inbox; this
  needs a real runtime test, not just unit tests.
- **Meta verification stability** — use the **Bloomwire global webhook from the
  beginning** so the verified Meta callback URL does not have to change later.
  Decide early whether to register the global endpoint with Meta up front.

## Out of scope (this ADR)

No implementation: no global endpoint, no router service, no config/feature flag,
no per-inbox routing config, no migrations/schema, no Chatwoot route changes, no
app behavior change. **Chatwoot native webhook behavior is unchanged.**

## Phase placement

- **Phase 5** prepares the controlled channel readiness and WhatsApp setup mapping
  needed for the future router, but **must not implement the router itself.**
- **Phase 8 — Bloomwire Global Meta/WhatsApp Webhook Router** (this decision) is
  **future / parked**.

## References

- `0001-technical-baseline.md`, `0002-bloomwire-enterprise-boundary-and-telemetry.md`,
  `0003-bloomwire-permission-and-channel-control-boundary.md`
- `../../CONTEXT.md`, `../product/05-development-phases.md`,
  `../system-overview/index.html`
