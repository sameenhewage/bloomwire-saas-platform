# 03 — Feature Scope

## In scope (toggle-gated, OFF by default)

- Feature-toggle foundation (`Bloomwire::Features`, master AND-gate).
- Privacy / security hardening (secret masking, DTO scrubbing, CE-safe support-access audit, log / job-arg scrubbing).
- Managed onboarding + routing registry (control-plane).
- Global webhook front-door (one Meta app + secret, Bloomwire-owned global verify token).
- Native-setup restriction for managed tenants.
- Outgoing gateway support at the Meta seam (later phase).

## Out of scope

- Pricing / billing / plan limits.
- Copying WhatsWay code (concepts only).
- Duplicating messages / conversations / contacts.
- Channels beyond WhatsApp (registry is future-proofed, not populated).
- Replacing or forking the Chatwoot conversation engine.

> Full phase plan: `../research/bloomwire-final-feature-toggle-architecture-plan.md` §12.
