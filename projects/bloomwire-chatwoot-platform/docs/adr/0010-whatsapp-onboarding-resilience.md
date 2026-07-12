# ADR-0010 — WhatsApp Onboarding Resilience (synchronous fallback + asynchronous Standard flow)

- Status: **Accepted; merged and DEV safe-runtime validated.** The immediate synchronous hardening remains the
  protected fallback. The v3 asynchronous Sidekiq workflow is deployed for **Standard “Register New Number” only**;
  Coexistence remains on its existing synchronous flow and is never controlled by the Standard emergency switch.
  The `waiting_meta` lifecycle correction merged as `a709528`; Section D's hotfix merged as `4bbeecda` and is
  DEV-deployed. Section E's Coexistence readiness correction merged as `ca6086c` and is DEV-deployed; one approved
  provider attempt failed closed because Meta remained DISCONNECTED and the official readiness pair remained false.
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

### C. `waiting_meta` lifecycle and reconnect ownership correction (Accepted — merged `a709528`; DEV lifecycle proof)

A confirmed DEV reconnect failure exposed three lifecycle ownership gaps: the browser mapped persisted `waiting_meta`
to generic processing, local Cancel did not terminalize the server attempt, and the implemented recovery sweep had no
scheduler registration. Later popup completions entered the separate Coexistence endpoint; that endpoint safely
returned `no_connected_registration`, but it was not the owner of the Standard attempt.

The corrective contract is:

- `waiting_meta` has its own Standard-labelled UI state. **Relaunch Meta** first authorizes the same account-owned
  attempt through a side-effect-free endpoint, then opens Standard Embedded Signup with `coexistence: false` and
  submits only to that attempt's async `submit` endpoint. Relaunch never creates an attempt, advances generation, or
  enqueues a job.
- **Cancel setup** is server-authoritative and idempotent for `waiting_meta`: it row-locks the attempt, transitions it
  to `cancelled`, clears temporary encrypted secrets and stale lease/enqueue ownership, preserves the row for audit,
  and returns the existing safe DTO. Processing/terminal states other than an already-cancelled replay fail safely.
- Every persisted attempt status maps explicitly to one UI state. Raw SDK/server messages never enter UI state;
  only a fixed allowlist of stable non-secret codes may render as a Standard-flow error reference.
- `Bloomwire::WhatsappOnboardingSweepJob` is registered exactly once in `schedule.yml` on `scheduled_jobs` every
  minute. The existing recovery service remains authoritative for the generous 30-minute abandonment TTL and the
  60-second redrive grace.
- Existing account scope, administrator authorization, base managed-feature gate, safe DTO, encrypted-at-rest
  attempt storage, emergency-switch continuity, and Standard/Coexistence endpoint separation remain unchanged.

### D. Disconnected reconnect is not persisted-finalized crash resume (Accepted — merged `4bbeecda`; DEV deployed)

Live DEV certification on merged/deployed `a709528` proved one additional ownership distinction. A preserved setup may
hold its previous channel credential while `setup_status=disconnected`; that state exists specifically so a later
Embedded Signup reconnect re-registers the same records. It is not evidence that a new submitted attempt has already
persisted/finalized. The former fast path checked only matching setup + credential, skipped the fresh OAuth code, and
mapped every non-ready setup to `action_required`.

The corrected invariant is:

- persisted crash-resume may short-circuit only when the matching setup is already a persister final outcome:
  `ready_for_webhook` or `action_required`;
- `disconnected`, `pending`, `configured`, or `blocked` cannot consume that shortcut and must continue through OAuth
  exchange, register reconciliation, capability, subscription, and idempotent persistence;
- reconnect persistence still reuses the same Channel/Inbox/Setup and never creates duplicate chat/message/contact
  state.

Runtime-shaped TDD proved the bug RED **1/1** and the guard GREEN **1/0**; processor **25/0**; adjacent lifecycle
**58/0 with 5 expected inverse-key pending**; RuboCop **2/0**. The single live attempt's OAuth code expired before
recovery, was safely cleared as terminal `expired`, and did not alter the disconnected number or 50/17/17 records.
No second attempt was created. The emitted root token-shaped line was verified invalid; DEV/Meta browser sessions and
storage were invalidated/cleared. PR #156 exact-reviewed head `0fd8adc` passed CI 8/8, merged as `4bbeecda`, and DEV
run `29095330302` passed exact SHA, health, migrations, cron, volumes, queues, and clean recent-log checks.

