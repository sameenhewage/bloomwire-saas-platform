# ADR 0001 — Technical Baseline

- **Status:** Accepted (architecture / documentation phase)
- **Date:** 2026-06-25
- **Context source:** `../research/bloomwire-final-feature-toggle-architecture-plan.md` + S-01…S-07 runtime evidence.

## Context

Bloomwire/Unecast adds managed WhatsApp onboarding on top of Chatwoot. We must add tenant-facing and Ops capabilities
without forking Chatwoot or breaking stock behavior.

## Decision

1. **Build additively on Chatwoot**, behind feature toggles that default OFF; **Feature-OFF == stock Chatwoot** (S-07
   baseline).
2. **Reuse the native WhatsApp pipeline** for inbound routing, idempotency, outbound send, and status reconciliation
   (S-01…S-04 proven); do not reimplement it.
3. **Routing registry is control-plane** (non-secret routing identifiers + status); Chatwoot stays source of truth; no
   duplication of messages / contacts / conversations.
4. **Global webhook front-door** uses one Meta app + global app secret and a **Bloomwire-owned global verify token**; it
   verifies + forwards the unmodified payload to the native job. Registry-first routing requires an explicit job overlay —
   it is not free with the stock job.
5. **Extend, don't edit, stock files** where possible — prefer `prepend_mod_with` / view overrides / middleware; each
   must be a **no-op when the toggle is OFF**.
6. **Secrets:** never committed; `provider_config` secret-at-rest is a Phase 2 decision gate (encrypt or accept+document).

## Consequences

- Net-new Bloomwire behavior is independently testable and reversible (toggle OFF).
- Live Meta-dependent steps (GET handshake, real send, media) remain BLOCKERs until Phase 9.
- First implementation slice: Phase 1 feature-toggle foundation.

## Alternatives rejected

- Forking Chatwoot / editing the conversation engine (too risky; breaks upgrades).
- Duplicating data into Bloomwire-owned tables (violates source-of-truth).
- Copying WhatsWay (clean-room; concepts only).
