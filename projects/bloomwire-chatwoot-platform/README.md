# Bloomwire / Unecast (Chatwoot-based) — Project

Managed WhatsApp onboarding on top of Chatwoot, behind feature toggles. With every toggle **OFF** the platform is stock
Chatwoot.

## Documentation map

- **`CONTEXT.md`** — project contract (read first).
- **`docs/product/`** — vision, users/roles, core flows, scope, first-slice PRD.
- **`docs/adr/0001-technical-baseline.md`** — baseline technical decision.
- **`docs/research/`** — build-ready architecture plan + S-01…S-07 runtime evidence + decision register.

## Status

Architecture / documentation only. No product code, branches, or migrations yet.

## Golden rules

See `CONTEXT.md` and root `AGENTS.md`: additive + toggle-gated; **Feature-OFF preserves stock Chatwoot**; Chatwoot is
source of truth; secrets are never committed.