### E. Coexistence reconnect uses Business App onboarding readiness (Accepted — merged `ca6086c`; DEV deployed; provider certification blocked)

The owner clarified that the certification target is not another Standard attempt: it is one future Coexistence
reconnect of the same existing WhatsApp Business App number while reusing Inbox 50 / Channel 17 / Setup 17. Read-only
DEV truth on `4bbeecda` showed one disconnected binding, zero active Standard attempts, and Channel 17 still marked
`connection_mode=standard`. A safe live GET returned HTTP 200 with `status=DISCONNECTED`, `is_on_biz_app=false`, and
`platform_type=CLOUD_API`, proving the official conjunction remains false before a successful Coexistence popup.

The deployed Coexistence service correctly skips Standard Cloud API `/register`. Its remaining defect was readiness
ownership: it checked only `status=CONNECTED`; a still-DISCONNECTED selection then entered the connected-duplicate
resolver and returned `no_connected_registration`. Meta's documented post-popup Coexistence contract is instead the
exact pair `is_on_biz_app=true` plus `platform_type=CLOUD_API`. Shared reconnect persistence also reused records without
applying the Coexistence create override, so old mode metadata survived.

The focused correction is:

- add a read-only two-field Graph query behind the existing open/read timeout and sanitized error path;
- only Coexistence checks that pair after a non-CONNECTED status and never enters Standard `/register`;
- preserve existing capability, final-WABA subscription, safe DTO, resolver, account scope, and failure behavior;
- run a default-no-op channel-configuration hook inside the existing reconnect transaction; Coexistence merges
  `source=bloomwire_managed` and `connection_mode=coexistence` before the mapping write;
- create no new Channel/Inbox/Setup and never rotate a credential without a fresh popup-derived token.

Public-service TDD proved RED **1/1** → GREEN **1/0**. Coexistence **18/0**; Graph client **34/0**; Coexistence request
plus Standard inverse **64/0**; affected matrix **170/0 with 25 expected no-key pending**; keyed processor consumer
**25/0**. RuboCop **5/0**; independent Standards/Spec review **0/0 findings**; diff/docs/HTML/secret checks clean.
PR #157 exact head `2becf92` passed CI **8/8**, merged as `ca6086c`, and DEV run **29102109973** passed exact
Rails/Sidekiq SHA, health 200/200, 0 pending migrations, preserved data services, and clean encryption/queue checks.

One separately approved dedicated Coexistence popup then produced both browser signals and exactly one controller
request. The request failed closed after 6.177s with safe `422 no_connected_registration`; no automatic retry ran.
Route/log proof found one Coexistence request, zero Standard attempt requests, zero `/register`/`deregister` markers,
zero subscription failures, zero 5xx, and zero secret-like hits. Post-attempt Meta remained `DISCONNECTED` and the
official readiness conjunction remained false. Setup stayed `disconnected`; Channel stayed `standard`; 50/17/17,
all uniqueness counts, timestamps, and the encrypted credential remained unchanged; active attempts, enqueued/retries,
and retained temporary secrets remained zero.

The implementation and exact-SHA deployment pass, but provider certification is **FAILED CLOSED / BLOCKED**. A
successful provider transition, transactional mode change, success-path record reuse, and inbound/outbound messaging
were not reached. No second popup, message test, Standard fallback, manual provider mutation, schema/frontend/API/
router/Enterprise/production change, duplicate, or credential rotation occurred or is approved. The exact reason
Meta's completion UI did not yield the official readiness pair is not proven and must not be inferred.

### F. Permanent local Inbox removal preserves attempt audit history and fences stale persistence (Accepted — PR #166; base `52e5524`; fence `8403cc5`; review `4679498933` identity `ba62ba7`; refreshed CI/review pending)

A DEV Remove Inbox failure proved that retained attempts are a database dependency of their bound Inbox/Channel. Five
terminal rows blocked `inbox.destroy!` after Setup and history had already committed, leaving a partial aggregate. The
attempts must not simply be deleted: this ADR already preserves cancelled/terminal rows as the non-secret audit record of
an onboarding run, and both target foreign keys are intentionally nullable. The permanent-removal contract is therefore:

- preserve terminal attempts, but clear their optional `inbox_id` and `channel_whatsapp_id` before destroying the target;
- for a bound active attempt, transition to secret-free `cancelled`, clear code/token/stage plus lease/enqueue/processing
  ownership, then clear both target references;
