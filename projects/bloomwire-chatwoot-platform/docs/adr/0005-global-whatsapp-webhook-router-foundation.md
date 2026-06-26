# ADR-0005 — Global Meta WhatsApp Webhook Router (foundation)

- Status: Accepted (implemented; feature-gated OFF by default)
- Extends: ADR-0001 / ADR-0002 / ADR-0003 / ADR-0004 (never overrides)
- Scope: routing foundation + GET verification (registration **readiness**) only. **No** Meta registration API
  call / real Meta E2E, onboarding wizard, routing registry, outgoing gateway, AI bot, analytics, new secret
  columns, or new message/conversation/contact storage.

## Context

Bloomwire-managed WhatsApp numbers should be received at a single Bloomwire-controlled endpoint and routed to
the right tenant inbox using the PR #35 `Bloomwire::WhatsappSetup` mapping, **reusing** Chatwoot's existing
WhatsApp processing path (no duplication).

## Decision

### Endpoint + gate
`POST /bloomwire/webhooks/whatsapp` → `Bloomwire::Webhooks::WhatsappController#process_payload`, gated by
`Bloomwire::Features.enabled?(:global_webhook_router)` (master ON + privacy ON + toggle ON — the feature is
privacy-dependent). With the feature OFF the endpoint is inert (`head :not_found`); stock Chatwoot is untouched.

### Route key
`phone_number_id` (from `entry[0].changes[0].value.metadata.phone_number_id`) is the **primary** lookup key —
it's per-number unique at Meta and the mapping stores it with a partial-unique index. `waba_id` (`entry[0].id`)
is non-unique (one WABA → many numbers) and is **not** used as the key.

### Resolution (fail-closed) — `Bloomwire::Webhooks::WhatsappRouter`
Resolve a single `Bloomwire::WhatsappSetup.ready_for_webhook` by `phone_number_id`. Return nil (do **not**
route) when: phone_number_id blank, no match, status not `ready_for_webhook`, more than one match (defensive;
the partial-unique index prevents it), or the row is missing `inbox_id`/`channel_whatsapp_id`.

### Handoff (channel-alignment enforced — PR #36 review fix)
Forwarding the raw payload to `Webhooks::WhatsappEventsJob` is safe **only if** that job will re-resolve to the
*same* mapped channel. The job resolves by `Channel::Whatsapp.find_by(phone_number: "+<display_phone_number>")`
and accepts it only when `provider_config['phone_number_id']` equals the payload's `phone_number_id`. So
`resolve_handoff_safe_setup(payload)` returns a setup **only when** all hold (else nil, fail-closed):
- payload `phone_number_id` == `setup.phone_number_id` (from `resolve`),
- `setup.channel_whatsapp` and `setup.inbox` exist and `channel.inbox.id == setup.inbox_id`,
- `channel.provider_config['phone_number_id']` == payload `phone_number_id`,
- `channel.phone_number` == `"+<display_phone_number>"` (mirrors `get_channel_from_wb_payload`).

Only then is the **raw payload** forwarded to the existing `Webhooks::WhatsappEventsJob` (stock processing path:
it re-resolves to the mapped channel and runs the existing contact/conversation/message creation). The router is
a **routing gate**, not a new processor: no new message/conversation/contact tables.

### Auth + privacy
- Meta signature is verified on **POST only** (`before_action :verify_meta_signature!, only: :process_payload`,
  reuse `MetaTokenVerifyConcern`, HMAC-SHA256 of the raw body vs the global `WHATSAPP_APP_SECRET`); invalid
  signature ⇒ 401.
- Always returns `head :ok` to Meta when authorized (no retry storms); the routing decision is fail-closed.
- The router logs **only** a redacted, masked `phone_number_id` tail and never the payload, message content,
  tokens, or secrets. It never reads `provider_config` secrets.

