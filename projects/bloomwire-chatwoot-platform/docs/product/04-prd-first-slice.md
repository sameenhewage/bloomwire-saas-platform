# 04 — PRD: First Slice (Phase 1 — Feature-Toggle Foundation)

## Goal

Ship the central feature-toggle control surface **dark** (every toggle OFF → zero behavior change).

## Scope

- `Bloomwire::Features` service: master AND-gate + `InstallationConfig`-backed keys, defaults OFF.
- Gated super-admin "Bloomwire" page (visible only when the master toggle is ON).
- Reuse `GlobalConfigService`.

## Acceptance truth

- **User expects:** a single ON/OFF control surface that changes nothing until used.
- **Current system does:** stock Chatwoot with no Bloomwire control surface.
- **Done means:** toggles OFF → the app equals the S-07 `develop` baseline; the master AND-gate forces sub-features OFF;
  the page is hidden unless the master toggle is ON.

## Tests

- Unit: master AND-gate forces sub-OFF; defaults OFF.
- Request: page hidden unless master ON.
- **Feature-OFF regression** specs proving parity with `develop`.

## Out of scope for this slice

Any behavior-changing managed feature (webhook router, native-setup restriction, and privacy controls land in later
phases).

## Why first

Zero-risk, Meta-independent foundation that every later phase depends on.
