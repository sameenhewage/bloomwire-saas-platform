# 04 — PRD: First Implementation Slice

> **Status: implemented and merged into `version_1` via PR #3.**
>
> This file is the historical PRD for the first implementation slice. Current
> phase tracking lives in `05-development-phases.md`.

## Slice name

**Bloomwire Business Profile + Super Admin Business List**

## Prerequisite slice

Before implementing this slice, complete **Slice 0 — Chatwoot Runtime Baseline**
if Chatwoot source is not already present and running in the repo/environment.
That prerequisite should prove the Chatwoot baseline boots and is ready for
Bloomwire feature work without adding SaaS features yet.

## Why this slice first

It is the smallest end-to-end piece that proves the Bloomwire SaaS layer can sit
on top of Chatwoot: capture business profile metadata for a tenant, and let a
Super Admin see all tenants enriched with that metadata. It touches the tenant
model, a Bloomwire-owned table, and a control-plane view without duplicating any
Chatwoot conversation data.

## Acceptance truth (rule 1)

- **User expects:** Bloomwire admins to see business tenants with SaaS metadata.
- **System needed:** Chatwoot accounts enriched with Bloomwire SaaS metadata.
- **Done means:** a Super Admin can view businesses with business name, industry,
  plan, status, onboarding status, and created date.

## Implemented scope

- A Bloomwire-owned business profile record linked to a Chatwoot account.
- Business metadata fields for industry, plan, status, and onboarding status.
- A Super Admin Business List / Show view.
- Backend route under the Super Admin namespace.

## Explicitly NOT in this slice

- No billing automation or plan enforcement.
- No create/edit/delete UI for business profiles.
- No editing or copying of Chatwoot conversation, contact, or message data.
- No Chatwoot Enterprise dependency.

## Verification completed

- Super Admin Businesses list rendered real tenant rows with business metadata.
- Existing Super Admin Accounts and Users pages still worked.
- Model and request specs passed.
- Source-of-truth rule preserved.

## Next phase

See `05-development-phases.md`.

Current phase after this slice: **Phase 2 — Tenant Readiness / Data Consistency**.
Next coding slice: `feature/bloomwire-business-profile-backfill`.
