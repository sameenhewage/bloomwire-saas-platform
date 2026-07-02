# Phase 17D.0 — WhatsApp Business App Coexistence Discovery

Status: **open / discovery only**

Base: `version_1` after PR #105 docs stamp (`c4ca7022902c933e34e8fb07964ae0c2dda928d3`).

## Purpose

Bloomwire Phase 17C.3 introduced the customer WhatsApp connection-choice screen:

1. **Connect Existing WhatsApp Business App** — Coexistence, currently disabled / coming soon.
2. **Register New Number** — Standard, available now.

The product decision is that Coexistence cannot remain a dead/coming-soon path forever. This discovery locks the contract before enabling it so we do not accidentally route an existing WhatsApp Business App number through the wrong backend path, leak credentials, duplicate messages, or weaken the native Chatwoot WhatsApp flow.

This phase is **evidence/report only**. It does not enable the card, add routes, store credentials, run migrations, deploy, or call Meta/WhatsApp.

## Current evidence from `version_1`

### 1. Existing Standard backend is a safe managed-signup seam

`app/app/services/bloomwire/whatsapp_embedded_signup_service.rb` is the current managed self-serve backend seam. Its comments and implementation establish these boundaries:

- It exchanges a Meta embedded-signup `code` into a managed WhatsApp inbox without touching the native `Whatsapp::EmbeddedSignupService`.
- It uses the Bloomwire global webhook router model and only calls app-to-WABA subscription.
- It never performs per-customer callback override / native per-channel webhook setup.
- It creates a `source: 'bloomwire_managed'` WhatsApp Cloud channel shell, writes the access token only through `Bloomwire::WhatsappCredentialWriter`, creates an inbox, and creates a `Bloomwire::WhatsappSetup` mapping.
- The response DTO is safe: ids/status/masked phone only; no token, `api_key`, or `provider_config`.

Important implementation references:

- `Bloomwire::WhatsappEmbeddedSignupService#perform_meta_steps`
- `Bloomwire::WhatsappEmbeddedSignupService#create_channel_shell`
- `Bloomwire::WhatsappEmbeddedSignupService#dto_for`
- `Api::V1::Accounts::Bloomwire::Whatsapp::EmbeddedSignupsController`
- route: `POST /api/v1/accounts/:account_id/bloomwire/whatsapp/embedded_signup`

### 2. Current channel metadata does not explicitly track connection mode

The Standard service currently stores the following non-secret provider config keys on the WhatsApp channel shell:

```ruby
provider_config: {
  'phone_number_id' => phone_info[:phone_number_id],
  'business_account_id' => @waba_id,
  'source' => 'bloomwire_managed'
}
```

There is no explicit `connection_mode`, `onboarding_mode`, or `coexistence` marker yet. That makes blind UI enablement risky because the system cannot distinguish:

- Standard number registration / Cloud API-only setup
- Existing WhatsApp Business App coexistence setup

### 3. Existing frontend is already using Business App onboarding hints

`useWhatsappEmbeddedSignup` already listens for both:

- `FINISH`
- `FINISH_WHATSAPP_BUSINESS_APP_ONBOARDING`

`whatsapp/utils.js` also launches Meta embedded signup with:

```js
extras: {
  setup: {},
  featureType: 'whatsapp_business_app_onboarding',
  sessionInfoVersion: '3',
}
```

This is important. The current UI labels the enabled path as **Register New Number / Standard**, but the underlying Meta SDK utility already contains Business App onboarding terminology. Therefore we must verify Meta semantics before assuming that Standard and Coexistence require completely different SDK calls.

### 4. Global webhook router is already handoff-safe

`Bloomwire::Webhooks::WhatsappController` is the global front-door. When the router feature is enabled, it verifies Meta signature, resolves a ready `Bloomwire::WhatsappSetup` by `phone_number_id`, and hands the raw payload to the existing `Webhooks::WhatsappEventsJob` only when handoff-safe.

`Bloomwire::Webhooks::WhatsappRouter` resolves by non-secret `phone_number_id` and checks that the mapped channel/inbox align with the payload before handoff. It does not store messages or duplicate payload processing.

### 5. `smb_message_echoes` is already partially handled in the stock job

`Webhooks::WhatsappEventsJob` already detects the `smb_message_echoes` field and routes it to:

```ruby
Whatsapp::IncomingMessageWhatsappCloudService.new(
  inbox: channel.inbox,
  params: params,
  outgoing_echo: true
).perform
```

The job also uses echo-specific contact locking semantics because echo payloads reverse the contact direction: `from` is the business number and `to` is the customer.

This means outbound messages sent from the WhatsApp Business App may already have a processing path. Phase 17D.1 must verify this path with focused tests before adding new processing.

