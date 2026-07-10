# ADR-0010 — WhatsApp Onboarding Resilience (synchronous fallback + asynchronous Standard flow)

- Status: **Accepted; merged and DEV safe-runtime validated.** The immediate synchronous hardening remains the
  protected fallback. The v3 asynchronous Sidekiq workflow is deployed for **Standard “Register New Number” only**;
  Coexistence remains on its existing synchronous flow and is never controlled by the Standard emergency switch.
- Extends: ADR-0004 (`Bloomwire::WhatsappSetup` mapping — unchanged), ADR-0005 (global webhook router — unchanged),
  ADR-0006 (provider secret at rest — unchanged), ADR-0008 (onboarding responsibility pivot — unchanged),
  ADR-0009 (multi-inbox model + global uniqueness keys — unchanged).
- Supersedes: nothing.

## Context

Before v3, Standard and Coexistence WhatsApp Embedded Signup ran **all** Meta Graph steps **and** the DB writes
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

### B. Asynchronous Standard workflow (Accepted — merged and DEV-deployed)

Move the Standard flow’s Meta side effects OFF the web request into a resumable **Sidekiq onboarding workflow**:

- The admin/account-scoped controller records an encrypted onboarding attempt and returns **202 Processing**. Creating
  a new attempt requires managed onboarding plus the Standard async path. Submitting or polling an already-created
  account-scoped attempt requires the base managed feature only, so a switch flip cannot orphan a waiting/in-flight run.
- Submission is row-locked and replay-safe: the first valid `waiting_meta` submit persists credentials and advances one
  generation; a replay re-enqueues that persisted generation without overwriting it; non-submittable states fail safely.
- Sidekiq receives exactly the non-secret `[attempt_id, submission_generation]` arguments. A stale generation no-ops at
  job entry and at the processor's authoritative lease claim. Recovery/TTL work does not depend on the emergency switch.
- A leased Sidekiq processor reconciles real Meta state before mutation and advances idempotently through token,
  registration, capability, subscription, and persistence.
- The authenticated account payload exposes `canUseAsyncStandardWhatsappOnboarding`. The existing managed entry
  always keeps its Standard/Coexistence chooser: Standard selects async when the capability is true and the protected
  synchronous fallback when false; Coexistence always uses its existing flow.
- A persisted account-scoped Standard attempt resumes the async poller even if the emergency switch later changes.
  An explicit server `expired` status means Meta-session expiry. A generic poll 404 means `attempt_not_found`, clears
  stale local storage, and offers **Check status / Restart**; it never selects sync or claims Meta expiry.

The emergency switch is a rollback control for **new Standard async attempt creation only**. An attempt created before
it flips remains submittable and pollable; workers/recovery remain switch-independent. The switch does not hide
Coexistence or stop in-flight attempts.

## Consequences

- **Positive:** no more split-state 500s on a slow `/register`; each Meta call is individually bounded; retries
  converge to exactly one set of records; the global request budget is untouched for all other traffic; timeout
  errors are secret-free.
- **Trade-offs:** the synchronous 75s endpoint budget remains while the rollback fallback exists. Async Standard adds
  an encrypted attempt lifecycle, leases, recovery, TTL sweeping, a job, polling, and operator-visible failure states.
- **Compatibility:** Feature OFF remains stock/inert. Coexistence, native WhatsApp, global routing, existing records,
  and the conversation/message/contact sources of truth are unchanged.

## Validation

- New/updated synchronous-hardening specs (all Meta stubbed, WebMock-blocked, no real Graph calls): Graph timeout →
  sanitized `GraphApiTimeoutError`; middleware budget/bypass/passthrough; register-read-timeout recovery;
  CONNECTED/subscribed retry skips; repeated retries = exactly one Channel/Inbox/Setup; Meta timeout leaves zero
  records. Exact-SHA review found the assigned-user task POST still bypassed the helper; RED proved it and the write
  now uses the same helper. Final hardening matrix **123/0**; full RuboCop **2742/0**; docs/diff/secret gates passed.
- Post-rebase backend async/client suite: **202 examples, 0 failures, 5 expected no-key pending**; no-key
  fail-closed suite **49/0 (14 expected encryption-only pending)**; shared backend **72/0**. Frontend affected suite:
  **145 tests, 0 failures**. `pnpm eslint`: **0 errors, 371 existing repository warnings**. Full RuboCop **2759/0**.
- The isolated merged-`version_1` upgrade audit passed baseline→apply→rollback→reapply with **29 columns / 7 indexes /
  3 FKs / 2 checks**, then removed the audit database with zero residue.
- Async tests cover explicit Standard routing, chooser/Coexistence preservation, feature OFF, rollback-safe polling,
  server-expired versus HTTP-404 semantics, recoverable Check status/Restart, safe DTOs, account scope, and admin
  authorization. Exact-SHA review additionally proved a stale in-flight poll could overwrite cancelled/restarted
  state; a monotonic flow generation now invalidates stale create/popup/submit/poll continuations.
- Delivery: PR **#153** exact-reviewed head `91e1f3c`, CI **8/8**, merged as `bc6602d`; DEV deploy run
  **29071915838** succeeded with migrations + smoke. Rails/Sidekiq exact SHA, local/public health 200, migration
  catalog **29/7/3/2**, encryption ready, no pending migrations, queues **0/0/49 historical**, recent errors 0.
- Authenticated safe runtime validated chooser ownership, default async routing, safe create/show/404 DTOs,
  switch-blocked new create with pre-flip submit/poll continuity, switch-independent worker/recovery, safe terminal
  copy + Restart fallback, stopped 3s polling with no duplicate burst, and restoration to record-absent/OFF. Three
  unbound test attempts were deleted; zero remain.
- The sole protected managed Channel/Setup/Inbox stayed ready and encrypted; its existing read path stayed present.
  No live Meta/WhatsApp call, message send, provider-credential mutation, Enterprise change, production change, or
  protected-row mutation occurred. Original Postgres/Redis volumes were reused; no data volume was recreated.
- Residual: a real successful new-number Meta signup was intentionally not run. Keep the synchronous fallback and
  its 75s middleware until that later provider certification. Legacy clean-install debt remains issue **#151**.
