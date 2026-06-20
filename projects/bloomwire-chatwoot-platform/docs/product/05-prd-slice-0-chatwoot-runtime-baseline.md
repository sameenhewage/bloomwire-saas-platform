# 05 — PRD: Slice 0 — Chatwoot Runtime Baseline

> **Status: documented only. Not implemented in this PR.**

## Slice name

**Chatwoot Runtime Baseline**

## Why this slice comes before SaaS features

Before Bloomwire adds business profiles, dashboards, permissions, audit logs, or
usage analytics, the team must prove that the Chatwoot CE baseline can run in the
chosen repo/environment. This keeps the path to a client-testable product short:
first get the conversation engine running, then add the thinnest Bloomwire SaaS
layer on top.

## Acceptance truth (rule 1)

- **User expects:** a working Chatwoot-based platform baseline that can be used
  for fast client testing.
- **Current system does:** has documentation and agent workflow, but no confirmed
  running Chatwoot runtime baseline in this project.
- **Done means:** Chatwoot CE boots successfully in the target development
  environment, login works, a basic inbox/conversation path can be verified, and
  the team has a clear deployment path for VPS/HTTPS testing.

## Scope of this slice (when implemented later)

- Decide and execute the Chatwoot source strategy:
  - preferred: clean Chatwoot CE fork/import strategy that preserves upstream
    maintainability;
  - do not manually drag/drop large Chatwoot source folders without a clear plan.
- Confirm local runtime:
  - dependencies installed;
  - app boots;
  - login works;
  - no obvious console/runtime failures on the first screen.
- Confirm container/deployment baseline where practical:
  - Docker or documented runtime command;
  - PostgreSQL and Redis connection;
  - worker process path understood;
  - Nginx/HTTPS/VPS plan documented for demo hosting.
- Record exact setup commands and environment assumptions in the project README
  or a setup note.

## Explicitly NOT in this slice

- No Bloomwire SaaS feature implementation.
- No business profile table.
- No custom roles/permissions engine.
- No audit or usage analytics tables.
- No WhatsApp provider customization beyond proving the baseline path.
- No Chatwoot Enterprise dependency.

## Verification this slice will require later (rule 6)

- Runtime proof: app boots and login works.
- Browser proof: first usable screen renders without blocking errors.
- Console proof: no critical frontend errors on initial load.
- Network proof: core page/API requests succeed.
- Source-of-truth proof: no duplicated conversation/message/contact storage is
  introduced.
- Deployment proof, if included: public HTTPS URL reaches the app.

## Next slice after this

After Slice 0 passes, implement:

**Bloomwire Business Profile + Super Admin Business List**

That is the first real Bloomwire SaaS feature slice.
