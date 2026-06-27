# Phase 10B — Dev Deployment Stabilization

Status: **PASS** (record of the dev deployment + the stabilization learnings folded back into the repo).

This document records what was deployed to the dev testing server, the real Meta inbound smoke result, and
the deployment learnings that are now fixed/documented in the codebase. **No secrets appear here — only masked
or presence values.** The operational how-to lives in
[`../ops/whatsapp-webhook-deployment-runbook.md`](../ops/whatsapp-webhook-deployment-runbook.md).

## What is deployed

- **Host / URL:** `dev.unecast.com` (Contabo testing server) — testing only, data disposable.
- **Code:** `version_1 @ 7ade9dc` (PR #41 merge), image built from that commit (`/app/.git_sha` == `7ade9dc…`).
- **Stack:** Docker Compose project `app` — services `rails`, `sidekiq`, `postgres` (pgvector/pg16), `redis`.
  Host **nginx** terminates TLS (Let's Encrypt) and reverse-proxies `dev.unecast.com` → `127.0.0.1:3000`.
- **Bloomwire toggles (dev):** `BLOOMWIRE_MODE_ENABLED`, `BLOOMWIRE_PRIVACY_HARDENING`,
  `BLOOMWIRE_GLOBAL_WEBHOOK_ROUTER`, `BLOOMWIRE_RESTRICT_NATIVE_WHATSAPP_SETUP` all ON.

## Real Meta inbound smoke — PASS

End-to-end validated on dev (masked evidence):

- Meta webhook **GET verification** → HTTP 200 + challenge echoed (`global webhook verification succeeded`).
- Real inbound **POST** from Meta → **signature valid** (`WHATSAPP_APP_SECRET` HMAC) → router resolved the
  setup by `phone_number_id` (`****8541`) → handoff-safe → `Webhooks::WhatsappEventsJob` performed → a
  conversation + incoming message were created in the correct inbox (account/inbox aligned with the setup).
- Negative checks: bad signature → **401**; valid signature + unknown `phone_number_id` → **200 fail-closed**
  (no enqueue, no wrong-inbox write); wrong verify token → **401**.
- No outgoing send/reply was made (incoming-only).

## Learnings folded into the repo

1. **Docker build metadata (`.git_sha`) must not assume `.git` is in the build context.**
   Upstream generates `.git_sha` with `RUN git rev-parse HEAD` and then `rm -rf .git`, which assumes the build
   context contains a git checkout. This fork keeps the Rails app under `app/` with `.git` at the repo root, and
   the production compose build context is `app/` (no `.git`), so the original step failed the build. Fixed in
   `app/docker/Dockerfile`: resolve the sha from the `GIT_SHA` build arg first, fall back to `git rev-parse`
   when a checkout is present, else `"unknown"` — the build never fails. `.git_sha` is display-only; no runtime
   behavior change. See `docs/adr/0005-…` for the decision entry.

2. **`phone_number_id` must be the exact Meta value, never inferred from a masked last-4.**
   During the smoke, the seeded `phone_number_id` shared the same last-4 as Meta's real value but differed in
   the middle digits, so `Bloomwire::Webhooks::WhatsappRouter#resolve` (which keys on `phone_number_id`) failed
   closed and no message routed. Mapping seeds and `.env` sources must carry the **full, exact** Meta
   `phone_number_id` (and `display_phone_number`); masked values are for reporting only.

3. **The global verify token must never be logged, and nginx must not log webhook query strings.**
   The application never logs the verify token, but nginx's default access log captured it once because Meta
   sends `hub.verify_token` in the GET query string. nginx now logs the webhook path **without** the query
   string for `/bloomwire/webhooks/whatsapp` (see runbook). Verify-token rotation procedure is in the runbook.

4. **`.env` stays gitignored and is never committed.** Secrets (app secret, access token, verify token, DB
   password, full phone identifiers) live only in the server-local `.env` / `InstallationConfig`. This PR does
   not add, move, or commit any secret.

## Scope note

This phase only stabilizes deployment metadata + documents the runbook. It does **not** touch runtime secrets,
CI/CD, production planning, role-lockdown, UI, or feature behavior.