### GET verification (registration readiness — added slice)
`GET /bloomwire/webhooks/whatsapp` → `Bloomwire::Webhooks::WhatsappController#verify` serves Meta's
webhook-callback verification handshake so the global endpoint can be registered as a Meta callback URL.
- **Same gate**: `ensure_router_enabled` applies to GET too — feature OFF ⇒ `head :not_found` (inert, no param
  echo); native `webhooks/whatsapp/:phone_number` GET/POST untouched.
- **Global verify token, not per-customer**: the global front-door has no `:phone_number` in the URL (unlike
  the native per-channel `valid_token?`), so it validates one InstallationConfig key
  **`BLOOMWIRE_WHATSAPP_GLOBAL_VERIFY_TOKEN`** (read via `GlobalConfigService`), constant-time compare. Valid ⇒
  echo `hub.challenge`; missing config or wrong/absent token ⇒ **fail closed** (401). **Not** `WHATSAPP_APP_SECRET`
  (that stays dedicated to POST signature).
- **No signature, no `phone_number_id`, no mapping, no enqueue**: verification never enters resolution or the
  processing job; the verify token itself is never logged.
- **Secret hygiene**: the verify token is added to `Bloomwire::Features::MASKED_SECRET_KEYS`, so the existing
  Phase 2A seam masks it (password input, no cleartext on index/show/edit) and never wipes it on a blank submit
  on SuperAdmin surfaces while privacy hardening is ON. It is not exposed on any tenant/business surface.
- **Registration-ready only**: this makes the endpoint registrable; it does **not** call the Meta registration
  API or perform real Meta E2E.

## Alternatives considered
- **Call `IncomingMessageWhatsappCloudService` directly with the mapping's inbox** — rejected: skips the job's
  mutex/echo/inactive handling and duplicates job logic. Forwarding to the job reuses the whole path.
- **Key on `waba_id`** — rejected: not unique per number.

## Consequences
- One global endpoint can front Bloomwire-managed numbers; the mapping is the routing gate, the existing job
  is the executor. OFF ⇒ stock. No secret/message duplication.

## Deferred (follow-ups, out of this slice)
- **Meta webhook registration API call + real Meta E2E** for the global endpoint. GET verification (above) makes
  the endpoint *registration-ready*; the actual Meta App webhook-subscription call and live send/receive remain
  deferred (tied to managed onboarding) and require a separate approval.
- Inbound message content currently still appears in Rails' framework `Parameters:` request log (identical to
  the native `webhooks/whatsapp` controller; governed by the global `config.filter_parameters`, which already
  redacts secret/key/access keys). A global logging-policy decision to suppress message bodies is a separate item.

## Evidence (this slice)
- Tests: resolver spec (14) + controller request spec (10) = 24, all green; regression (PR #35 + Phase 1/2A/2B/2C
  + native webhook controller/events job) green (118 total). RuboCop: no offenses. No migration / no new tables.
- Runtime (dev, curl): OFF ⇒ 404; ON + valid signature + matching `phone_number_id` ⇒ 200 (handoff enqueued);
  ON + unknown ⇒ 200 fail-closed (redacted diagnostic `****`); invalid signature ⇒ 401; resolver resolves the
  correct setup live and returns nil for unknown; signing secret + api_key absent from logs.

## Evidence (GET verification slice)
- TDD red→green: 9 failures before implementation (no GET route ⇒ diagnostic 404 echoed the `hub.challenge`
  param; masking key absent) → GET verify request spec (12) + Features masking unit (3 new) green. Regression
  green: 154 examples / 0 failures (new GET verify + PR #36 router POST + PR #35 setup model/controller +
  Phase 1/2A/2B/2C + native `webhooks/whatsapp` controller + `WhatsappEventsJob`). RuboCop: no offenses.
  No migration / no new tables / no new secret columns.
- Runtime: 22/22 in-process integration drive over the real dev stack + live `curl` on the dev server —
  OFF ⇒ GET 404 (empty body, `hub.challenge` not echoed), POST 404, native routes unchanged; ON ⇒ valid token
  echoes `hub.challenge`, invalid/absent token ⇒ 401, missing token config ⇒ 401 (fail closed); GET never
  enqueues `Webhooks::WhatsappEventsJob` and needs no `phone_number_id`/`Bloomwire::WhatsappSetup`; verify token,
  `WHATSAPP_APP_SECRET`, message body, and full unknown `phone_number_id` all absent from logs.

