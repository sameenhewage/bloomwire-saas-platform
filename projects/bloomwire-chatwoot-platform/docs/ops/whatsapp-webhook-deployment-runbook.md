# Runbook — Bloomwire WhatsApp Webhook Deployment (dev)

Operational guide for deploying `version_1` to the dev server and operating the Bloomwire global WhatsApp
webhook. **Never paste secrets into this file, chat, logs, PRs, or commits.** Report presence/masked only
(e.g. `present`, `missing`, `****1234`). `.env` is gitignored and must never be committed.

Related: ADR `docs/adr/0005-global-whatsapp-webhook-router-foundation.md`;
deployment record `docs/runtime/phase-10b-dev-deployment-stabilization.md`.

## 1. Build & deploy (Docker)

Build context is the Rails app dir (`app/`), which has **no `.git`**. Pass the commit explicitly so
`/app/.git_sha` is stamped (the Dockerfile falls back to `git rev-parse`, then `"unknown"`, so the build
never fails):

```bash
cd app
GIT_SHA="$(git -C .. rev-parse HEAD)"
docker compose -p app \
  -f docker-compose.production.yaml -f docker-compose.bloomwire-production.yaml \
  build --build-arg GIT_SHA="$GIT_SHA"
docker compose -p app -f docker-compose.production.yaml -f docker-compose.bloomwire-production.yaml up -d
```

Fresh DB setup (loads schema incl. `bloomwire_whatsapp_setups` + `bloomwire_whatsapp_setup_requests`, seeds,
migrates):

```bash
docker compose -p app -f docker-compose.production.yaml -f docker-compose.bloomwire-production.yaml \
  run --rm rails bundle exec rails db:chatwoot_prepare
```

Verify provenance: `docker exec app-rails-1 cat /app/.git_sha` should print the deployed commit.
Notes: the server-local `docker-compose.bloomwire-production.yaml` overlay + `app/.env` are gitignored /
not tracked — do not commit them. Host nginx + Let's Encrypt are managed outside Docker; do not delete them.

## 2. Bloomwire config (read via `GlobalConfigService` = InstallationConfig DB → ENV)

Required for the inbound smoke (set in `app/.env` and/or `InstallationConfig`, never printed):

- Toggles ON: `BLOOMWIRE_MODE_ENABLED`, `BLOOMWIRE_PRIVACY_HARDENING`, `BLOOMWIRE_GLOBAL_WEBHOOK_ROUTER`
  (router is privacy-dependent — it stays inert unless privacy hardening is also ON),
  `BLOOMWIRE_RESTRICT_NATIVE_WHATSAPP_SETUP`.
- Secrets/config: `WHATSAPP_APP_SECRET` (signature), `BLOOMWIRE_WHATSAPP_GLOBAL_VERIFY_TOKEN` (GET handshake),
  `BLOOMWIRE_WHATSAPP_PUBLIC_CALLBACK_HOST=dev.unecast.com` (hostname only, no scheme/path).
- Mapping inputs use the **exact** Meta values: `phone_number_id`, `display_phone_number`, access token in
  `Channel::Whatsapp#provider_config` only (no new secret store). The masked last-4 is for reporting only —
  the stored value must be the full exact `phone_number_id`, or the router fails closed.

## 3. Meta dashboard webhook

- Callback URL: `https://<public-host>/bloomwire/webhooks/whatsapp` (dev: `https://dev.unecast.com/bloomwire/webhooks/whatsapp`).
- Verify token: paste the value of `BLOOMWIRE_WHATSAPP_GLOBAL_VERIFY_TOKEN` (read it locally from `app/.env`,
  do not paste it in chat). Subscribe field: `messages`.
- Expected GET behavior: valid token → **200** + challenge; wrong token → **401**; router/toggle OFF → **404**.

## 4. Verify token rotation

1. Generate a new strong token server-side (e.g. `openssl rand -hex 24`) — never print it.
2. Set it in `app/.env` and `InstallationConfig`, then `GlobalConfig.clear_cache` (effective live; persists
   across restarts via `app/.env`).
3. Re-verify locally: valid → 200 + challenge, wrong → 401, router OFF → 404 (then re-enable).
4. Confirm **0** occurrences of the token in Rails logs and **0** cleartext in nginx logs.
5. Update the Meta dashboard with the new token (manual). Note: editing only the token may not make Meta
   re-send the GET handshake — the webhook stays verified from before and inbound is unaffected (POSTs use the
   signature, not the verify token); the new token is used on Meta's next handshake.

## 5. nginx query-param log filtering

Meta sends `hub.verify_token` in the GET URL, so the webhook path must be logged **without** its query string.
Define a path-only log format in `http{}` (e.g. `/etc/nginx/conf.d/00-bloomwire-weblog.conf`):

```nginx
log_format webhook_safe '$remote_addr - - [$time_local] "$request_method $uri $server_protocol" $status $body_bytes_sent "-" "$http_user_agent"';
```

Add an exact-match location in the `dev.unecast.com` server block (same proxy settings as `location /`):

```nginx
location = /bloomwire/webhooks/whatsapp {
    access_log /var/log/nginx/access.log webhook_safe;
    proxy_pass http://127.0.0.1:3000;
    # ... same proxy_set_header Host / X-Forwarded-For / X-Forwarded-Proto / X-Real-IP + timeouts as location /
}
```

Validate + reload safely: `nginx -t` **before** `systemctl reload nginx`. Verify a GET with a dummy token is
logged path-only (the token must not appear). `hub.verify_token` / `hub.challenge` / `access_token` / `code` /
`token` / `secret` query values must not be logged in cleartext.

## 6. Readiness (must be READY before Meta steps)

Run the SuperAdmin real-hop readiness for the setup (`Bloomwire::WhatsappRealHopReadiness`). All checks must
PASS: toggles ON; `WHATSAPP_APP_SECRET` + `BLOOMWIRE_WHATSAPP_GLOBAL_VERIFY_TOKEN` configured;
`BLOOMWIRE_WHATSAPP_PUBLIC_CALLBACK_HOST` configured; setup present + `ready_for_webhook`; channel alignment
(provider `whatsapp_cloud`, phone `+<display_phone_number>`, provider_config `phone_number_id` == setup
`phone_number_id`); and `router_handoff_safe`. If anything is BLOCKED, stop and fix before configuring Meta.

The readiness page (`/super_admin/bloomwire_whatsapp_setups/:id/readiness`) includes a consolidated **Global
webhook registration readiness** panel (Phase 12F): it shows the exact callback path/URL plus the GET-verify
prerequisites (global router enabled, privacy hardening enabled, global verify token configured, app secret
configured, public callback host configured) as PASS/BLOCKED. Use it to confirm step 3 is safe to perform.
Secret values are never displayed.

## 7. Secret hygiene (non-negotiable)

- `.env` stays gitignored; never commit/stage it. Secrets live only in server-local `.env` / `InstallationConfig`
  and `Channel::Whatsapp#provider_config`. No new secret store.
- Never echo the Meta app secret, access token, verify token, DB password, or a full phone number / full
  `phone_number_id` — masked/presence only.
