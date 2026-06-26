# ADR-0005 — Global Meta WhatsApp Webhook Router (foundation)

- Status: Accepted (implemented; feature-gated OFF by default)
- Extends: ADR-0001 / ADR-0002 / ADR-0003 / ADR-0004 (never overrides)
- Scope: routing foundation only. **No** Meta registration/E2E, onboarding wizard, routing registry,
  outgoing gateway, AI bot, analytics, or new message/conversation/contact storage.

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
- Meta signature is verified (reuse `MetaTokenVerifyConcern`, HMAC-SHA256 of the raw body vs the global
  `WHATSAPP_APP_SECRET`); invalid signature ⇒ 401.
- Always returns `head :ok` to Meta when authorized (no retry storms); the routing decision is fail-closed.
- The router logs **only** a redacted, masked `phone_number_id` tail and never the payload, message content,
  tokens, or secrets. It never reads `provider_config` secrets.

## Alternatives considered
- **Call `IncomingMessageWhatsappCloudService` directly with the mapping's inbox** — rejected: skips the job's
  mutex/echo/inactive handling and duplicates job logic. Forwarding to the job reuses the whole path.
- **Key on `waba_id`** — rejected: not unique per number.

## Consequences
- One global endpoint can front Bloomwire-managed numbers; the mapping is the routing gate, the existing job
  is the executor. OFF ⇒ stock. No secret/message duplication.

## Deferred (follow-ups, out of this slice)
- **GET verification + Meta webhook registration** for the global endpoint (needs a global verify-token,
  tied to managed onboarding) — required before any real Meta E2E.
- Inbound message content currently still appears in Rails' framework `Parameters:` request log (identical to
  the native `webhooks/whatsapp` controller; governed by the global `config.filter_parameters`, which already
  redacts secret/key/access keys). A global logging-policy decision to suppress message bodies is a separate item.

## Evidence (this slice)
- Tests: resolver spec (14) + controller request spec (10) = 24, all green; regression (PR #35 + Phase 1/2A/2B/2C
  + native webhook controller/events job) green (118 total). RuboCop: no offenses. No migration / no new tables.
- Runtime (dev, curl): OFF ⇒ 404; ON + valid signature + matching `phone_number_id` ⇒ 200 (handoff enqueued);
  ON + unknown ⇒ 200 fail-closed (redacted diagnostic `****`); invalid signature ⇒ 401; resolver resolves the
  correct setup live and returns nil for unknown; signing secret + api_key absent from logs.
