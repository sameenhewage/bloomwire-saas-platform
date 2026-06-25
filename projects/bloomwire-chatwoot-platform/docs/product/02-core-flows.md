# 02 — Core Flows

## 1. Managed WhatsApp onboarding (Ops)

Ops provisions a WABA / number on behalf of a tenant → creates `Channel::Whatsapp` + `Inbox` → writes the routing
registry (non-secret identifiers + status). Detailed states live in the architecture plan onboarding state machine.

## 2. Inbound message routing

Meta → Bloomwire **global webhook front-door** → verify signature with the global app secret → forward the
**unmodified** payload → native `WhatsappEventsJob` resolves the channel by payload metadata → message persisted in the
correct inbox. Idempotent by `wamid` / `source_id`.

## 3. Outbound + status

Native `MessageBuilder` → `SendReplyJob` → `SendOnWhatsappService` → `WhatsappCloudService#send_message` (the single
Meta seam). Status reconciliation keys off `source_id` (`sent → delivered → read → failed`).

## 4. Restrict native customer WhatsApp setup

For managed tenants, hide the native WhatsApp setup UI **and** guard the APIs (toggle-gated); Ops remains exempt.

> See `../research/bloomwire-final-feature-toggle-architecture-plan.md` for the build-ready detail and runtime proofs.
