# Bloomwire / Unecast — Project Context (CONTEXT.md)

> Project-specific contract. **Extends — never overrides — the global rules in root `AGENTS.md` / `CLAUDE.md`.**
> Read this before working anywhere under `projects/bloomwire-chatwoot-platform/`.

## What this project is

Bloomwire/Unecast is a **managed WhatsApp onboarding** layer built **on top of Chatwoot** (the base system kept under
`app/`). It lets a Bloomwire Ops team onboard and operate WhatsApp Business numbers on behalf of tenant businesses,
while tenants use the standard Chatwoot inbox/agent experience.

## Non-negotiable contract

- **Additive + feature-toggle protected.** Every Bloomwire behavior ships behind a toggle that defaults **OFF**.
- **Feature OFF == stock Chatwoot (tenant-facing).** With all toggles OFF, **tenant-facing / runtime behavior and the
  conversation engine** behave exactly like the `develop` baseline (S-07). The **only** OFF-state addition is the
  **SuperAdmin-only** Bloomwire control page — the master-toggle **bootstrap surface**, reachable with master OFF so the
  feature can be enabled from the UI (no out-of-band DB edits) — which has **zero tenant-facing impact**.
- **Chatwoot stays source of truth.** No duplication of conversations / messages / contacts. The routing registry holds
  **non-secret** routing identifiers + status only.
- **Secrets never duplicated, never committed.** `.env` stays untracked. Meta secrets live in
  `Channel::Whatsapp#provider_config`; secret-at-rest encryption is a Phase 2 decision gate (encrypt or accept+document).
- **WhatsWay is reference-only.** Concepts may inform design; never copy its code or architecture.
- **Pricing / billing out of scope.**

## Source of truth / ownership

- **Inbound routing:** native `Webhooks::WhatsappEventsJob` resolves the channel by payload metadata; the registry is
  control-plane (ownership / status / onboarding), not the hot-path router.
- **Outbound + status:** native pipeline (`SendOnWhatsappService` → `WhatsappCloudService`); status reconciliation keys
  off `source_id`.
- **One behavior = one owner** (see the architecture plan).

## Where things live

- **Build-ready architecture:** `docs/research/bloomwire-final-feature-toggle-architecture-plan.md`
- **Runtime evidence (S-01…S-07):** `docs/research/bloomwire-s0*-*.md`
- **Decisions:** `docs/adr/0001-technical-baseline.md` + the decision register in
  `docs/research/bloomwire-evidence-review-and-decision-register.md`
- **Product framing:** `docs/product/`

## Status

Architecture / documentation phase. **No product code yet.** First implementation slice = Phase 1 feature-toggle
foundation (see `docs/product/04-prd-first-slice.md`).
