# 04 — PRD: First Implementation Slice

> **Status: documented only. Not implemented in this PR.**

## Slice name

**Bloomwire Business Profile + Super Admin Business List**

## Why this slice first

It is the smallest end-to-end piece that proves the Bloomwire SaaS layer can sit
on top of Chatwoot: capture business profile metadata for a tenant, and let a
Super Admin see all tenants enriched with that metadata. It touches the tenant
model, a Bloomwire-owned table, and a control-plane view without duplicating any
Chatwoot conversation data.

## Acceptance truth (rule 1)

- **User expects:** Bloomwire admins to see business tenants with SaaS metadata.
- **Current system does:** only has Chatwoot accounts and **no** Bloomwire SaaS
  metadata.
- **Done means:** a Super Admin can view businesses with **business name,
  industry, plan, status, onboarding status, and created date**.

## Scope of this slice (when implemented later)

- A Bloomwire-owned business profile record (`bloomwire_` prefixed table) linked
  to a Chatwoot account (the tenant).
- Fields: business name, industry, plan, status, onboarding status, created
  date.
- A Super Admin "Business List" view that lists tenants with those fields.
- Backend-enforced access: only platform roles (Super Admin / Ops) can view the
  full list.

## Explicitly NOT in this slice

- No billing automation, no plan enforcement logic.
- No editing of Chatwoot conversation/contact data.
- No duplication of Chatwoot conversation/message/contact history.
- No Chatwoot Enterprise dependency.

## Verification the slice will require (later, rule 6)

- Runtime proof the Business List renders real tenant rows with correct
  metadata.
- Source-of-truth check: Chatwoot account count maps correctly to listed
  tenants, or safe exclusions are explained.
- Safe DTO check: no raw internal IDs, phone numbers, or tokens exposed in the
  API powering the list.

> This document defines the slice. Implementation is a separate, future PR.
