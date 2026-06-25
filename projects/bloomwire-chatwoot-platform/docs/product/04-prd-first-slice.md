# 04 — PRD: First Slice (Phase 1 — Feature-Toggle Foundation)

## Goal

Ship the central feature-toggle control surface **dark** (every toggle OFF → zero behavior change).

## Scope

- `Bloomwire::Features` service: master AND-gate + `InstallationConfig`-backed keys, defaults OFF.
- **SuperAdmin-only** "Bloomwire" control page, **reachable regardless of master state** — it hosts the master toggle, so
  it is the **bootstrap surface** and cannot be gated behind the toggle it sets. Only the **sub-feature toggles + managed
  behavior** are gated behind master ON.
- Reuse `GlobalConfigService`.

## Acceptance truth

- **User expects:** a single ON/OFF control surface that changes nothing until used.
- **Current system does:** stock Chatwoot with no Bloomwire control surface.
- **Done means:** with toggles OFF, **tenant-facing / runtime** behavior equals the S-07 `develop` baseline; the master
  AND-gate forces sub-features OFF; the SuperAdmin control page is **reachable with master OFF** (so Bloomwire can be
  enabled from the UI — **no out-of-band DB edits**), is **SuperAdmin-only**, and exposes **no managed behavior** until
  master ON.

## Tests

- Unit: master AND-gate forces sub-OFF; defaults OFF.
- Request: control page **reachable to SuperAdmin with master OFF** (bootstrap); **forbidden to non-SuperAdmin**;
  sub-feature controls inert until master ON.
- **Feature-OFF regression** specs proving **tenant-facing** parity with `develop`.

## Out of scope for this slice

Any behavior-changing managed feature (webhook router, native-setup restriction, and privacy controls land in later
phases).

## Why first

Zero-risk, Meta-independent foundation that every later phase depends on.