- local Inbox/Channel FKs are not stable pre-persistence identity: submit binds `phone_number_id` first. Purge therefore
  preserves exact linked-audit matches and also selects only active attempts with the same account and one unambiguous
  nonblank `phone_number_id` from the current Channel/Setup;
- blank, missing, whitespace, or conflicting Channel/Setup phone identity adds no match. WABA is never a fallback;
  different-phone attempts in the same account/WABA and matching-phone attempts in another account remain untouched;
- cancellation is not itself a persistence fence: async mapping persistence must re-lock the Attempt and validate active
  status, `processing_owner`, `submission_generation`, and unexpired lease in the same transaction as Channel/Inbox/Setup
  persistence plus Attempt binding/finalization; mapping-level rollback uses a savepoint within that outer fence;
- local processor writes (`mark_processing`, safe error, resume binding/finalization, and terminal transitions) use the
  same owner/generation/lease guard so cancellation cannot be overwritten later;
- lock related Attempts in ascending ID order before the Inbox, then lock Setup Requests/Setups and owned children. This
  matches persistence’s Attempt → mapping order and avoids the deterministically reproduced Attempt↔Inbox deadlock;
- preserve account-level Setup Request intake history while clearing its optional link to the technical Setup;
- keep every Meta/network call outside DB transactions and row locks. Remove Inbox remains local-only: no register,
  deregister, reconnect, webhook subscription/unsubscription, credential mutation, or provider API call;
- return HTTP `202` plus safe `status=pending` when accepted. Automatic completion reconciliation is deferred; refresh
  reloads the authoritative Inbox list and browser/store state must not claim deletion before completion is known;
- add no schema/FK change: lifecycle ordering, one transaction, and the existing Attempt lease are the smallest root fix.

The persistence-fence RED/GREEN remains. Review `4679498933` added a production-shaped unbound fixture: identity RED
**49/3** proved purge-first resurrection, persistence-first absence of blocking/complete locks, and direct failure to
cancel the exact unbound worker. GREEN is **51/0** and ten repeated deterministic race runs are **100/0**. A lower-ID
bound audit plus the active unbound worker prove stable ordered locks and no deadlock. All Meta collaborators remain
mocked/WebMock-blocked and no network executes inside the fence. Implementation `ba62ba7`; refreshed exact-head CI and
review remain required.

This decision does not restore the existing DEV partial state. Inbox 50 / Channel 17 remain without Setup 17 or history,
and the five terminal attempts remain bound until a separately approved recovery phase.

## Consequences

- **Positive:** no more split-state 500s on a slow `/register`; each Meta call is individually bounded; retries
  converge to exactly one set of records; the global request budget is untouched for all other traffic; timeout
  errors are secret-free.
- **Trade-offs:** the synchronous 75s endpoint budget remains while the rollback fallback exists. Async Standard adds
  an encrypted attempt lifecycle, leases, recovery, TTL sweeping, a job, polling, and operator-visible failure states.
- **Compatibility:** Feature OFF remains stock/inert. Standard async, native WhatsApp, global routing, existing record
  identities, and conversation/message/contact sources of truth are unchanged. Coexistence gains only its official
  readiness read and transactional mode correction for reused records.

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
- Corrective lifecycle implementation evidence (2026-07-10; all provider boundaries mocked/WebMock-blocked): relaunch
  API RED **3/3 failures** → GREEN **3/0**; frontend lifecycle RED **44 tests / 11 failures** → GREEN **44/0**; safe
  error/flow-label RED **41 tests / 6 failures** → GREEN **41/0**; scheduler RED **2/1** → GREEN **2/0**;
  independent concurrency QA duplicate Start RED **31/1** → GREEN **31/0**. Final affected backend **114/0 (5
  expected inverse-key pending)** plus encryption-absent **5/0**; frontend **134/0**; targeted RuboCop/ESLint clean;
  translation JSON valid; production Vite build completed in **45.94s**; static secret-pattern scan **922 added lines /
  0 hits**. No live Meta/WhatsApp call, provider-credential mutation, Enterprise change,
  production change, or DEV data mutation occurred.
- Corrective lifecycle delivery: PR #155 head `f37467c`, CI 8/8, merge `a709528`, DEV run `29091137113`;
  exact SHA, health, migrations, cron, and volumes verified. Section D then merged/deployed as `4bbeecda`; provider
  certification remains blocked pending Section E's Coexistence readiness fix and explicit owner approval.
