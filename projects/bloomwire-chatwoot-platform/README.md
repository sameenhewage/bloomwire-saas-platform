# Bloomwire SaaS Platform

Bloomwire is an **omnichannel customer service SaaS platform** built on top of
**Chatwoot Community Edition**. This folder holds the project's documentation and
architecture context. No application code lives here yet.

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

- **Phase:** documentation + architecture foundation only.
- **No application code** has been written for Bloomwire.
- **Chatwoot source has not been imported** into this project yet.
- Chatwoot source integration/import strategy will be decided in a separate
  baseline PR before any Bloomwire application feature work begins.

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

## First implementation direction

After this documentation foundation is merged, the first real slice is:

> **Bloomwire Business Profile + Super Admin Business List** — let Bloomwire
> admins see business tenants enriched with SaaS metadata (business name,
> industry, plan, status, onboarding status, created date).

Before that slice starts, complete **Slice 0 — Chatwoot Runtime Baseline** if
Chatwoot source is not already present and running in the repo/environment.

See `docs/product/04-prd-first-slice.md`. It is documented, **not implemented**,
in this PR.
