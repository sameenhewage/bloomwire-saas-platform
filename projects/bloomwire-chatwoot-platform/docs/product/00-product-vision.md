# 00 — Product Vision

## Problem

Businesses want WhatsApp customer messaging, but Meta onboarding (WABA creation, number registration, webhook setup,
template/approval) is complex. Bloomwire/Unecast offers a **managed** path: an Ops team onboards and operates WhatsApp
for tenant businesses on a Chatwoot base.

## Vision

A multi-tenant, Chatwoot-based platform where Bloomwire Ops can provision and route WhatsApp numbers for many tenant
businesses through a single Meta app + global webhook front-door, while tenants get the native Chatwoot inbox/agent
experience.

## Principles

- Build **additively** on Chatwoot; never fork the conversation engine.
- Every managed capability is **feature-toggle gated** and **OFF by default**.
- Chatwoot remains the **source of truth** for conversations / contacts / messages.
- Privacy and tenant isolation are first-class (see the privacy phase in the architecture plan).

## Success

- A managed tenant can receive **and** reply to WhatsApp messages routed via the Bloomwire front-door.
- With all toggles OFF, the platform is indistinguishable from stock Chatwoot.
