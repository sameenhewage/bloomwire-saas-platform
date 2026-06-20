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
- Chatwoot source integration/import strategy will be decided in the runtime
  baseline slice before any Bloomwire application feature work begins.

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

## Fast demo path

The next work should stay lean and prove the product quickly:

1. **Slice 0 — Chatwoot Runtime Baseline**
   - prove Chatwoot CE can boot in the chosen repo/environment;
   - prove login and basic inbox/conversation path;
   - define the VPS/HTTPS demo path;
   - no Bloomwire SaaS features yet.
2. **Slice 1 — Bloomwire Business Profile + Super Admin Business List**
   - let Bloomwire admins see business tenants enriched with SaaS metadata
     (business name, industry, plan, status, onboarding status, created date).

See:

- `docs/product/05-prd-slice-0-chatwoot-runtime-baseline.md`
- `docs/product/04-prd-first-slice.md`

Both slices are documented only in this PR. Implementation is separate.