## Real-hop readiness console (Phase 10A.1)

A SuperAdmin/Ops-only, read-only console answers "is a real Meta inbound test ready or blocked, and what is
missing?" — **without calling Meta** and **without ever rendering secret values**.

- **Service** `Bloomwire::WhatsappRealHopReadiness` (PORO, no DB writes): given a `Bloomwire::WhatsappSetup`
  it returns `{ status: ready|blocked, ready_for_inbound_mapping, ready_for_get_verification_config,
  checks: [{ key, group, status, message }], callback_path, callback_url, masked: {…} }`. Secret checks report
  only **configured/missing** (never the value); phone identifiers are **masked** (`****`-tail).
- **Checks (grouped):** feature toggles (`BLOOMWIRE_MODE_ENABLED` / `…PRIVACY_HARDENING` / `…GLOBAL_WEBHOOK_ROUTER`),
  secrets/config (`WHATSAPP_APP_SECRET`, `BLOOMWIRE_WHATSAPP_GLOBAL_VERIFY_TOKEN` configured), setup mapping
  (present / `ready_for_webhook` / phone_number_id / account / inbox / channel + the three consistency rules),
  channel alignment (`whatsapp_cloud` provider / phone_number / `provider_config.phone_number_id` match /
  `WhatsappRouter.resolve_handoff_safe_setup` would pass for a sample aligned payload), and callback URL.
- **Surface:** member action `readiness` on `SuperAdmin::BloomwireWhatsappSetupsController`
  (`/super_admin/bloomwire_whatsapp_setups/:id/readiness`), gated by `authenticate_super_admin!` +
  `ensure_bloomwire_mode_enabled` (OFF ⇒ stock). The page shows the overall verdict, the grouped checklist, the
  copyable callback path, a masked next-steps runbook, and warnings (no real Meta E2E performed; never paste
  secrets; real test stays blocked until external Meta assets exist).
- **Config:** one **non-secret** `InstallationConfig` `BLOOMWIRE_WHATSAPP_PUBLIC_CALLBACK_HOST` (hostname only,
  not masked, not a secret) lets Ops record the staging/tunnel host so the full callback URL can be displayed.
  No new tables, no new secret columns, no duplicate secret storage.

### External assets required for the real hop (none are stored in git)
- A Meta test **WABA** + its **`phone_number_id`** and **`display_phone_number`**.
- Meta Developer **dashboard access** (to set the callback URL and run GET verification).
- A **physical test phone** to send one inbound message.
- A **public HTTPS callback URL** (staging or tunnel) → record its host in `BLOOMWIRE_WHATSAPP_PUBLIC_CALLBACK_HOST`.
- The real `WHATSAPP_APP_SECRET` and a chosen `BLOOMWIRE_WHATSAPP_GLOBAL_VERIFY_TOKEN` (set in env/config only).

### Evidence (Phase 10A.1)
- TDD red→green: service spec (17) + SuperAdmin request spec (12) = 29 green. Regression: 183 examples / 0
  failures (new + PR #35/#36/#37 + Phase 1/2A/2B/2C + native `webhooks/whatsapp` controller + `WhatsappEventsJob`).
  RuboCop: no offenses. No migration / no new tables / no new secret columns.
- Runtime (dev, real stack): 18/18 — unauthenticated + business/agent users redirected to super_admin sign in;
  SuperAdmin sees BLOCKED (missing config) → READY (fake aligned config) → BLOCKED again on a
  `provider_config.phone_number_id` mismatch (exact reason shown); the page never renders the app secret, verify
  token, provider api_key, or full phone identifiers; logs contain none of those; the service makes no outbound
  HTTP / Meta call; live `curl` confirms the route is wired and auth-gated (302 → `/super_admin/sign_in`).
