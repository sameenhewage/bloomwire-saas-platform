# ADR 0001 — Technical Baseline

- **Status:** Accepted
- **Date:** 2026-06-20
- **Context:** Bloomwire SaaS platform foundation

## Context

Bloomwire is an omnichannel customer service SaaS platform. We need a clear
technical baseline before any implementation so the SaaS layer is built on top
of a proven conversation engine without duplicating its data or depending on
proprietary code.

## Decision

1. **Chatwoot Community Edition is the base engine.** Bloomwire builds on
   Chatwoot CE for all omnichannel conversation capabilities.
2. **Bloomwire adds a SaaS layer on top.** Business profiles, plans,
   subscriptions, feature flags, custom roles/permissions, audit logs, usage
   analytics, onboarding steps, and industry presets are Bloomwire-owned.
3. **Chatwoot DB remains the operational source of truth** for conversations,
   messages, contacts, and inboxes. Bloomwire does not duplicate this data.
4. **Bloomwire tables only add SaaS metadata / control** and use the
   `bloomwire_` prefix. They reference Chatwoot entities by identifier; they do
   not copy Chatwoot history.
5. **No Chatwoot Enterprise dependency.** No Enterprise code is copied,
   imported, used, or depended on.
6. **Roles/permissions are backend-enforced.** Frontend hiding is UX only.
7. **Deployment target (later):** Docker + GitHub Actions (CI/CD) + VPS +
   PostgreSQL + Redis + Sidekiq + Nginx/HTTPS.

## Multi-tenancy

- One Chatwoot account = one Bloomwire business tenant.
- One Chatwoot inbox = one connected customer channel.

## Consequences

- **Positive:** fast time-to-value, no re-implementation of messaging, clean
  separation between conversation engine (Chatwoot) and SaaS control (Bloomwire),
  no licensing risk from Enterprise code.
- **Trade-offs:** Bloomwire is coupled to Chatwoot CE's data model and upgrade
  cadence; integration must respect Chatwoot's supported extension points.
- **Constraints carried forward:** no data duplication, no Enterprise code,
  `bloomwire_` table prefix, backend-enforced permissions, safe DTOs only.

## Status of code

- This ADR is part of the documentation foundation. **No application code and no
  Chatwoot source import** are introduced by the decision itself.