### 6. `smb_app_state_sync` support is not yet proven

The docs from WhatsWay describe Coexistence as requiring both:

- `smb_message_echoes`
- `smb_app_state_sync`

Current evidence proves an echo path exists, but this discovery has **not yet proven** an app-state-sync/contact-sync path. We should not claim Coexistence is complete until app-state-sync behavior is inspected and tested.

## Main contract decision

Do **not** enable the Coexistence card by calling the Standard endpoint blindly.

The next implementation should make connection mode explicit. Two viable designs:

### Option A — Same endpoint, explicit mode

```text
POST /api/v1/accounts/:account_id/bloomwire/whatsapp/embedded_signup
```

Payload includes:

```json
{
  "mode": "standard" | "coexistence"
}
```

Pros: smaller routing/API surface.

Cons: easier to accidentally mix Standard and Coexistence behavior inside one service.

### Option B — Separate endpoint / service for Coexistence

```text
POST /api/v1/accounts/:account_id/bloomwire/whatsapp/coexistence_embedded_signup
```

Pros: review-safe boundary; impossible for the UI to accidentally send Coexistence through Standard path; clearer tests and failure messages.

Cons: one additional controller/service route.

**Recommendation:** Option B.

## Proposed implementation slices

### Phase 17D.1 — Coexistence backend contract

Backend-only, test-first.

Expected behavior:

- Add a dedicated account-scoped Coexistence endpoint or a clearly separated service boundary.
- Admin-only; agent denied.
- Same managed-mode gate as Standard, plus an explicit Coexistence capability/feature if needed.
- Fail closed before token storage if platform config or encryption is not ready.
- Accept only non-secret Meta signup credentials plus an explicit mode/flow marker.
- Store token only through `Bloomwire::WhatsappCredentialWriter`.
- Store non-secret routing identifiers in `Bloomwire::WhatsappSetup`.
- Store an explicit non-secret channel/provider marker such as `connection_mode: 'coexistence'` or equivalent.
- Subscribe WABA to the global webhook only; no per-channel callback override.
- Return safe DTO only; no token / `api_key` / `provider_config` / raw Meta payload.
- No real Meta/WhatsApp calls in tests.

### Phase 17D.2 — Coexistence webhook proof

Webhook/test slice before full UI enablement.

Expected checks:

- `smb_message_echoes` payload routes through the global router to the mapped channel.
- Echo payload creates/syncs an outgoing message without duplication.
- Echo payload does not expose PII in logs beyond existing redaction policy.
- `smb_app_state_sync` behavior is explicitly inspected and either supported or parked behind a documented blocker.
- If app-state-sync is unsupported, Coexistence must not be marked fully ready.

### Phase 17D.3 — Frontend enablement

Only after backend/webhook proof.

Expected behavior:

- Coexistence card becomes enabled only when backend capability says it is supported.
- Shows requirements screen before Meta flow.
- Button label: **Connect with Meta** / **Connect Existing WhatsApp Business App**.
- The Coexistence path calls the dedicated Coexistence endpoint, not the Standard endpoint.
- No manual credential fields.
- No Add Agents step.
- Errors are sanitized.
- Success screen shows safe DTO and readiness.

## Guardrails for all 17D work

- No production deploy.
- No dev deploy unless separately approved.
- No real Meta/WhatsApp calls in automated tests.
- No migration unless a later implementation slice proves it is required.
- No secrets printed, logged, returned, or written to docs.
- No native `/whatsapp/authorization` carve-out.
- No native `Whatsapp.vue` weakening.
- No duplicate chat/message source of truth.
- Chatwoot remains the account/inbox/contact/conversation/message source of truth.

## Open questions before 17D.1

1. Does the current Meta embedded signup config already cover both Standard and Coexistence, or should Bloomwire maintain two Meta configuration IDs?
2. Does the current `featureType: 'whatsapp_business_app_onboarding'` mean the current enabled Standard flow is already Business App onboarding, or is it simply Meta's current embedded-signup session format?
3. Which exact webhook fields must the global Meta App subscribe to for Coexistence beyond `messages` and `message_template_status_update`?
4. Is `smb_app_state_sync` needed for go-live, or can Coexistence first ship with message echoes only and a documented limitation?
5. Should connection mode live only in `Channel::Whatsapp#provider_config`, or should `Bloomwire::WhatsappSetup` also expose a non-secret mode for SuperAdmin observability?

## Current recommendation

Start 17D.1 as **backend contract + tests**, not UI enablement. The UI card should remain disabled until backend and webhook proof are complete.

The safest implementation plan is:

```text
17D.1 backend contract → 17D.2 webhook proof → 17D.3 frontend enablement → dev deploy/runtime verification
```
