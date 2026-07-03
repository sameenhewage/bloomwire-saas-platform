# Phase 17D.2 — WhatsApp Business App Coexistence Webhook Proof

Status: **MERGED via PR #109 at `4a57564d7c1fbc54aeafbf9049f61b5b7a8b0795`** (approved head
`fbbbe14f06d6f49e5ff629b34788fd347718caf9`; `version_1` tip `4a57564`). Backend/webhook proof only — **no frontend
enablement**; the Coexistence card in `BloomwireWhatsapp.vue` remains **disabled / "Coming soon"** until Phase
17D.3. No deploy · no production · no migrations · dev remains `9b09f9e`.

Base: `version_1` @ `5002942a381ccd95dfd550afc4db4e6346c1493f`.

## Purpose

Before enabling the "Connect Existing WhatsApp Business App" (Coexistence) card, prove that the **existing**
Bloomwire global webhook router (ADR-0005) and the **existing** stock `Webhooks::WhatsappEventsJob` can safely
handle coexistence webhook traffic — routing, `smb_message_echoes`, and `smb_app_state_sync` — **without**
duplicating messages, leaking secrets, weakening the native flow, or adding app-side chat storage.

A coexistence-created channel (Phase 17D.1) is a normal `whatsapp_cloud` channel whose `provider_config` carries
`source = bloomwire_managed` and `connection_mode = coexistence`. It is created via the same safe seam as Standard
(token only in encrypted `provider_config`; non-secret `Bloomwire::WhatsappSetup` routing row).

## What was proven

### 1. Global router routing — SAFE (no change needed)

`Bloomwire::Webhooks::WhatsappRouter` keys resolution **only** on the payload's `metadata.phone_number_id` plus
channel alignment (`channel.phone_number == "+<display>"`, `provider_config['phone_number_id']` match, inbox
match). It **never inspects `connection_mode`**, so a coexistence channel resolves exactly like a Standard one.

Proven in `spec/services/bloomwire/webhooks/whatsapp_router_spec.rb` (`coexistence routing` context):
- A coexistence channel resolves via `resolve_handoff_safe_setup` by its `phone_number_id`.
- An `smb_message_echoes` payload resolves the same way (router reads `metadata`, present on every field type).
- A wrong `phone_number_id` does **not** route (fail-closed `nil`).
- Routing is **account-scoped**: each payload resolves only to its own account's mapping, never another account's
  (the partial-unique index on `phone_number_id` for `ready_for_webhook` guarantees a single owner).

### 2. `smb_message_echoes` — SAFE, uses the existing OUTGOING echo path (no change needed)

The stock `Webhooks::WhatsappEventsJob` already detects `field == 'smb_message_echoes'` (`message_echo_event?`)
and routes it to `Whatsapp::IncomingMessageWhatsappCloudService.new(inbox:, params:, outgoing_echo: true)` — the
**outgoing** echo path. An echo (a reply the business sent from the WhatsApp Business App) is therefore recorded
as an outgoing message, **not** a duplicate inbound customer message.

Proven in `spec/jobs/webhooks/whatsapp_events_job_spec.rb` (coexistence context):
- An `smb_message_echoes` payload for a coexistence channel calls `IncomingMessageWhatsappCloudService` with
  `outgoing_echo: true` (never the inbound path).
- No secrets / raw payloads are logged; the flow stays account/inbox-scoped (uses `channel.inbox`).

### 3. `smb_app_state_sync` — was unhandled → now SAFELY IGNORED (minimal change)

Current behavior (RED): `smb_app_state_sync` was **not** special-cased, so it fell through to
`handle_message_events` → `IncomingMessageWhatsappCloudService` (inbound processing). It created no message (no
`messages` array), but it **did** invoke inbound processing, which is not appropriate for a state-sync event.

Minimal safe change (GREEN) in `app/app/jobs/webhooks/whatsapp_events_job.rb`:
- `process_events` now returns early via `handle_app_state_sync` when `field == 'smb_app_state_sync'`.
- `handle_app_state_sync` logs a single **redacted, content-free** line and returns — no inbound processing, no
  message/conversation creation, no crash.

Proven in `spec/jobs/webhooks/whatsapp_events_job_spec.rb` (coexistence context):
- An `smb_app_state_sync` payload does **not** call `IncomingMessageWhatsappCloudService` or
  `IncomingMessageService`, and does not raise.
- It creates **no** `Message` and **no** `Conversation`.

### 4. No duplicate storage

No app-side chat/message tables were added; no Agno/session/chat-history duplication. The proof relies entirely on
the existing Chatwoot webhook-processing path (`IncomingMessageWhatsappCloudService` for the outgoing echo path,
and a no-op ignore for state-sync).

## Code change in this phase

- `app/app/jobs/webhooks/whatsapp_events_job.rb` — added the `smb_app_state_sync` safe-ignore guard
  (`app_state_sync_event?` + `handle_app_state_sync`). Echo + inbound behavior are unchanged.

That is the **only** production code change. Routing and echo handling required no code change (already safe).

## Tests

- `spec/services/bloomwire/webhooks/whatsapp_router_spec.rb` — coexistence routing context (4 examples).
- `spec/jobs/webhooks/whatsapp_events_job_spec.rb` — coexistence context (echo outgoing; app_state_sync
  safe-ignore; no message/conversation) (3 examples).
- `spec/support/bloomwire_whatsapp_e2e_helpers.rb` — added `bw_echo_payload` + `bw_app_state_sync_payload`
  (fake, non-secret).

Targeted run: `DISABLE_ENTERPRISE=true bundle exec rspec spec/services/bloomwire/webhooks/whatsapp_router_spec.rb
spec/jobs/webhooks/whatsapp_events_job_spec.rb` → **43 examples, 0 failures**. Broader webhook regression (router,
job, PII logging, request logging, inbound e2e) → **58 examples, 0 failures**. RuboCop clean.

## Boundaries / hard rules honored

- **No frontend enablement** — `BloomwireWhatsapp.vue` untouched; Coexistence card stays disabled until 17D.3.
- **No native `/whatsapp/authorization` change**; no per-channel webhook override, no `channel.setup_webhooks`,
  no `override_waba_callback`, no `subscribe_waba_webhook`.
- **No migration / schema change · no deploy · no production · no real Meta/WhatsApp calls** (all payloads fake,
  no HTTP). **No secrets** logged or stored. **No app-side duplicate chat storage.**

## Next

- **17D.3** — frontend enablement (flip the Coexistence card live against the 17D.1 endpoint).
