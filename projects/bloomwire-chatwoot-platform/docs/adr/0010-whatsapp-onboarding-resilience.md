# ADR-0010 — WhatsApp Onboarding Resilience (timeout + idempotency; sync now, async later)

- Status: **Accepted** for the **immediate synchronous hardening** (Phase: onboarding resilience). The **asynchronous
  Sidekiq onboarding workflow** is **Proposed** (durable design) and deferred to a controlled post-demo phase.
- Extends: ADR-0004 (`Bloomwire::WhatsappSetup` mapping — unchanged), ADR-0005 (global webhook router — unchanged),
  ADR-0006 (provider secret at rest — unchanged), ADR-0008 (onboarding responsibility pivot — unchanged),
  ADR-0009 (multi-inbox model + global uniqueness keys — unchanged).
- Supersedes: nothing.

## Context

The Standard/Coexistence WhatsApp Embedded Signup runs **all** Meta Graph steps **and** the DB writes
**synchronously inside one web request**: code exchange → long-lived token → phone info → `/register` (only when
not already CONNECTED) → status re-check → resolve target → outbound-capability check → subscribe app→WABA + verify
→ persist `Channel::Whatsapp` + `Inbox` + `Bloomwire::WhatsappSetup`.

That request is bounded by the **global 15s `Rack::Timeout`**, and the Graph client (`Whatsapp::FacebookApiClient`)
made **bare `HTTParty` calls with no HTTP timeouts**. On a real DEV onboarding (2026-07-09) this produced a
**split state**:

- Bloomwire POSTed `/{phone_number_id}/register` to Meta.
- Meta processed it and moved the number to **CONNECTED**.
- The Rails request exceeded the **15s** `Rack::Timeout` **during** `/register`; the browser got **500**.
- Bloomwire persisted **0** records (it fails closed before any DB write on a Meta error).

So Meta and Bloomwire diverged: number CONNECTED on Meta, **no** Inbox/Channel/Setup in Bloomwire. A second attempt
only succeeded because it found the number already CONNECTED (skipped `/register`) and finished in ~11s. Disabling
the DEV token-debug logging reduced latency but is **not** a reliability fix — a genuinely slow cold-path
`/register` could still exceed 15s.

## Decision

### A. Immediate synchronous hardening (Accepted — implemented)

1. **Per-call Graph HTTP timeouts.** Every `Whatsapp::FacebookApiClient` request goes through one `http_request`
   helper that injects `open_timeout: 5s` + `read_timeout: 25s` and raises a **sanitized**
   `Whatsapp::GraphApiTimeoutError` (HTTP verb + timeout class only — never url/query/token/App Secret/PIN/OAuth
   code/response body) on a connection or read timeout. No single Meta call can hang the request.

2. **Endpoint-specific request timeout.** A dedicated `Bloomwire::OnboardingRequestTimeout` gives ONLY the two
   onboarding POST endpoints a bounded **75s** ceiling and marks the request so a prepend on `Rack::Timeout`
   (`RackTimeoutBypass`) lets that single request skip the global timer. **The global `Rack::Timeout` default is
   unchanged — every other request still gets 15s.** (75s comfortably covers the sequential Meta calls even when
   `/register` actually runs, while still being a finite ceiling.)

3. **Idempotent / resumable onboarding** (mostly already present via Phase 4 + Phase 6; one gap closed here):
   - **Skip `/register` when the number is already CONNECTED** (`ensure_registered`) — a retry after a
     register-then-timeout resumes from Meta's CONNECTED state; a register **read** timeout inside the same request
     is caught and the re-checked status drives the flow.
   - **Skip the subscribe POST when the app is already in the WABA `subscribed_apps`** (`subscribe_final_waba` now
     pre-checks `subscribed_to_waba?`) — new in this ADR.
   - **Reuse existing records** (`reconnect_same_account_number`, keyed by `account_id` + `phone_number_id`): a
     re-onboard of the same number by the same account refreshes the SAME Channel/Inbox/Setup.
   - **Resume from real Meta state**: every attempt re-reads phone status / subscription from Meta.

4. **Persistence protected by DB uniqueness + a transaction** (no new migration needed — the constraints already
   exist): `channel_whatsapp.phone_number` UNIQUE; `bloomwire_whatsapp_setups.phone_number_id` UNIQUE (partial) and
   `channel_whatsapp_id` UNIQUE; writes run in one `ActiveRecord::Base.transaction` with a `RecordNotUnique` guard.
   These GUARANTEE **exactly one** Inbox/Channel/Setup even under repeated or concurrent retries (a losing concurrent
   attempt fails closed with `:phone_number_taken` rather than duplicating).

### B. Durable design (Proposed — deferred)

Move the Meta side effects OFF the web request into an **asynchronous Sidekiq onboarding workflow**:

- The controller validates + records an **onboarding attempt** and returns **202 Processing** with an attempt id.
- A Sidekiq job runs the resumable state machine `pending → meta_registered → subscribed → capable → ready`, each
  transition **idempotent** and keyed by `phone_number_id`, safe to retry from the real Meta state (register only if
  not CONNECTED; subscribe only if not already subscribed; persist reusing existing records).
- The frontend **polls** the attempt status (the Phase 6 watchdog/polling UI already exists) and shows
  ready / action-required / a sanitized failure with manual retry.

This removes the request-timeout coupling entirely and makes onboarding fully crash/deploy-safe. It is deferred so
the **currently working, demo-proven** synchronous flow is not changed before the company demo.

## Consequences

- **Positive:** no more split-state 500s on a slow `/register`; each Meta call is individually bounded; retries
  converge to exactly one set of records; the global request budget is untouched for all other traffic; timeout
  errors are secret-free.
- **Trade-offs:** the 75s ceiling uses the same `Timeout` mechanism `Rack::Timeout` uses (a known Ruby caveat) — it
  is a backstop; the primary protection is the per-call Graph timeouts + idempotency. The endpoint ceiling is active
  wherever `Rack::Timeout` is (production/DEV); if `Rack::Timeout` were removed, the per-call Graph timeouts still
  bound the request.
- **Follow-up:** `PARK-ENG-ONBOARD-RESUMABLE` in `../parked-items.md` tracks the async Sidekiq workflow (Section B).

## Validation

- New/updated specs (all Meta stubbed, WebMock-blocked, no real Graph calls): Graph timeout → sanitized
  `GraphApiTimeoutError`; middleware (onboarding budget + bypass + non-onboarding passthrough); in-request
  register-read-timeout recovery; retry-sees-CONNECTED-skips-register; retry-sees-subscribed-skips-subscribe;
  repeated retries = exactly one Channel/Inbox/Setup; Meta timeout fails safely (0 records); secrets never in the
  DTO. Exact-SHA review found the assigned-user task POST still bypassed the helper; a RED timeout-options contract
  proved it and the write now uses the same helper. Final hardening matrix **123/0**; full RuboCop **2742/0**; docs,
  diff, and secret gates passed. **Not merged or deployed.**
