# Bloomwire SaaS Platform

Bloomwire is an **omnichannel customer service SaaS platform** built on top of
**Chatwoot Community Edition**. This folder holds the project's documentation and
architecture context; the Chatwoot CE application and Bloomwire SaaS features live
in the repo's `app/` directory.

---

## What Bloomwire is

Bloomwire lets businesses run customer conversations across many channels
(WhatsApp, web chat, email, social) from one place, while giving the SaaS
operator (Bloomwire) tools to manage business tenants, plans, roles, usage, and
compliance. The conversation engine is Chatwoot; Bloomwire adds the SaaS and
business-management layer around it.

## Why Chatwoot

- Chatwoot CE is a mature, open-source **omnichannel conversation engine**: it
  already handles accounts, inboxes, contacts, conversations, messages, teams,
  labels, campaigns, automation, and reporting.
- Building on Chatwoot lets Bloomwire focus on the **SaaS/business layer**
  (tenancy, plans, roles, audit, analytics, onboarding, industry presets)
  instead of rebuilding messaging from scratch.
- **Community Edition only.** No Chatwoot Enterprise code is used.

## Current repo status

- **Phase:** Phase 4 — Roles & Permissions Engine (Slice 1 merged). Phases 0–3
  are complete and merged into `version_1`.
- **Chatwoot CE is running** as the base engine (source in the repo's `app/`
  directory); Bloomwire SaaS features are built additively on top of it.
- **Built so far:** Bloomwire business profiles + Super Admin businesses list,
  tenant readiness backfill, tenant setup foundation, onboarding step tracking +
  progress UI, Chatwoot readiness mapping, manual tenant activation gate, and the
  first permission foundation (`Bloomwire::AccessPolicy`).
- **Source of truth:** Chatwoot owns conversations / messages / contacts;
  Bloomwire never duplicates them. No Chatwoot Enterprise / `custom_roles`
  dependency; permissions currently reuse Chatwoot `AccountUser` roles (Bloomwire
  roles tables are future-only).
- See `docs/product/05-development-phases.md` (execution source of truth) and
  `docs/system-overview/index.html` (living overview + changelog) for detail.

## How work is organized

All Bloomwire project docs live under this folder:

```
projects/bloomwire-chatwoot-platform/
  CONTEXT.md                  # project contracts (read first)
  README.md                   # this file
  docs/product/               # vision, users, flows, scope, PRD
  docs/adr/                   # architecture decisions
  docs/research/              # market & fit-gap research
```

Root-level shared assets (`AGENTS.md`, `CLAUDE.md`, `.claude/`, `docs/agents/`)
stay at the repo root and are never copied here.

## Branch workflow

```
feature/*  →  version_1  →  develop  →  main
   (work)     PR+approve   PR+approve  PR+approve
```

- Real work happens on **`feature/*`** branches, created off `version_1`.
- `version_1`, `develop`, and `main` are **protected** (PR + 1 approval).
- Never push directly to a protected branch.

## Demo path

The lean demo path is built and runtime-verified:

1. **Chatwoot Runtime Baseline** — Chatwoot CE boots and logs in; the VPS/HTTPS
   demo path is defined.
   (`docs/product/05-prd-slice-0-chatwoot-runtime-baseline.md`)
2. **Bloomwire Business Profile + Super Admin Businesses** — Bloomwire admins see
   business tenants enriched with SaaS metadata (industry, plan, status,
   onboarding status, Chatwoot readiness) at `/super_admin/bloomwire/businesses`,
   and can manually activate a ready tenant.
   (`docs/product/04-prd-first-slice.md`)

For the full, current list of everything built (Phases 0–4 Slice 1), see
`docs/product/05-development-phases.md` and the living
`docs/system-overview/index.html`.
