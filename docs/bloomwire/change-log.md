<!-- Docs only. Bloomwire-owned change log. Kept current per AGENTS.md -> "Bloomwire Documentation Governance". -->

# Bloomwire Change Log

Docs-first change log for **Bloomwire-owned** changes. The full implementation reference lives in
[`implementation-ledger.md`](./implementation-ledger.md); the rule that keeps this file current is
`AGENTS.md` → **"Bloomwire Documentation Governance"** (introduced in Phase 15E.1).

Every entry should record: **phase · PR · merge SHA (once known) · summary · why · what was NOT
changed · validation · residual risks**, and (for security/permission/WhatsApp changes) state
explicitly: **no secrets exposed · no provider-credential mutation unless authorized · whether live
Meta/WhatsApp calls were made · whether Enterprise code was touched.**

---

## Unreleased / Pending Merge

### Admin — Remove WhatsApp Inbox (managed deprovision) — OPEN (product code; not merged)
- **Branch:** `feat/bloomwire-remove-whatsapp-inbox` off `version_1` `a6b26e8404d5d81f1ac489e8db2c97c891c3e78c` (post‑#131 merge SHA).
- **GPT‑5.5 CHANGES REQUIRED (2nd pass, reviewed `2a96f49`) — fixed:**
  1. **`RecordNotDestroyed` no longer swallowed.** `.purge!` keeps the safe `RecordNotFound` race no-op, but a
     `RecordNotDestroyed` (e.g. a halted destroy callback) is treated as success ONLY if a fresh `Inbox.exists?`
     check proves the inbox is gone; otherwise it logs a sanitized `removal_failed` and **re-raises for Sidekiq
     retry** (RED→GREEN spec: surviving inbox propagates + is not marked successful).
  2–3. **Enqueue acceptance verified + deterministic routing.** `#prepare` now checks `perform_later` acceptance
     (`false` / not-`successfully_enqueued?` / raised → confirmed failure); on failure it **restores the prior
     routeable status** (deterministic — nothing deleted, fully routeable again) and returns `:enqueue_failed`
     (controller → **503**, retriable). Success returns 202 only for a confirmed-accepted job. Tests cover
     false/un-enqueued/raised enqueue + the successful manual retry.
  4. **Sanitized audit events** `removal_started` (prepare), `removal_succeeded` (purge done), `removal_failed`
     (purge error, warn) — internal ids/actor/error-class only.
  5. **Settings-level gate test** — `Settings.vue#canRemoveManagedWhatsappInbox` proven: capability OFF hides the
     action; capability ON + managed WhatsApp Cloud shows it (+ non-cloud / non-managed hidden).
  6. **Real 15s timeout-abort test** — advancing the timer aborts the request and surfaces the safe error (no hang).
  - Re-validated: service 24 · job 1 · request 8 · component 11 · settings-gate 4; full WhatsApp backend regression
    **490/0** (1 pending); FE 64; ESLint + RuboCop + vite build clean; no secret in diff.
- **GPT‑5.5 CHANGES REQUIRED (1st pass, reviewed `cecac65`) — fixed:**
  1–4. **Async, retry-safe deletion.** The heavy purge moved OUT of the request into a dedicated idempotent
     background job (`Bloomwire::WhatsappInboxDeprovisionJob`). The request path is now short — `#prepare`:
     authorize/verify account+source, **block routing** (`setup_status -> 'blocked'`, committed), **enqueue**, and
     return **202 `removal_started`**. `.purge!` re-verifies state each run, **no single giant transaction** (batched
     per-record destroy!), and handles concurrent/duplicate/retried jobs (no-op when gone; rescues the
     RecordNotFound race; lets unexpected errors propagate so Sidekiq retries). New concurrency/retry/idempotency
     tests added.
  5–6. **UI gated on the onboarding capability.** The Remove action is gated on `canSelfServeManagedWhatsapp` (the
     SAME server-derived capability onboarding uses; opt-in default FALSE) → **hidden when the feature is OFF**.
  7. **Bounded, abortable FE lifecycle.** The removal request uses an `AbortController` + a 15s timeout, aborted on
     `onBeforeUnmount`/`onBeforeRouteLeave`; a `leftFlow` guard prevents any late alert/emit after route leave.
  8. **Accurate wording.** Success now says **"removal started"** (accepted async job), not "removed".
  - Re-validated: service 16 · job 1 · request 6 · component 10; full WhatsApp backend regression **481/0** (1
    pending); ESLint + RuboCop + vite build clean; no secret in diff.
- **Why:** in managed mode, account admins cannot remove a WhatsApp inbox — the stock `InboxesController#destroy`
  is blocked by `restrict_managed_provider_inbox_destroy!` (403). This adds a dedicated, admin-facing deprovision.
- **Backend — dedicated deprovision service** (`Bloomwire::WhatsappInboxDeprovisionService`) + endpoint
  `DELETE …/bloomwire/whatsapp/inboxes/:id` (admin-only, account-scoped, feature-gated 404). It does **not** weaken
  the stock destroy guard. Sequence: (1) **block routing first** — `Bloomwire::WhatsappSetup.setup_status ->
  'blocked'`, committed immediately (the global router only routes `ready_for_webhook`); (2) **destroy the setup
  mapping** explicitly (it has no dependent cleanup and would otherwise orphan); (3) **destroy the inbox**, which
  cascades conversations/messages/contact_inboxes/inbox_members/reporting_events/webhooks + the `Channel::Whatsapp`
  (`dependent: :destroy`). Shared **Contact records are preserved** (only ContactInbox joins go). **Idempotent**
  (repeat → 404). **Meta boundary:** only `provider_config['source'] == 'bloomwire_managed'` channels are
  deprovisioned, so `Channel::Whatsapp#teardown_webhooks` (a Meta unsubscribe, `embedded_signup`-only) **never
  fires** — no WABA delete, no number deregister, no Meta call. Sanitized audit log (internal ids only). After
  removal the local `phone_number_taken` guard no longer matches (number freed); the global uniqueness guard is
  unchanged.
- **Frontend:** an admin-only "Remove inbox" action on the WhatsApp inbox settings page opens a destructive
  confirmation modal (title, irreversible warning, inbox name, **masked** phone number (last 4 only), connection
  mode Standard/Coexistence, the Meta-boundary note, Cancel + red "Delete inbox permanently"); repeated clicks
  disabled while deleting; safe success/failure alerts; on success it returns to the inbox list. Never renders the
  full number, phone_number_id, WABA id, or credentials.
- **Not changed / safety:** stock destroy guard; the global duplicate-number guard; the webhook router resolution;
  Enterprise. No Meta call; shared Contacts + other inboxes/tenant data untouched; the DEV account‑1 fixture is not
  deleted by tests (each test builds its own account/inbox).
- **TDD:** service `whatsapp_inbox_deprovision_service_spec` **11** (cross-account/not-whatsapp/not-managed refusals;
  destroys inbox+channel+setup no orphans; conversations/messages/contact_inboxes deleted; shared Contact preserved;
  unrelated data untouched; router stops resolving; no Meta call; idempotent; number freed); request
  `inboxes_spec` **6** (feature-off 404; admin removes; agent 403; cross-tenant 404; idempotent 404; no-secret
  response); component `BloomwireRemoveWhatsappInbox.spec` **8** (action shown; warning/name/mode; masked number
  only; Coexistence mode; cancel = no writes; confirm dispatches + emits; safe error; repeated-click guard). Full
  WhatsApp backend regression **492 examples, 0 failures** (1 pending); FE `57` (removal 8 + wizard 45 + api 4);
  ESLint + RuboCop + vite build clean; `git diff --check` clean; no secret in diff.

### Duplicate WhatsApp-number UX (preflight + safe error mapping) + sensitive-parameter log filtering — OPEN (product code; not merged)
- **Branch:** `fix/bloomwire-duplicate-number-ux-and-log-filtering` off `version_1` `209bfb0f7acb8674c3a9731d7ab219ed5972252a` (current deployed SHA).
- **GPT‑5.5 CHANGES REQUIRED (reviewed `fb77e55`) — 3 items fixed:**
  1. **Lifecycle-safe bounded preflight:** the preflight now runs INSIDE the attempt's `try` — `attemptSeq`/`seq` +
     timer/abort reset are established BEFORE the first await; the request is **bounded** (`PREFLIGHT_TIMEOUT_MS`
     8s) via a cancellable timer + `AbortController` (signal threaded store→API→axios), **aborted** on
     unmount/route‑leave; a **stale/leftFlow check runs immediately after the await, before creating a tracer or
     opening Meta** (a late response can no longer open the popup after the flow left); `attemptActive` is released
     on every terminal preflight path; a visible "checking" state disables the submit action. Fails open; the
     authoritative post‑Meta guard is unchanged.
  2. **Availability-oracle throttling:** the `phone_availability` endpoint is rate-limited per `(account, actor)`
     (`RATE_LIMIT` 20 / `RATE_PERIOD` 60s) → **429** on excess (lookup not run); the raw phone number is never
     logged (anchored filter, below); response contract unchanged (`{ status }` only, no tenant leak).
  3. **Exact-key parameter filtering:** replaced the broad `:code`/`:phone_number` substring symbol filters with
     **anchored regexes** (`/\Acode\z/i` … `/\Aphone_number\z/i`) so unrelated keys (`error_code`, `status_code`,
     `country_code`, `phone_number_verified`) stay visible and `website_token` is preserved, while the required
     sensitive keys render `[FILTERED]` (verified).
  - Re-validated: service 8 · request 9 · filter 3 · wizard **45** (+4 preflight-lifecycle: timeout→fail-open,
    unmount-during-preflight, route-leave-during-preflight, clean manual retry); WhatsApp backend regression
    **337/0**; ESLint + RuboCop + vite build clean; no secret in diff.
  - **Note:** the "Remove WhatsApp Inbox" feature is intentionally **out of this PR** — it will be a separate
    focused PR after #131 is approved and merged.
- **Root cause (proven, prior investigation):** on DEV a Standard signup used a number already connected as the
  account‑1 fixture; the backend correctly returned **422 `phone_number_taken`** with the safe message "This
  WhatsApp phone number is already connected.", but the wizard **discarded** the backend `code`/message and showed
  only the generic "We couldn't finish connecting WhatsApp." (UX defect). Separately, the Meta auth `code` was
  logged unfiltered in the Rails Parameters line (log-hygiene defect).
- **Fix 1 — advisory duplicate preflight:** new admin-only, account-scoped, feature-gated (404) endpoint
  `POST …/bloomwire/whatsapp/phone_availability` (`Bloomwire::WhatsappPhoneAvailability`). Normalizes the typed
  number to `+<digits>` (consistent with `Channel::Whatsapp` / `PhoneInfoService`) and does a **global** existence
  check (mirrors the authoritative unique guard). Returns **only** `{ status: "available" | "already_connected" }` —
  never another tenant's account/inbox/channel id or name, `phone_number_id`, WABA id, or any secret. The wizard
  calls it before opening Meta; **already_connected → the Meta popup does not open** and it shows "This WhatsApp
  number is already connected to Bloomwire. Use a different number or disconnect the existing inbox first." Advisory
  only: it **fails open** (blank/error) and the **authoritative post-Meta guard is unchanged** (Meta may confirm a
  different number).
- **Fix 2 — safe backend error-code mapping (Standard + Coexistence):** the wizard now reads
  `error.response.data.code` and maps `phone_number_taken` / `phone_number_id_conflict` / `invalid_phone_number` to
  specific safe messages; `meta_error` / unknown / 5xx / timeout keep the generic safe message. Raw backend/Meta
  exception strings are never shown.
- **Fix 3 — copy:** a note under the number field — "Use a number that is not already connected to another Bloomwire
  inbox." (does not imply "New number" means unused).
- **Fix 4 — sensitive Rails parameter filtering:** added `code, auth_code, business_id, waba_id, phone_number_id,
  display_phone_number, access_token, phone_number` to `config.filter_parameters` (Rails substring matching, so
  `:phone_number` also covers `phone_number_id`/`display_phone_number` and `:code` covers `auth_code`). Intentionally
  did **not** add a bare `:token` (the existing regex already filters `token` while preserving the `website_token`
  exception). Verified the auth code + identifiers now render `[FILTERED]`; `website_token` still preserved.
- **Not changed / safety:** the authoritative global duplicate guard; the existing account-1 WhatsApp fixture (not
  deleted/modified/reassigned); the webhook router; Enterprise. No number was moved/reassigned; no Meta retry; the
  preflight is read-only (creates/modifies no records) — account‑21 stays 0 Inbox / 0 Channel::Whatsapp / 0
  WhatsappSetup.
- **TDD:** service `whatsapp_phone_availability_spec` **8** (normalize/available/already_connected incl.
  cross-account global, read-only, safe enum); request `phone_availabilities_spec` **7** (admin + account-scope +
  feature-gate + already_connected-without-tenant-leak + read-only); `filter_parameter_logging_spec` **2** (fields
  → `[FILTERED]`; website_token preserved); wizard `BloomwireWhatsapp.spec` **41** (+9: preflight available→popup,
  already_connected→no popup, warning shown, fail-open, Standard/Coexistence `phone_number_taken`,
  `phone_number_id_conflict`, unknown/5xx→generic, Fix‑3 note). WhatsApp backend regression **334/0**; ESLint +
  RuboCop + vite build clean; `git diff --check` clean; no secret in diff.

### Coexistence onboarding infinite-wait hardening + sanitized end-to-end trace — OPEN (product code; not merged)
- **Branch:** `fix/bloomwire-coexistence-onboarding-trace` off `version_1` `d21a243b614835769a3dd3c255c1d917e75dfdfc`
  (base verified, current deployed SHA).
- **GPT‑5.5 CHANGES REQUIRED — 4 blocking findings fixed (reviewed head `5d4f763`):**
  1. **Standard flow restored:** the tracer is created **only for Coexistence** (per attempt); Standard/native uses
     a no-op tracer → **no** attempt id, **no** browser trace events, **no** trace-endpoint call, never `mode=coexistence`;
     the Standard create payload is exactly pre-PR (no `onboarding_attempt_id`).
  2. **Fresh attempt id per attempt:** the tracer + random id are minted at the **start of every** Coexistence
     attempt (not at mount); a retry uses a **different** id + support reference, carried end-to-end (signup →
     signals → create POST → controller trace → UI); no stale state/timers/events carry over.
  3. **Lifecycle-safe create:** the create timeout is a lifecycle-scoped, cancellable timer + an `AbortController`
     (signal threaded store→API→axios) cleared/aborted on success/failure/route-leave/unmount/retry; a per-attempt
     **stale guard** makes any late response inert (no UI change, no navigation, no late trace, no store refresh —
     the abort makes the store action reject before its `dispatch('get')`).
  4. **Forbidden trace payloads rejected:** the trace endpoint now inspects the **raw** body before strong-params
     and returns **4xx with no log** for ANY non-allow-listed top-level key (unknown or sensitive:
     `code/auth_code/access_token/token/phone/phone_number/phone_number_id/waba_id/business_id/app_id/configuration_id/url/query/message/metadata/...`);
     unknown event → 422; a logging-infra failure for an otherwise-valid request still returns 204.
  - Suite after this first fix pass (historical snapshot; superseded — see the **Current exact-head validation** line
    below): composable **20**, wizard **29**, trace service **8**, trace endpoint **25** (incl. per-sensitive-key
    rejection), WhatsApp backend regression **314/0**; ESLint + RuboCop + vite build clean; no migration/schema; no
    Standard/router/Enterprise change beyond restoring Standard; no Meta retry; no record mutation.
- **GPT‑5.5 CHANGES REQUIRED (2nd pass, reviewed `4d041b5`) — remaining blocker fixed: double-submit attempt ownership.**
  `register()` mutated attempt state (tracer / attempt id / support reference / `attemptSeq` / `AbortController` /
  timer) **before** the composable's in-flight guard, so a rapid second click could mint a second id, bump `attemptSeq`,
  and supersede/abort the first valid attempt. Fix: a **wizard-owned `attemptActive` guard** set the instant an attempt
  starts (before ANY attempt-state mutation) and cleared only on a terminal state (success/failure/cancel/timeout/
  route-leave/unmount). A second submit while a signup OR create is active is now a **pure no-op** — exactly one tracer,
  one attempt id, one Meta signup launch, one create POST (carrying the first id); no supersession, no abort of the
  active attempt, no support-reference change. Manual retry after a terminal failure still mints a fresh id. Wizard spec
  now **32** (added: no-op during signup — one tracer/id/signup/no-abort; support-ref unchanged; no-op during
  creating_inbox — form hidden + one POST; retry → new id; RED-proven: without the guard a double-submit mints 2
  tracers). Standard flow unchanged.
- **Current exact-head validation (head `181d34ecabb67f01c929281739548ecaad11f960`):** composable **20** · wizard
  **32** · trace service **8** · trace endpoint **25** · WhatsApp backend regression **314 examples, 0 failures** ·
  CI **8/8 green** · unresolved review threads **0**. ESLint + RuboCop + vite build clean; `git diff --check` clean;
  no secret in diff; no migration/schema; no webhook-router change; no Enterprise change; Standard flow unchanged;
  no Meta retry; no account/Inbox/Channel/WhatsappSetup mutation. **PR remains unmerged and undeployed.**
- **Incident (Part 1, evidence-based classification): Stage A** — during a live Coexistence attempt the customer
  completed the Meta flow (3 Meta webhooks at 04:17–04:19 today → `[BLOOMWIRE ROUTER] no handoff-safe setup`,
  `200 OK`), but the **browser received no signal that resolved `runEmbeddedSignup()`** → the create POST was
  **never dispatched** (0 coexistence POSTs in the whole current-container log window) → **0 records** for the
  target account; the hang was **indefinite** → PR #127's second-signal timeout **never armed** (it arms only
  after the first signal). Not D/E/F. Exact browser sub-stage was not directly logged (no client trace existed —
  fixed by Part 2).
- **Part 3 — every infinite-wait path removed:** `useWhatsappEmbeddedSignup` now has an explicit finite state
  (`idle/launching/waiting_for_meta/waiting_for_second_signal`) with an **overall watchdog armed at launch**
  (`OVERALL_SIGNUP_TIMEOUT_MS`, default 180s) that bounds the **zero-signal / never-settling SDK/FB.login** class
  the second-signal timer cannot, plus the existing second-signal timer; the wizard adds a **bounded backend create
  request** (`CREATE_REQUEST_TIMEOUT_MS`, 45s) that fails closed. **Guaranteed teardown** (settle-once cleanup +
  `cancel()` wired to `onBeforeUnmount` + `onBeforeRouteLeave`) clears timers, the `message` listener,
  `isAuthenticating` and processing state on every success/cancel/timeout/exception/unmount/route change. On
  failure the UI stops the spinner, shows a **sanitized** message ("No automatic retry was performed"), a
  **support reference** (short attempt id), and a safe manual **Retry** — no auto-retry, no partial local records.
- **Part 2 — structured sanitized trace:** one random `onboarding_attempt_id` per attempt is carried browser →
  controller. New `Bloomwire::OnboardingTrace` writes ONE allow-listed structured-JSON line per event to the app
  log (22 events: `onboarding_started` … `attempt_finished`); metadata is strictly allow-listed
  (attempt id, account id, actor id, mode=coexistence, event, result, elapsed_ms, http_status, sanitized
  error_code, source, build sha, ts). New admin-only, account-scoped, feature-gated (404), rate-limited endpoint
  `POST …/bloomwire/whatsapp/onboarding_traces` receives browser events with a strict event + metadata allow-list
  (rejects arbitrary/sensitive payloads; unknown event → 422; a logging failure always returns 204). **Never logs**
  auth code / token / phone number / phone_number_id / WABA / business / App ID / Config ID / Meta URL. Standard
  (native) flow is unchanged (no tracer → no attempt id, no trace calls).
- **Not changed:** backend authorization; the global webhook router; the coexistence service's Meta/DB behavior;
  Standard flow; Enterprise; **no schema/migration** (trace → app log, not a DB table); account-1 fixture. No Meta
  onboarding retried; no records mutated during investigation.
- **TDD — initial validation (HISTORICAL snapshot at first push; superseded by the two review-fix passes above —
  see the current exact-head counts: composable 20 · wizard 32 · trace service 8 · trace endpoint 25 · backend 314/0):**
  composable `useWhatsappEmbeddedSignup.spec.js` **20** (overall watchdog / zero-signal, second-signal,
  either-order, duplicate→one, SDK-never-settles, cancel/unmount, double-click guard, trace correlation);
  wizard `BloomwireWhatsapp.spec.js` **25** (create timeout, 4xx, 5xx, success transition, failure clears loading,
  unmount + route-change cleanup, repeated attempt, no-parallel, attempt-ref); `onboarding_trace_spec` **9**
  (allow-list, secret rejection, sanitization, never-raise); `onboarding_traces` request spec **8** (admin +
  account scope + feature gate + allow-list + rate-limit + logging-failure-safe). WhatsApp backend regression
  **281/0**; ESLint + RuboCop clean; vite build ok; no secret in diff.

### WhatsApp channel tile intermittently disappears (deterministic-state fix) — OPEN (product code; not merged)
- **Branch:** `fix/bloomwire-whatsapp-tile-race` off `version_1` `8fabfc331b7f62d5c64197fe020e563140d3239f`
  (base verified). **Frontend-only; no backend / DB / router / auth / config change.**
- **Symptom:** on `/app/accounts/:id/settings/inboxes/new`, same user/account/URL/build, the WhatsApp channel
  tile appeared on one refresh and was absent on another (demo-blocking, non-deterministic).
- **RCA (proven):** the tile is gated by the server capability `canSelfServeManagedWhatsapp`; for a managed
  account it is the **only** permitted tile (all others need `canCreateInbox`, which is `false`). The backend is
  **deterministic** (verified on deployed `8fabfc33`: `Bloomwire::Capabilities.for` → `canSelfServeManagedWhatsapp=true`,
  `canCreateInbox=false`, 10/10; all feature flags resolve true; capabilities live **only** on the account-show
  payload — `_account.json.jbuilder` emits them `if @current_account_user.present?`, and the lighter bootstrap
  `_user` accounts array omits them). The **frontend** was the fault: `useBloomwireCapabilities` returns
  `canSelfServeManagedWhatsapp=false` as a **fallback whenever the account payload has not (fully) hydrated** and
  **cannot distinguish "loading" from "denied"**; `ChannelList.vue` had **no loading state** and rendered the
  terminal "MANAGED_BY_OPS" empty state whenever the filtered list was momentarily empty (the anti-pattern
  "loading state shown as no-channels-available"); `initializeEnabledFeatures` also dereferenced
  `currentAccount.value.features` unguarded; and the stock `accounts/get` action **swallows failures silently**
  (no retry / no error), so an un-hydrated / failed account-show left the tile hidden until the next refresh.
- **Fix (smallest root fix, deterministic):** `useBloomwireCapabilities` now exposes `capabilitiesLoaded`
  (account payload carries a `bloomwire_capabilities` map). `ChannelList.vue` ensures the authoritative account
  payload is hydrated on mount (dispatches `accounts/get`) and renders: **loading skeleton** while capabilities
  hydrate (never the empty surface) → **recoverable error + retry** if the authoritative request fails / caps
  never arrive → the channel tiles once loaded → the managed empty state **only** when genuinely loaded with no
  permitted channel. `initializeEnabledFeatures` guards `currentAccount`. Agents stay blocked (real caps drive
  `isChannelSetupAllowed`); account context and the Standard/Coexistence WhatsApp wizard entry are unchanged.
- **Not changed:** backend authorization / `Bloomwire::Capabilities` / feature flags / webhook router / DB /
  config; the Standard & Coexistence flows; Enterprise. **No secrets / Meta identifiers** in code, tests, or logs.
- **`custom_roles` 500 (separate, unrelated):** `GET /api/v1/accounts/:id/custom_roles` → 500
  `NoMethodError: undefined method 'custom_roles' for Account` is the **Enterprise** controller calling
  `Current.account.custom_roles` (the `has_many :custom_roles` lives only in the enterprise Account concern) on a
  non-enterprise build. It is **not** requested on the inbox-new page (verified via the browser Network tab) and
  does **not** contribute to the tile defect → **tracked as a separate focused follow-up** (frontend should not
  fetch custom_roles when the enterprise custom-roles capability is absent); not fixed here (would touch
  Enterprise-gating, out of this PR's scope). Not ignored.
- **TDD / validation:** `ChannelList.spec.js` **24/24** (14 existing logic tests intact + 10 new: delayed
  hydration→tile, single fetch/tile, already-hydrated fast path, transient failure→error not empty, rejected
  request→error, retry→tile, eligible admin→tile, agent→blocked, repeated-mount determinism, account-switch no
  stale, Standard/Coexistence route unchanged); `useBloomwireCapabilities.spec.js` adds `capabilitiesLoaded`
  cases. Focused FE suites **58/58**; ESLint clean; `vite build` ok. **Runtime:** case A (tile visible) + the
  account-show **304-cache** + "no custom_roles on inbox-new" captured on the deployed build via an authenticated
  session; case B (tile missing) + the mandatory 20-hard-refresh check require the **account-1 admin** session
  (the session provided was account-21/amaya, which cannot access account 1) — pending.

### WhatsApp / Meta Graph API version contract → v25.0 — OPEN (product code; not merged)
- **Branch:** `fix/bloomwire-whatsapp-graph-api-v25` off `version_1` `e8717b059759da7b090b172c291ad2a33ea08794`
  (base verified). **Version-only change; no API behavior changed beyond v25.0 compatibility.**
- **Why:** the approved Meta Graph API version for this project is **v25.0**, but the Coexistence flow inherited
  older/implicit versions: the **frontend Embedded Signup SDK** silently used **v22.0** (the `WHATSAPP_API_VERSION`
  config was never passed to the browser, so `utils.js` fell back to a hard-coded `v22.0`); the **outbound
  message/media** path defaulted to **v24.0** (`WHATSAPP_CLOUD_API_VERSION` unset); backend code fallbacks were `v22.0`.
- **Centralized fix:** new single source of truth `Whatsapp::GraphApi::DEFAULT_VERSION = 'v25.0'` (backend) +
  `DEFAULT_WHATSAPP_GRAPH_API_VERSION = 'v25.0'` (frontend `utils.js`). All Coexistence-flow defaults now reference it:
  `Whatsapp::FacebookApiClient` (token exchange, WABA + phone-number queries, token debug, register, webhook
  subscribe/override/unsubscribe), `Whatsapp::HealthService`, `Whatsapp::Providers::WhatsappCloudService`
  (message + media paths), and the FB JS SDK init (`initializeFacebook` / `setupFacebookSdk`). `dashboard_controller`
  now passes `WHATSAPP_API_VERSION` (default v25.0) into `window.chatwootConfig.whatsappApiVersion` so the popup is
  config-driven with a v25.0 safety net. Per-surface ops overrides (`WHATSAPP_API_VERSION`, `WHATSAPP_CLOUD_API_VERSION`)
  are preserved. Runtime DB `WHATSAPP_API_VERSION` is already `v25.0`.
- **Explicitly NOT changed:** the global Meta webhook router (version-independent — routes by `phone_number_id`, unchanged);
  the Bloomwire WA Dev fixture; **Enterprise** WhatsApp calling (its own `WHATSAPP_CALLING_API_VERSION_FALLBACK`,
  untouched); the **template-management** surface (`business_account_path` + `Whatsapp::CsatTemplateService` remain on the
  pre-existing `v14.0` — not part of the Coexistence onboarding or message/status path; flagged as a separate follow-up);
  unrelated Instagram/Messenger/Shopify/reports versions.
- **TDD (RED→GREEN):** frontend `whatsapp/specs/utils.spec.js` **RED-proven** (4/5 failed on the old v22.0 fallback) → v25.0
  SDK init + no older/implicit version + override preserved; backend `facebook_api_client_spec` asserts every generated
  Graph URL is `/v25.0/` and never `/v1x|20–24/`; `whatsapp_cloud_service_spec` message/media default `/v25.0/` (+ ops
  override still works); `dashboard_controller_spec` asserts `whatsappApiVersion: 'v25.0'` reaches the window config.
  WhatsApp backend regression **278 examples, 0 failures** (Enterprise call-flow spec fails 6/6 **pre-existing** on clean
  `version_1`, unrelated). RuboCop + ESLint clean; vite build ok; `git diff --check` clean; no secret in diff (no App ID /
  Configuration ID / token / WABA ID / phone_number_id / phone number in code, tests, or logs).

### Coexistence onboarding callback fix — Stage-B transition hang — OPEN (product code; not merged)
- **Branch:** `fix/bloomwire-coexistence-callback-transition` off `version_1`
  `e8717b059759da7b090b172c291ad2a33ea08794` (base verified, fail-closed passed). **Frontend-only.**
- **Incident (root cause, proven):** during the first live Coexistence onboarding for account 21, the wizard reached
  "Registering your WhatsApp number…" and hung; **zero** backend create requests arrived (no
  `POST …/bloomwire/whatsapp/coexistence_embedded_signup`), account 21 stayed at 0 Inbox/Channel/Setup, and Meta sent
  two webhook events for the new number (global router fail-closed 200, existing fixture untouched). **Owner:**
  `useWhatsappEmbeddedSignup.js`. **Why:** the run's Promise settled only when **both** the FB.login `authCode` **and**
  the postMessage `businessData` were present (`resolveIfReady`); if exactly one Meta signal arrived and the other
  never did, the Promise **never settled**, so `isAuthenticating` stayed `true`, `BloomwireWhatsapp.vue`'s
  `await runEmbeddedSignup()` never returned, the `PROCESSING` loader showed forever, and the create POST was never
  dispatched. **Stage B** (browser received a Meta response, entered registering, but the create request never reached
  the backend).
- **Smallest root fix:** a **bounded completion timeout** in the composable, armed only **once the first** of the two
  signals arrives (never limits time spent in the Meta popup). If the second signal doesn't arrive within `timeoutMs`
  (default 60s), the run **fails closed** with a safe error instead of hanging. Both arrival orders still resolve
  exactly once; the existing `settled` guard keeps **duplicate** Meta events/callbacks to **one** resolution → **one**
  create POST; on reject/timeout the caller shows the sanitized generic error, ends the spinner, and leaves the form
  **retryable**; account context is preserved (unchanged account-scoped store/API). No Meta/WhatsApp/HTTP call added;
  no backend/DB/config/schema change; no secrets logged (auth code / token / phone / phone_number_id / WABA ID /
  Configuration ID / App ID never touched).
- **TDD (RED→GREEN):** `useWhatsappEmbeddedSignup.spec.js` +4 (auth-only→timeout reject **RED-proven** hang, business-only
  →timeout reject **RED-proven** hang, no-spurious-timeout-after-resolve, duplicate FINISH→one resolution) → **14/14**;
  `BloomwireWhatsapp.spec.js` +1 (signup reject → safe error + **no** create dispatch + retryable) → **16/16**. ESLint
  clean; `git diff --check` clean; no secret in diff. **Not changed:** the Meta event names/shape (no guessing), the
  backend coexistence endpoint/contract, the global webhook router, `WHATSAPP_CONFIGURATION_ID` (stays `0643fcdbad9c`).
- **Follow-up (separate slice, NOT in this PR):** `GET /api/v1/accounts/:id/custom_roles` → 500
  `NoMethodError: undefined method 'custom_roles' for Account` on non-enterprise accounts (surfaced on account‑21
  settings). It does not block the onboarding component (the create POST path is independent), so it is reported as a
  small separate follow-up rather than mixed into this fix.

### Phase 17F.3 — Guided TeamMember + InboxMember alignment — OPEN (product code; not merged)
- **Branch:** `feature/bloomwire-phase-17f3-guided-membership-alignment` off `version_1`
  `e9fcef99705eee792cf99c04baa9edc24eee880e` (PR #125 merge; base verified, fail-closed passed). **Scope: staff-access
  alignment only.** **Schema/migration: NO · persistent Inbox↔Team mapping: NO · new Category model/table/entity: NO ·
  WhatsApp onboarding/credentials/callbacks/subscriptions/global-router/message-routing: UNCHANGED · Meta/WhatsApp/
  external call during alignment: NONE · Enterprise: NO · DEV deploy: NO · production: untouched.**
- **Recorded — Phase 17F.2B DEV runtime PASS** (from the prior deploy step; carried here per instruction, no separate
  docs-only PR): deployed SHA `e9fcef99705eee792cf99c04baa9edc24eee880e`; deployment run `28732366110`; authenticated
  **account-1 administrator** validation; the Category → "Add WhatsApp Inbox" launcher was visible on **both** eligible
  Category/Team rows; the **account-scoped existing** WhatsApp Add-Inbox wizard was reached (`/accounts/1/settings/
  inboxes/new/whatsapp`, no team/category param); **Standard and Coexistence** options were reused; **zero** membership
  / inbox / channel / setup / contact / conversation / message deltas; **no** Meta signup or customer onboarding. **This
  is not Gate B PASS** and not customer-onboarding certification.
- **Discovered membership architecture:** categories are the existing **Team** convention; `TeamMember` (unique
  `[team_id,user_id]`) and `InboxMember` (unique `[inbox_id,user_id]`; stock `after_create` round-robin is a **local
  Redis** op, not external). The overview already exposes the actionable drift per **linked** (unambiguous) pair
  (`derived_inboxes[].drift.staff_missing_inbox_access` + `.collaborators_not_in_team`), so **no overview DTO change was
  needed**. `Current.account.teams.find` / `.inboxes.find` reject cross-account ids (404); admin via
  `check_admin_authorization?`; feature via `BLOOMWIRE_CATEGORY_ADMIN_UI` (404 when off).
- **Server-authoritative (GPT‑5.5 CHANGES REQUIRED fix):** the endpoint is **identity-only** — the request carries
  **only** `team_id` + `inbox_id` (`user_ids` removed from strong params **and** the frontend payload). The server
  **independently recomputes**, from **fresh DB state**, (a) that the pair is a **currently-derived, unambiguous,
  actionable** pair and (b) the additive drift, then adds **only** those server-computed differences. It **never**
  accepts client-selected membership IDs as authority; any client preview is **display-only**. Eligibility + drift are
  recomputed **inside the transaction** (association caches reset), so a **stale preview** (memberships changed after
  the UI rendered) is handled from fresh state. Fails closed (422) for **unrelated / ambiguous / unlinked / stale**
  pairs; cross-account team/inbox → 404 (`Current.account.teams/.inboxes.find`).
- **One derivation algorithm:** extracted the authoritative membership-overlap logic into
  `Bloomwire::CategoryInboxDerivation` (`matched_teams` / `derived_pair?` / `additive_drift`); **both** the read-only
  overview and the write-side alignment now use it, so they cannot diverge (overview output unchanged — 15 specs green).
- **Helper decision (existing APIs vs local helper):** the existing `team_members` + `inbox_members` endpoints are
  **two independent HTTP calls / two transactions**, so sequential FE composition can leave **partial completion**.
  The **local-only, admin-only, feature-gated** helper `Bloomwire::CategoryInboxAlignment`
  (`POST /bloomwire/category_inbox_alignment`) wraps both additive `TeamMember` + `InboxMember` writes in **one
  `ActiveRecord::Base.transaction`** — additive only (never removes staff), idempotent (diff-based no-op),
  account-scoped. **No new schema; no persisted Team↔Inbox mapping.**
- **Atomicity boundary (corrected — no overstatement):** the membership writes are **database-atomic** (a mid-write
  failure rolls back **all** rows). The stock `InboxMember after_create` round-robin (a **local Redis `LPUSH`** via
  `AutoAssignment::InboxRoundRobinService`) is **NOT part of the DB transaction** and can survive a later DB rollback;
  it is upstream behavior and **self-heals** from the DB source of truth (`available_agent` runs
  `reset_queue unless validate_queue?`, rebuilding the queue from `inbox.inbox_members`). The upstream callback was
  **not modified**. No Meta/WhatsApp/HTTP/email/webhook/external call occurs during alignment.
- **Frontend:** the Categories & Inboxes overview surfaces an **"Align staff access"** action only on a **linked**
  derived inbox that has drift and only for a category-admin (agents / feature-OFF / ambiguous → no action → fail
  closed). `MembershipAlignmentDialog.vue` previews the selected Team + Inbox, current staff on each side, and the
  **additive** diff (display-only) with a "no staff will be removed" note; Cancel writes nothing; **Confirm sends only
  `{team_id, inbox_id}`** (a double-submit guard ensures a single in-flight request); success refreshes the existing
  overview data source (no fabricated mapping); failure shows a safe error and never falsely shows aligned.
- **Validation (RED→GREEN):** backend `spec/requests/bloomwire/category_inbox_alignment_spec.rb` **19 examples, 0
  failures** (client `user_ids` ignored / no write authority ×2; server-side recompute; bidirectional additive;
  stale-safe fresh recompute; unrelated / ambiguous / unlinked / stale-ambiguous fail closed; cross-account team +
  inbox → 404; agent → 401; **database-atomic rollback**; **round-robin Redis boundary reconcilable**; no persistent
  mapping; no external call; feature-OFF → 404); overview regression **15** unchanged. Frontend Vitest categoryInboxes
  **4 files / 54 tests** (new dialog identity-only payload + **double-submit** test; align-action + wiring; 17F.1/17F.2B
  intact). RuboCop + ESLint clean; `git diff --check` clean; no secrets; **no schema/migration**. Safe DTO only
  (`{id,name}`) — no email/phone/secrets in responses, tests, logs, or docs.
- **Status:** **17F.3 IMPLEMENTED (staff-access alignment only).** Not customer-onboarding certification; **full Gate B /
  real Meta Coexistence certification remains required before production/customer go-live.** Do not merge · do not deploy
  · do not run Meta signup · do not onboard a customer · do not touch the existing "Bloomwire WA Dev" fixture — awaiting
  GPT-5.5 exact-head review.

### Phase 17F.2B — Category → "Add WhatsApp Inbox" launcher — MERGED (PR #125, merge SHA `e9fcef9`) + DEV runtime PASS
- **Branch:** `feature/bloomwire-phase-17f2b-category-add-whatsapp-launcher` off `version_1`
  `0c3f32d2e02d7d8d6d980b556614d31d9cfd4de6` (PR #124 merge; base verified, fail-closed passed). **Type:** frontend-only
  UI launcher. **Product code changed: YES (frontend only).** **Schema/migration: NO · backend endpoint: NO · new
  Category model/table/entity: NO · persistent Inbox↔Team mapping: NO · membership (TeamMember/InboxMember) writes: NO ·
  duplicate wizard: NO · per-customer webhook: NO · credential mutation: NO · Enterprise: NO · real Meta calls: NO ·
  DEV deploy: NO · production: untouched.**
- **OWNER-APPROVED DEPENDENCY CHANGE (recorded per owner decision):** 17F.2B implementation **may now begin before full
  Gate B certification.** **Full Gate B / Real Meta Coexistence certification remains MANDATORY before production /
  customer go-live and before claiming end-to-end customer-onboarding certification.** This entry records that explicit
  decision in the implementation PR (no separate docs-only contract-change PR was created).
- **What:** in the existing **Categories & Inboxes** admin overview (`categoryInboxes/Index.vue`), each Category/Team
  row now shows an **"Add WhatsApp Inbox"** action that **deep-links** to the existing normal Add-Inbox flow
  (`settings_inboxes_page_channel`, `sub_page=whatsapp` → the existing Standard/Coexistence managed wizard) via
  `useAccount().accountScopedRoute(...)`. It is a `router-link` (declarative navigation) — **it performs no writes,
  triggers no backend call, and creates no Category↔Inbox relationship** (membership alignment is deferred to 17F.3).
- **Authorization / gating:** launcher shown only when `canAccessCategoryAdmin && canSelfServeManagedWhatsapp` (existing
  category-admin + managed-WhatsApp-onboarding capabilities). Agents (both false) and feature-OFF never see it; the
  route guard (`redirectIfCategoryAdminDisabled`) + backend controllers remain the authoritative enforcement boundary.
- **Return behavior:** cancelling/completing the existing wizard returns via normal navigation; the overview refreshes
  through its existing data source (`onBeforeMount → categoryInboxOverviewAPI.get`) on re-entry; no fabricated mapping.
- **Validation (automated; supporting evidence — Gate B still required for customer cert):** RED→GREEN Vitest —
  `categoryInboxes/Index.spec.js` **20 passed** (8 new launcher tests; 4 were RED pre-implementation: admin sees it,
  correct account-scoped wizard route, no team/category param, declarative no-write click); categoryInboxes directory
  regression **3 files / 35 tests passed**; ESLint clean on changed files; `git diff --check` clean; no secrets in
  diff. Changed files: `categoryInboxes/Index.vue`, `categoryInboxes/specs/Index.spec.js`,
  `i18n/locale/en/categoryInboxes.json` (frontend only — no schema/migration/backend/workflow/Enterprise).
- **Status:** **17F.2B IMPLEMENTED (frontend launcher).** This is **not** a claim of customer-onboarding certification —
  that remains gated on full Gate B (real Meta Coexistence E2E) before production/customer go-live. Do not merge · do
  not deploy · do not run Meta Embedded Signup · do not start 17F.3 — awaiting GPT-5.5 exact-head review.

### Phase 17F.2A — DEV secure config + Meta Embedded Signup launch/cancel preflight — PENDING DOCS-ONLY PR
- **Base:** current latest `version_1` = `9fe522fbd5221ae301b7b133276c6c193eb65019` (PR #123 docs-only merge). No
  product code, tests, schema, workflows, runtime config, DEV, production, roles, memberships, inboxes, channels, setups,
  credentials, or existing WhatsApp fixture changed by this docs-only PR. Do not deploy this PR.
- **Secure DEV config evidence:** `WHATSAPP_APP_ID` present = true; `WHATSAPP_CONFIGURATION_ID` present = true;
  `platform_ready=true`. The two existing blank DEV `InstallationConfig` rows were updated securely; no duplicate rows
  were created; values were never printed, logged, or exposed. Rails and Sidekiq SHA remained
  `6894d93459cdba0fbc503a7d68b4f54b42a54571`; PostgreSQL and Redis were preserved; production was untouched.
- **Browser result:** **Meta Embedded Signup launch/cancel preflight PASS — account 1**.
- **Browser evidence:** authenticated legitimate account-1 administrator; `canCreateInbox=false`;
  `canSelfServeManagedWhatsapp=true`; normal UI path Settings → Inboxes → Add Inbox → WhatsApp Business → Coexistence;
  real Facebook OAuth popup launched for WhatsApp Business App onboarding; popup was cancelled before any number selection
  or onboarding completion; no onboarding persistence POST occurred.
- **Zero-delta evidence:** account-scoped `Channel::Whatsapp` 1 → 1, `Inbox` 1 → 1, `Bloomwire::WhatsappSetup` 1 → 1;
  global counts remained 1 / 1 / 1; Contact 6 → 6; Conversation 6 → 6; Message 116 → 116; Sidekiq retry 0 → 0; Sidekiq
  dead 49 → 49; relevant application requests had no 5xx.
- **No mutation / no exposure:** no credential, subscription, callback, routing mapping, contact, conversation, message,
  inbox, channel, or setup mutation occurred; no secret or full identifier was recorded.
- **Boundary:** this is **not Gate B PASS**, not Embedded Signup completion PASS, not new Coexistence inbox creation or
  routing proof. Full Gate B / Real Meta Coexistence certification remains **BLOCKED / DEFERRED** because no second
  distinct controlled WhatsApp Business number is available. **17F.2B remains NOT STARTED**. The existing WhatsApp fixture
  remains do-not-touch; the popup preflight must not be rerun for this docs-only PR.

### Phase 17F.2A — Managed WhatsApp onboarding entry restoration — MERGED + DEV PASS for UI/runtime scope (PR #122, merge SHA `6894d93459cdba0fbc503a7d68b4f54b42a54571`)
- **Branch / merge / deploy:** product branch `fix/bloomwire-phase-17f2a-whatsapp-onboarding-entry` merged into
  `version_1` via PR #122 at `6894d93459cdba0fbc503a7d68b4f54b42a54571` after exact-head review of
  `eb01e0f44c9b5c96f905dfb37230a72d830c3853`. DEV deploy run `28699117487` completed successfully for
  `version_1` / `6894d93459cdba0fbc503a7d68b4f54b42a54571`. Production untouched.
- **Scope accepted as PASS:** Phase 17F.2A product implementation = **PASS**; DEV deployment = **PASS**; Gate A =
  **PASS**; Phase 17F.2A UI/runtime scope = **DEV PASS**. This PASS is limited to restoring the managed WhatsApp
  **New Inbox** entry, eliminating the blank Add Inbox surface, preserving admin/agent authorization behavior, and
  preserving feature-OFF / stock-compatible behavior.
- **Root cause fixed:** `settings/inbox/Index.vue` previously gated the "New Inbox" button on `isAdmin && canCreateInbox`
  (managed mode ⇒ `canCreateInbox=false`, ignoring `canSelfServeManagedWhatsapp`), and `settings/inbox/ChannelList.vue`
  could render a blank `/settings/inboxes/new` surface when no channel card was permitted.
- **Fix shipped:** `Index.vue` now gates the entry as `isAdmin && (canCreateInbox || canSelfServeManagedWhatsapp)`;
  `ChannelList.vue` renders a safe explicit unavailable state plus Back action instead of blank; managed WhatsApp still
  routes to the existing wizard; agents remain denied; stock/native behavior remains compatible. No schema/migration,
  backend endpoint, mapping, duplicate wizard, per-customer webhook, Enterprise, workflow, or environment change.
- **Gate A deployed DEV evidence (owner-approved):** authenticated DEV normal navigation confirmed Settings → Inboxes,
  **New Inbox** visible for the authorized administrator, click-through to a non-blank `/settings/inboxes/new`, WhatsApp
  Business card visible, Standard + Coexistence options visible, no provider secret fields exposed, cancel/back without
  creating records, safe unavailable state instead of blank when applicable, agent denied, feature-OFF/stock-compatible
  behavior preserved, and real Meta/WhatsApp calls = **0**.
- **Real Meta Coexistence onboarding certification:** renamed/reclassified from Gate B to **Real Meta Coexistence
  onboarding certification**. Status remains **BLOCKED / DEFERRED**. After the secure DEV config update,
  `WHATSAPP_APP_ID` present = true, `WHATSAPP_CONFIGURATION_ID` present = true, and `platform_ready=true`; the remaining
  blocker is that no second distinct controlled WhatsApp Business number is available for the original new-inbox isolation
  contract. The only controlled DEV number is already connected to the existing **“Bloomwire WA Dev”** inbox. This is a
  readiness/test-fixture limitation, **not a confirmed product defect**. Do not delete, migrate, rename, detach, modify,
  or re-onboard the existing inbox/channel/setup/credentials/conversations/messages/contacts/routing mapping; do not
  bypass the unique phone-number constraint.
- **Gate B / certification resource deltas:** the two existing blank DEV public-identifier `InstallationConfig` rows were
  updated securely and no duplicate rows were created. The launch/cancel preflight made no credential, subscription,
  callback, routing mapping, contact, conversation, message, inbox, channel, or setup mutation; no new fixture was created;
  production was untouched.
- **Existing Standard inbox global-router supporting evidence:** completed on DEV against the existing **“Bloomwire WA
  Dev”** Standard inbox at Rails/Sidekiq SHA `6894d93459cdba0fbc503a7d68b4f54b42a54571` and labelled exactly
  **“Existing Standard inbox global-router supporting evidence only”**. One owner-assisted inbound text
  (`BW-STD-SMOKE-20260704T1100Z`) routed through the global webhook router to the existing masked `phone_number_id`
  (`****8541`) with one persisted target conversation/message path, zero duplicates, zero cross-account/inbox leakage,
  zero 401/no-handoff/5xx, and zero matching Sidekiq retry/scheduled jobs. One outbound reply
  (`BW-STD-SMOKE-REPLY-20260704T1108Z`) used the normal `Messages::MessageBuilder` → `SendReplyJob` path, reached
  final status `read`, retained a masked source id, and had zero duplicate/cross-account/retry/error findings. Local and
  public health remained 200, pending migrations remained false, Rails/Sidekiq SHA remained unchanged, and fixture counts
  for `Channel::Whatsapp`, `Inbox`, and `Bloomwire::WhatsappSetup` remained one each.
- **Certification boundary:** this evidence proves only that the existing Standard inbox can receive a real inbound
  WhatsApp message through the global router, send one normal outbound reply, preserve account/inbox isolation, avoid
  duplicate processing, and keep DEV operational health stable. It is **not** Coexistence signup PASS, Embedded Signup
  PASS, new inbox creation PASS, new-inbox isolation PASS, Real Meta Coexistence onboarding certification, full Gate B
  PASS, or proof that the platform is ready for customer Coexistence onboarding.
- **Future certification hard gate:** Real Meta Coexistence onboarding certification remains mandatory before production
  enablement of customer Coexistence onboarding, before the first real customer Coexistence onboarding, and before any
  claim that Bloomwire Coexistence onboarding is end-to-end certified. It remains **BLOCKED / DEFERRED** until a second
  distinct controlled WhatsApp Business number is available for the original new-inbox isolation contract; restored public
  identifiers and `platform_ready=true` are necessary evidence, not Gate B PASS.
- **17F.2B dependency:** **17F.2B remains NOT STARTED**. It must not begin until the existing full Gate B / Real Meta
  Coexistence certification passes. This docs-only status-evidence correction does **not** change that contract. Any
  future dependency change requires a separate explicit owner-approved contract-change decision and GPT-5.5 review.

### Phase 17F.2 — Guided "Add WhatsApp Inbox to Category" — DISCOVERY & CONTRACT only — MERGED (PR #121, merge SHA `ada23bc`, docs‑only)
- **Type:** DISCOVERY + IMPLEMENTATION CONTRACT (docs‑only). **Product code changed: NO.** No schema/migration · no
  frontend · no route · no workflow/env · no deploy · no production · no real Meta/WhatsApp/Shopify · **no
  implementation.** Branch `docs/bloomwire-phase-17f2-guided-inbox-discovery` off `version_1` `bb2a3d7` (verified tip).
- **What:** new `docs/bloomwire/phase-17f2-guided-inbox-category-flow-discovery.md` — a complete, code‑evidenced map of
  the existing flows (Standard + Coexistence Embedded Signup, inbox/channel creation, `Bloomwire::WhatsappSetup`,
  Team/`TeamMember`, `InboxMember`, the 17F.1 overview + Team/Inbox/Agents deep‑links, admin‑vs‑agent policies, account
  isolation, feature flags/capabilities, transaction boundaries, validation/rollback) plus a failure/rollback matrix, a
  security/authorization matrix, feature ON/OFF behavior, recommended UX/backend/frontend orchestration, the flow‑shape
  decision, partial‑completion handling, proposed slices, RED→GREEN tests, risks and non‑goals.
- **CORRECTION (owner‑observed DEV blocker — §0 of the doc):** an owner test on authenticated DEV
  (`/settings/inboxes/list`) found **NO "New Inbox" button**, and `/settings/inboxes/new` renders a **blank channel
  list** ⇒ a real business admin **cannot add a second WhatsApp inbox via the normal UI on DEV**. **Multi‑inbox backend
  support alone is NOT a product PASS**, and 17F.1 MCP validation did **not** cover the click journey *Inbox list → New
  Inbox → WhatsApp card → Standard/Coexistence*. **The managed onboarding entry journey is NOT DEV PASS.** Root cause
  (verified in source): `settings/inbox/Index.vue` gates the New Inbox entry on `isAdmin && canCreateInbox` (managed
  mode ⇒ `canCreateInbox=false`; `canSelfServeManagedWhatsapp` not even considered), and `settings/inbox/ChannelList.vue`
  filters **all** cards when `canCreateInbox=false && canSelfServeManagedWhatsapp=false` **with no safe empty state** ⇒
  blank. Effective managed capability needs admin + `BLOOMWIRE_MODE_ENABLED` + `PRIVACY_HARDENING` +
  `RESTRICT_NATIVE_WHATSAPP_SETUP` + `MANAGED_WHATSAPP_ONBOARDING` — **do not assume which DEV flag is missing; inspect
  server‑side in the later deploy phase.**
- **Key finding:** the *category launcher* can be built **without a new mapping and without a transaction that spans an
  external Meta operation** (setup runs Meta **before** one `ActiveRecord::Base.transaction`; membership is admin‑only,
  transactional, idempotent, reversible; overview surfaces partial completion). **But** the launcher is **not** the first
  slice — the onboarding **entry** must be restored first.
- **Recommendation (superseded by owner-approved status-evidence corrections):** current status correction authorizes
  documentation of the 17F.2A DEV pass, supporting smoke, secure public-identifier config update, and launch/cancel
  preflight only. **17F.2B remains NOT STARTED** and must not begin until the existing full Gate B / Real Meta Coexistence
  certification passes. Any future change to that dependency requires a separate explicit owner-approved contract-change
  decision and GPT-5.5 review.
- **17F.2A / certification split:** deployed DEV Gate A validates the 17F.2A UI/runtime scope; former Gate B is renamed
  **Real Meta Coexistence onboarding certification** and remains **BLOCKED / DEFERRED** until a second distinct controlled
  WhatsApp Business number is available. `WHATSAPP_APP_ID` and `WHATSAPP_CONFIGURATION_ID` are now present and
  `platform_ready=true`, but restored public identifiers are necessary evidence only, not customer-onboarding certification.
- **Governance corrections in PR #121:** Phase **17F.0** relabelled from "OPEN/not merged" to **Merged (PR #118, merge
  SHA `6c0ab8c`, docs-only)** here and in the implementation ledger (md + html). SESSION-LOG distinguished the
  repository `version_1` tip `bb2a3d7` from the DEV deployed runtime SHA `7bc59c7` at that time. Historical evidence
  unchanged.
- **Security:** no secrets exposed · no provider-credential mutation · no live Meta/WhatsApp/Shopify calls · no
  Enterprise code touched · docs-only.
- **Validation:** docs governance + secret scan + `git diff --check` + docs-only diff check + normal CI passed on PR #121;
  this historical entry is now superseded by the 17F.2A acceptance split and the status-evidence correction above.

### Phase 17F.1 — Read‑only "Categories & Inboxes" admin overview — MERGED (PR #119, merge SHA `7bc59c74ba5f96fc7ed394b0335dc216d4ab6529`) + DEV‑validated
- **Branch:** `feature/bloomwire-phase-17f1-category-inbox-overview` off `version_1` `6c0ab8c`. **PR:** #119 · approved
  head `024b35a56776ce4a50f7cd72137ffd79b68c9803` · **merged into `version_1` at `7bc59c74ba5f96fc7ed394b0335dc216d4ab6529`**
  (normal 2‑parent merge; parents `6c0ab8c` + `024b35a`; admin merge — branch policy `REVIEW_REQUIRED` was the only
  blocker, CI 8/8 green; self‑approve blocked by GitHub → pinned approval comment recorded) · **deployed to DEV in
  17F.1D (below).** **Type:** administrator‑only READ‑ONLY UI + safe‑DTO API (feature‑gated). **Product code changed:
  YES (gated).** **No DB migration/schema · no writes · no new Category entity · no real Meta/WhatsApp/Shopify.**
- **What:** new administrator‑only, **read‑only** "Categories & Inboxes" overview (Settings → Categories & Inboxes),
  gated by the new master‑gated feature `BLOOMWIRE_CATEGORY_ADMIN_UI` (OFF ⇒ stock: no route/page/API/nav). Composes
  **existing Chatwoot primitives only**:
  - **Backend:** `GET /api/v1/accounts/:id/bloomwire/category_inbox_overview` →
    `Api::V1::Accounts::Bloomwire::CategoryInboxOverviewController#show` (admin‑only via `check_admin_authorization?`;
    feature‑gated `head :not_found` when OFF). Safe DTO from `Bloomwire::CategoryInboxOverview`: categories (Teams) +
    their **derived** WhatsApp inboxes (by member overlap — there is **no persisted Inbox↔Team link**), safe
    staff/collaborator summaries (id + name only), relationship status, matched teams metadata, a WhatsApp badge
    (`connection_mode` standard/coexistence — the only non‑secret value read from `provider_config`) +
    `Bloomwire::WhatsappSetup#setup_status`, safe `not_configured` fallback, and per‑pair membership **drift** for
    linked rows. Ambiguous (inbox overlapping >1 team), unlinked teams, and unlinked inboxes are shown **explicitly,
    never guessed**. **Never exposes `provider_config`/tokens/secrets.**
  - **Frontend:** admin‑only Settings page (`categoryInboxes/Index.vue` + `InboxSummary.vue`) reusing
    `SettingsLayout`/`BaseSettingsHeader`/`Label`; **deep‑links** to the existing Team, Inbox, and Agents pages;
    loading / empty / error+retry states; explicit ambiguous + unlinked sections; new **opt‑in** capability
    `canAccessCategoryAdmin` (`Bloomwire::Capabilities` + `useBloomwireCapabilities`, default false), route guard
    `redirectIfCategoryAdminDisabled`, and a sidebar nav entry — all gated on the capability (feature OFF / agent ⇒ nav
    hidden + route redirects to the dashboard).
- **Permissions (backend‑enforced boundary):** admin + feature ON ⇒ 200 (all account teams/inboxes); agent ⇒ **401
  not‑authorized (no payload)**; feature OFF ⇒ **404 (any role)**. Account‑scoped (no cross‑account). Frontend hiding
  is UX only; the controller is the enforcement boundary.
- **What was NOT changed:** no schema/migration; no writes/mutation/membership‑sync/persistent mapping/new Category
  entity; no changes to contact visibility, inbox assignment, Standard/Coexistence setup controllers, native
  `/whatsapp/authorization`, or the global webhook router; Enterprise untouched.
- **Security:** **no secrets exposed** (DOM + API payload scanned clean); **no provider‑credential mutation**; **no
  live Meta/WhatsApp/Shopify calls**; **no Enterprise code touched.**
- **Validation (automated):** backend overview spec **15/15**; frontend targeted specs **24/24**; scoped
  category/capability Vitest **39/39**; curated Bloomwire RSpec **627 examples, 0 failures, 1 pending**; full Vitest
  **3661 passed**; full RuboCop **2700 files inspected, no offenses**; full ESLint **0 errors** (existing warnings
  only); docs governance + secret scan + migration/schema diff guard clean; `git diff --check` clean.
- **Runtime proof (LOCAL full stack — Rails+Vite; Chrome DevTools MCP; synthetic local‑only account):** **Admin+ON** —
  nav visible; page renders linked row with drift, ambiguous section with matched teams, unlinked section,
  Standard/Coexistence badges, setup statuses including **Not configured**, Team/Inbox editor links, and the Agents
  deep‑link. Network proof: `GET …/category_inbox_overview` returned **200** with safe DTO fields only. Agents link
  navigated to `/settings/agents/list`. Console had no application errors. Screenshot saved locally at
  `/tmp/pr119-category-inboxes-runtime.png`. **Cleanup:** synthetic account/users/inboxes/teams/setups/sessions verified
  zero; local Rails/Vite stopped; **no production · DEV untouched.**
- **Residual risks / parked:** Category↔Inbox is **derived (convention‑only)** by member overlap; a persistent
  Inbox↔Team mapping or reversible data tag remains **out of scope** and requires a separate owner‑approved design
  (per 17F.0). This slice is **read‑only**; the guided add/assign write flow is a later slice.

### Phase 17F.1D — DEV deploy + authenticated runtime validation — DONE (PASS) — deploy run `28694180364`
- **Deploy:** `deploy-dev.yml` (manual; prod hard‑blocked) deployed `version_1 @ 7bc59c7` to **dev only**
  (`env=dev`, `ref=version_1`, `run_migrations=true` — clean, 0 pending; `skip_smoke=false`; `prune=false`; postgres/redis
  volumes preserved). Run **`28694180364` SUCCESS**. Post‑deploy (independently re‑verified over SSH): rails
  `/app/.git_sha = 7bc59c74ba5f96fc7ed394b0335dc216d4ab6529`, sidekiq `/app/.git_sha = 7bc59c7`; **local health 200 +
  public health 200** (`{"status":"woot"}`); **rails + sidekiq Recreated** ("Up 2 minutes"); **postgres "Up 7 days" +
  redis "Up 11 hours" — NOT recreated (volumes preserved)**; no pending migrations; no 5xx. **Dev deployed SHA now
  `7bc59c7`** (was `4525bea`).
- **DEV flags (dev only):** `BLOOMWIRE_MODE_ENABLED=true` (already set) + `BLOOMWIRE_CATEGORY_ADMIN_UI=true` (new row).
  Runtime capability: **administrator → `canAccessCategoryAdmin=true`; agent → `false`**. Never enabled/modified in prod.
- **Authenticated DEV MCP — Admin + ON (PASS):** **Real account 1** — nav visible; page renders 2 categories + the
  ambiguous "Bloomwire WA Dev" (ready_for_webhook) in a dedicated explained section; deep‑links to Team/Inbox editors;
  **no write controls**; exactly one `GET …/category_inbox_overview [200]`; **0 console messages**; no secrets in DOM;
  service DTO secret‑scan `false`. **Synthetic DEV account (full matrix; cleaned up after)** — 7 categories, ambiguous
  section, unlinked section, **2 drift blocks**, 3 no‑inbox warnings, all 7 team names, **3 Standard / 2 Coexistence**
  badges, **all setup statuses (pending / configured / ready_for_webhook / blocked / not_configured)**, deep‑links to
  Team + Inbox + Agents editors, **read‑only (no create/edit/delete/sync)**, **isolation (no account‑1 data)**, and
  **desktop/tablet/mobile** with no horizontal overflow. Masked screenshots captured.
- **Authenticated DEV MCP — Agent + ON (PASS):** authoritative curl with a synthetic agent token → own account **401**
  `"You are not authorized to do this action"` and cross‑account **401** `"You are not authorized to access this
  account"` (both **0 overview keys**; a control request to `labels` returned 200, proving the token is valid);
  browser as agent → nav **absent**, direct route **redirected to dashboard** (0 rows, **no data flash**), in‑browser
  overview fetch **401** (no payload). Existing agent contact/inbox/setup behaviour is **unchanged** (17F.1 touches none
  of those paths).
- **Authenticated DEV MCP — Admin + feature OFF (PASS):** with `BLOOMWIRE_CATEGORY_ADMIN_UI=false` — admin overview
  endpoint **404** (empty); existing `labels/inboxes/teams/agents` endpoints **200**; browser nav **absent**, route
  **redirected**, existing Inboxes settings screen renders; **0 console errors**. Flag then **restored to `true`** and
  re‑verified at runtime (capability true; page renders 7 categories; nav visible).
- **Security / network counts (across admin, agent, feature‑OFF):** HTTP **5xx = 0** · console errors = 0 (the only
  console 401 was a deliberate agent probe fetch — the correct denial) · `graph.facebook.com` = 0 · `myshopify.com` = 0
  · overview mutation requests = 0 · `provider_config`/token/secret exposure = 0.
- **Cleanup:** synthetic DEV account + all synthetic users + temporary auth tokens removed (`SYNTH_*` counts all **0**);
  real account 1 + real admin **preserved**; DEV feature left **ON** (intended state); browser synthetic session
  cleared; **no real Meta/WhatsApp/Shopify setup created** (synthetic WhatsApp channels used `source=embedded_signup`,
  no `api_key`, `save(validate:false)` — no external calls); screenshots masked (names/emails/IDs). **Production
  untouched.**
- **Phase 17F.1 is COMPLETE. Phase 17F.2 NOT started.**

### Phase 17F.0 — Multi‑WhatsApp‑Inbox / Category Admin UI Discovery — MERGED (PR #118, merge SHA `6c0ab8c`, docs‑only)
- **Status correction (17F.2):** this entry previously read "OPEN (not merged)"; it was in fact **merged via PR #118 at
  `6c0ab8c`** (docs‑only; no deploy). Corrected here for accuracy; historical details below are unchanged.
- **Type:** DISCOVERY + PLANNING (docs‑only). **Product code changed: NO.** No migration/schema · no frontend · no
  route · no deploy · no production · no real Meta/WhatsApp/Shopify. Base `version_1` `096f619`; DEV runtime `4525bea`.
- **What:** new `docs/bloomwire/phase-17f0-multi-inbox-category-admin-ui-discovery.md` — evidence‑backed design for
  managing multiple WhatsApp inboxes, business categories/departments, and staff using existing Chatwoot primitives.
- **Key architecture conclusion:** **`Inbox` and `Team` are independent (no FK, no `team_id` on inboxes, no join
  table).** "Category/Department = Team + Inbox(es)" is **convention‑only** today (parallel `InboxMember` +
  `TeamMember`; auto‑assign already intersects `inbox ∩ team` members). **No new Category entity is needed** — DEV
  already uses Teams ("Area 1"/"Area 2") as categories. All admin‑vs‑agent boundaries are **already backend‑enforced**.
- **LOCKED Phase 17F permission model (backend‑enforced; §5a):** **Admin** — list/view/configure **every** inbox; start
  & manage the Bloomwire‑approved **Standard + Coexistence** managed setup; manage inbox members, teams/categories, and
  staff. **Agent** — list/view **only** `InboxMember`‑assigned inboxes; access only conversations/contacts reachable via
  assigned inboxes; **cannot** create a WhatsApp inbox, **cannot** access Standard/Coexistence setup, **cannot** modify
  provider/setup config, **cannot** bypass via direct routes/API. Verified in code: `InboxPolicy` (admin‑only writes;
  scope = `assigned_inboxes`), managed embedded‑signup controllers enforce `check_admin_authorization?` +
  `ensure_managed_whatsapp_self_serve!` (agent → not‑authorized even via direct API), `PermissionFilterService` +
  `ContactVisibility`. **17F.1 UI implication:** the "Categories & Inboxes" overview is **administrator‑only** and shows
  **all** account inboxes; agent operational selectors keep **assigned‑inbox‑only**; **no agent‑facing WhatsApp setup
  CTA/route**. Frontend hiding alone is **not** sufficient — these are invariants for all 17F slices.
- **Recommended UX:** **Option C (Hybrid)** — a thin Bloomwire "Categories & Inboxes" overview that **composes** and
  **deep‑links** the existing Chatwoot inbox/team/agent editors + a guided "add WhatsApp inbox → assign to
  category(team) → assign staff to both memberships" flow that closes the only real gap (membership drift).
- **Proposed slices (feature‑flagged; OFF ⇒ stock):** **17F.1 admin overview — READ‑ONLY, zero‑schema** (no writes, no
  membership sync, no orchestration; reuse existing inbox/team/agent stores + routes) · 17F.2 guided
  add‑inbox‑to‑category · 17F.3 unified staff membership · **17F.4 category↔inbox mapping — DEFERRED & NOT authorized by
  17F.0** · 17F.5 UI states/responsive · 17F.6 authenticated DEV E2E.
- **Schema governance (default):** **no schema change; no new Category model/table/entity.** 17F.1–17F.3 must use
  existing Chatwoot primitives (convention‑only). A persistent Inbox↔Team mapping or reversible data tag may be
  **considered later only if runtime evidence proves convention‑only is insufficient**, and **any migration, schema
  field, JSON metadata tag, or persistent mapping requires a separate design review + explicit owner approval — Phase
  17F.0 does not authorize it.**
- **Go/No‑Go for 17F.1:** **GO** (zero schema risk; pure composition).
- **Method:** 4 read‑only code sub‑agents + authenticated DEV admin runtime inspection (Chrome DevTools MCP, PHI masked).
  Runtime pages inspected: inbox list/settings, WhatsApp Standard/Coexistence setup, Teams, Agents, contacts, nav/IA.
  All Bloomwire gates verified ON on DEV. **No product code · no deploy · production untouched · no real Meta.**

### Phase 17E.4 — Contact ID hardening — MERGED (PR #116, merge SHA `4525bea6baf8c17315436982f0d70106508b9c57`)
- **PR:** #116 · **merged into `version_1` (tip `4525bea`)** via admin merge (branch policy required a review; CI was
  8/8 green) · **Type:** backend permission hardening (gated) + RSpec.
  **Product code changed: YES.** **No DB migration/schema · no frontend · no route · deployed to dev in **17E.4D** ·
  no production · no real Meta/WhatsApp · native `/whatsapp/authorization` + `Whatsapp.vue` + global webhook router
  untouched.**
- **What (closes the 17E.2/17E.3 deferred ID-based gaps):** routed 3 direct contact-by-id paths through the
  existing seam `Bloomwire::ContactVisibility.scope(account:, user:)` (one line each):
  1. **contact merge** — `Actions::ContactMergesController#contacts` (out-of-scope base/mergee → 404).
  2. **conversation-create** — `ConversationsController#contact` (out-of-scope contact → 404; inbox authz unchanged).
  3. **Shopify orders** — `Integrations::ShopifyController#contact` (out-of-scope → nil → `validate_contact` 422
     BEFORE any Shopify call → no egress).
- **Gate ON:** a gated agent can no longer merge/attach/fetch-orders-for an out-of-scope contact. **Gate OFF ==
  stock Chatwoot** (agent may act on any account contact). **Admin** unchanged (never narrowed). **CSAT** remains
  admin-only/protected — its product code is intentionally NOT touched.
- **Tests:** rewrote `hardening_followup_inventory_spec.rb` from characterization → hardening (**15 ex**);
  **RED-proven** — reverting the 3 controllers (git stash) fails exactly the 4 out-of-scope block cases (incl.
  Shopify `get` called twice), re-applying is GREEN. Shopify no-egress asserted (`shopify_client` never `:get`;
  `a_request(/myshopify\.com/)).not_to have_been_made`).
- **Security:** no secrets · no provider-credential mutation · no live Meta/WhatsApp · no Enterprise code touched.
- **Validation:** new **15/15**; suite (hardening + multi_inbox_runtime_e2e + contact_isolation + contact_visibility
  + shopify_controller + contact_merges_controller) **73/73**; conversations_controller regression **80/80**; RuboCop
  clean; `git diff --check` clean; no migration/schema; secret scan clean. CI **8/8 green** at head `74b4519`.
  **Deployed to dev in Phase 17E.4D; dev is now `4525bea`.**

### Phase 17E.4D — Dev Deploy + Authenticated Runtime Validation — DONE (PASS)
- **Deploy:** `deploy-dev.yml` (manual; prod hard-blocked) deployed `version_1 @ 4525bea` to **dev only**
  (`run_migrations=true` no-op — 0 pending in `3c45720..4525bea`; `prune=false`; postgres/redis volumes preserved).
  **Workflow run ID `28684004558` — SUCCESS.**
- **Post-deploy:** `/app/.git_sha = 4525bea6baf8c17315436982f0d70106508b9c57`; local + public health 200; login
  renders; rails + sidekiq up; postgres/redis reachable; **no pending migrations**; no 5xx.
- **DEV feature config:** `BLOOMWIRE_RESTRICT_AGENT_CONTACT_VISIBILITY=true` enabled on **dev only** via
  InstallationConfig (cache cleared); runtime resolves **true**; **kept enabled** (never enabled/modified in prod).
- **Authenticated runtime smoke (gate ON) — PASS.** Admin regression (existing session): dashboard, WhatsApp
  Standard + Coexistence (Available now), inbox list, conversations, contacts list/search — no 500, no secret, no
  Meta. 17E.4 targeted (synthetic agent/data; Shopify client stubbed — no real egress):
  - **contact merge:** agent in-scope 200; out-of-scope mergee → 404 (contact intact); out-of-scope base → 404
    (intact); admin cross-scope → 200.
  - **conversation-create:** agent in-scope 200; out-of-scope → 404 (0 side-effects); admin → 200.
  - **Shopify orders:** agent out-of-scope → **422 with 0 Shopify client calls (no egress)**; in-scope → 200
    (stub); admin → 200.
  - **isolation regression:** unassigned conversation direct → 401 (never 500); out-of-scope contact direct → 404
    (never 500); agent index sees only the assigned-inbox contact; admin sees all; seam agent-scope = in-scope only.
- **Evidence:** 0 console errors · 0 HTTP 5xx · 0 `graph.facebook.com` · 0 real `myshopify.com` requests · masked
  screenshot (WhatsApp Standard/Coexistence).
- **Cleanup:** all synthetic accounts/users/inboxes/contacts/conversations destroyed (0 remaining); no temp token
  files; **real data unchanged** (account 1 still 5 contacts). **No production · no real Meta/WhatsApp/Shopify.**

### Phase 17E.3D — Dev Validation Release (dev-only deploy) — DONE
- **Type:** dev deploy via `deploy-dev.yml` (manual dispatch; prod hard-blocked). Deployed `version_1 @ 3c45720`
  to **dev only** (`run_migrations=true` was a no-op — 0 pending; `prune=false`; postgres/redis volumes preserved).
- **Result:** SUCCESS — `/app/.git_sha = 3c45720204fe4c57528dfd8d1ef43f8a34674612`; local + public health 200;
  rails + sidekiq recreated + up; postgres `Up 6 days` (untouched). **Dev deployed SHA is now
  `3c45720204fe4c57528dfd8d1ef43f8a34674612` (`3c45720`)**, was `9b09f9e`. No production; no secrets printed; no
  real Meta.

### Phase 17E.3 — Owner-operated runtime E2E with mocked Meta — MERGED (PR #115, merge SHA `3c45720204fe4c57528dfd8d1ef43f8a34674612`)
- **PR:** #115 · **merge SHA `3c45720204fe4c57528dfd8d1ef43f8a34674612`** · merged into `version_1` (tip `3c45720`) · **Type:** TEST-ONLY (RSpec runtime/integration E2E).
  **Product code changed: NO.** **No DB migration/schema · no frontend · no route · no workflow/deploy · no
  production · no real Meta/WhatsApp (mocked at the seam) · native `/whatsapp/authorization` + `Whatsapp.vue` +
  global webhook router untouched.**
- **What:** two new integration specs under `app/spec/integration/bloomwire/` proving the full multi-inbox +
  customer/agent-visibility workflow end-to-end through the REAL runtime stack, Meta mocked
  (`Whatsapp::TokenExchangeService`/`PhoneInfoService`/`FacebookApiClient` + `Bloomwire::GlobalWhatsappConfig`;
  `WebMock.disable_net_connect!` blocks egress; an example asserts no `graph.facebook.com` call):
  1. `multi_inbox_runtime_e2e_spec.rb` (**22 ex**): **Flow 1** admin creates Inbox 1 (Standard) + Inbox 2
     (Coexistence) via mocked embedded signup, each mapped to its own `Channel::Whatsapp` + `Bloomwire::WhatsappSetup`,
     safe DTO (no token/api_key), non-admin forbidden; **Flow 2** inbound webhook routes pnid1→Inbox 1, pnid2→Inbox 2
     (connection_mode-agnostic), unknown + crossed pnid fail closed; **Flow 3** category agent lists/opens only its
     own inbox's conversations (401 cross-open), admin both; **Flow 4** contact isolation gate ON (list/search/show +
     sub-resource 404 + bulk label scoped; admin + gate-OFF unaffected); **Flow 5** UI-sanity-at-API (inbox list
     scoped per agent).
  2. `hardening_followup_inventory_spec.rb` (**5 ex, 1 pending**): characterizes the KNOWN, DEFERRED 17E.2 gaps.
- **Hardening follow-up inventory (verified in the mocked runtime, NOT fixed — deferred, needs separate approval):**
  with the gate ON, **contact merge** + **conversation-create** remain agent-reachable + unscoped (characterized as
  current behavior); **CSAT report** is admin-only (protected — not an agent vector); **Shopify orders** is
  statically reachable + unscoped but outside the mocked runtime (needs an integration hook + external stub) —
  documented, pending. No NEW/unexpected leak beyond the documented 17E.2 set; a CONTROL example asserts the gate is
  active (enumeration path still closed).
- **Not changed:** no product code (test-only); admin visibility; conversation/inbox scoping; the global webhook
  router; native WhatsApp; DB schema; frontend.
- **Security:** no secrets (all fake) · no provider-credential mutation · no live Meta/WhatsApp (mocked) · no
  Enterprise code touched.
- **Validation:** new specs **27 examples, 0 failures, 1 pending**; regression (contact_isolation, contact_visibility,
  multi_whatsapp_inbox_category_contract, whatsapp_router, whatsapp_inbound_e2e, embedded_signups,
  coexistence_embedded_signups) = **109 examples, 0 failures, 1 pending**; RuboCop clean; `git diff --check` clean;
  no migration/schema; secret scan clean. **No deploy · no production · no real Meta · dev remains `9b09f9e`.**

### Phase 17E.2 — Contact isolation & UI/permission polish — MERGED (PR #114, merge SHA `d98f7d8080fb4bd7f7e46745b7f6ac373b798ade`)
- **PR:** #114 · **merge SHA `d98f7d8080fb4bd7f7e46745b7f6ac373b798ade`** · merged into `version_1` (tip `d98f7d8`) · **Type:** backend permission
  fix (gated) + RSpec. **Product code changed: YES.** **No DB migration/schema · no frontend · no route · no
  workflow/deploy · no production · no real Meta/WhatsApp · native `/whatsapp/authorization` + `Whatsapp.vue` +
  global webhook router untouched.**
- **Decision (resolves the 17E.0/17E.1 caveat):** a business **agent** may only list/search/open contacts
  **reachable through their assigned inboxes** (via `contact_inboxes`); **admins see all**; a **shared** contact
  (contact_inbox in ≥2 inboxes) is visible to agents of any of those inboxes; conversation isolation remains the
  primary enforcement. **Gated** by the new `BLOOMWIRE_RESTRICT_AGENT_CONTACT_VISIBILITY` toggle (master
  AND-gated) — **OFF == stock Chatwoot** (agents see all contacts), so the invariant is preserved.
- **What changed (backend, gated):**
  1. New gate `Bloomwire::Features.restrict_agent_contact_visibility?` (+ `BLOOMWIRE_RESTRICT_AGENT_CONTACT_VISIBILITY`).
  2. New single seam `Bloomwire::ContactVisibility.scope(account:, user:)` — `account.contacts` for admin/stock;
     for a gated agent, `where(id: contacts.joins(:contact_inboxes).where(inbox_id: assigned).select(:id))`
     (subquery, distinct-safe, composes with sort/paginate/includes).
  3. Routed every agent-facing contact READ path through the seam: `ContactsController#index/search/active/show`
     (+ `update/avatar/destroy_custom_attributes` via `fetch_contact`), `Contacts::FilterService#base_relation`,
     global `SearchService#filter_contacts`, and `contacts/base_controller#ensure_contact` (notes/labels/
     attachments/conversations/contact_inboxes sub-resources → 404 for out-of-scope).
  4. **PR #114 review blocker fix** — routed the **bulk contact WRITE path** through the seam too.
     `BulkActionsController#enqueue_contact_job` now filters `ids` through `Bloomwire::ContactVisibility.scope`
     BEFORE enqueueing `Contacts::BulkActionJob`, so a gated agent can no longer bulk **add/remove labels** on an
     out-of-scope `contact_id`. Out-of-scope IDs are dropped (silently ignored, matching stock `where(id:)` skip
     behaviour); admins and gate-OFF pass IDs through unchanged; **delete stays admin-only** via the existing
     `authorize(Contact, :destroy?)`. Unsafe raw IDs never reach the async job.
- **Not changed:** admin visibility; conversation/inbox scoping; the global webhook router; native WhatsApp;
  DB schema; frontend. **No new category entity; no duplicate contact/chat store.**
- **Known limitation (documented, deferred):** direct ID-based access via **contact merge**, **CSAT report**
  contact inclusion, **Shopify** integration, and the **conversation-create** contact lookup are NOT scoped in
  this phase — they are mutations/reports/integrations requiring a known contact_id (not enumeration) and are
  lower-risk than the list/search enumeration this phase closes. Export/import remain **admin-only** (safe).
  **Bulk contact label add/remove is now scoped (PR #114 review blocker fix, item 4 above) and is no longer an
  open gap.**
- **Security:** no secrets · no provider-credential mutation · no live Meta/WhatsApp · no Enterprise code touched.
- **Validation:** new `contact_visibility_spec` 5/5 + `contact_isolation_spec` **20/20** (was 13/13; +7 bulk-action
  cases); bulk-path regression `bulk_actions_controller_spec` + `contacts/bulk_action_service_spec` +
  `contacts/bulk_action_job_spec` + `contacts_controller_spec` = **76/76**; **RED proof** for the blocker:
  reverting the controller (via `git stash`) fails exactly the 3 "does-not-mutate-B" cases (B is mutated),
  re-applying is GREEN. RuboCop clean; `git diff --check` clean; no migration/schema; secret scan clean.
  **No deploy · no production · dev remains `9b09f9e`.**

### Phase 17E.1 — Multiple WhatsApp Inbox backend contract tests — MERGED
- **PR:** #113 · **merge SHA** `5df9f9d74a59057e099e82c1e5471bfff0c8e449` · **Status:** merged into `version_1`
  (final tip `5df9f9d`). **Type:** TEST-ONLY (RSpec).
  **No product code · no DB migration/schema · no route · no frontend · no workflow/deploy · no production · no
  real Meta/WhatsApp calls (all stubbed).**
- **What:** turns the 17E.0 discovery ("one account can own multiple WhatsApp inboxes") into regression-locked
  backend contract tests. Extended 5 specs + 1 new spec:
  1. **Standard + Coexistence service specs** — two different numbers → two distinct `Channel::Whatsapp` +
     `Inbox` + `Bloomwire::WhatsappSetup` under one account; duplicate `phone_number` → `:phone_number_taken`;
     duplicate `phone_number_id` → `:phone_number_id_conflict` (second channel rolled back); coexistence keeps
     `connection_mode=coexistence`.
  2. **Standard + Coexistence request specs** — admin can register two numbers as two inboxes; duplicate → 422.
  3. **Router spec** — two numbers in one account each resolve to their own inbox; unknown pnid → nil; crossed
     pnid/display → fail-closed; routing is connection_mode-agnostic (Standard + Coexistence coexist).
  4. **NEW category contract spec** — Category = Team + Inbox; ConversationFinder + ConversationPolicy prove a
     category agent lists/opens ONLY their inbox (admin sees both); team-filtered assignment rejects a
     cross-category (team-2-only) assignee.
- **Product code changed?** **No — test-only.** All new tests pass against existing `version_1` code, confirming
  the contract needs no fix. (Contacts-isolation caveat is intentionally NOT addressed here — deferred to 17E.2.)
- **Validation:** targeted `rspec` (6 files) = **73 examples, 0 failures**; RuboCop clean; `git diff --check` clean.
- **Security:** no secrets · no provider-credential mutation · no live Meta/WhatsApp (all stubbed) · no Enterprise
  code touched. **No deploy · no production · dev remains `9b09f9e`.**

### Phase 17E.0 — Multiple WhatsApp Inbox per Account discovery + ADR — MERGED
- **PR:** #112 · **merge SHA** `83496896fcc7bcaa6ca076dbd2f346ee5eb4f7bc` · **Status:** merged into `version_1`
  (final tip `83496896`). **Type:** docs-only discovery + ADR-0009. **No app code · no tests · no route · no DB
  migration/schema · no workflow/deploy · no production · no real Meta/WhatsApp calls.**
- **What:** locks the Bloomwire **multiple WhatsApp inbox per account** business model before the 17E hardening
  slices — `docs/bloomwire/whatsapp-multi-inbox-discovery.md` (verdict + evidence + caveats + phased plan) and
  `projects/bloomwire-chatwoot-platform/docs/adr/0009-multi-whatsapp-inbox-category-model.md`.
- **Verdict:** **SUPPORTED** — one account can already own multiple WhatsApp inboxes/numbers with no code change.
  Services create a new `Channel::Whatsapp` + `Inbox` + `Bloomwire::WhatsappSetup` per call and block only a
  **duplicate `phone_number` / `phone_number_id`** (globally unique); there is **no per-account WhatsApp
  uniqueness**; `canSelfServeManagedWhatsapp` is a **role/managed-mode** guard, **not** count-based, so the
  WhatsApp card never disappears after the first inbox; the global router resolves inbound by `phone_number_id`
  → one setup → its own inbox (fail-closed).
- **Model:** **Category = Team + Inbox**; WhatsApp number = `Channel::Whatsapp` + `Inbox` + `Bloomwire::WhatsappSetup`;
  employee = `User`/agent; category staff = TeamMembers + InboxMembers; message = `Conversation`; assignment =
  `assignee_id` / `team_id`. Native teams/inbox-members/round-robin/team-filtered assignment already express it.
- **Caveats recorded:** (1) **contacts visibility** is account-wide in stock Chatwoot (conversations/inboxes are
  backend-scoped per agent, but the contacts list/search is not) — a cross-category contact-record leak, decision
  deferred to 17E.2; (2) **no automated tests** yet for the multi-inbox-per-account path (17E.1).
- **Next phases:** 17E.1 backend contract tests · 17E.2 UI/permission + contacts-isolation decision · 17E.3
  owner-operated runtime E2E (mocked Meta) before customer go-live.
- **Security:** no secrets exposed · no provider-credential mutation · no live Meta/WhatsApp calls · no Enterprise
  code touched. **No deploy · no production · dev remains `9b09f9e`.**

### Phase 17D.3 — WhatsApp Business App Coexistence frontend enablement — MERGED
- **PR:** #111 · **merge SHA** `ea305792dc83f864f8e1374ce0ca832f99f7d8f9` · **approved head** `d9810b72f707cf79ff0901c4babf1c95049b02c6` ·
  **Status:** merged into `version_1` (final tip `ea30579`) ·
  **Type:** frontend enablement (Vue wizard + Vuex action + API client + i18n + Vitest). **No backend/controller/
  service change · no DB migration/schema · no real Meta/WhatsApp calls (Meta SDK + window messaging mocked) ·
  no native `/whatsapp/authorization` or `Whatsapp.vue` change · no per-channel webhook override · no app-side
  duplicate chat storage · no secrets / no manual-credential UI · no deploy · no production.**
- **Why:** Phase 17D.2 proved the webhook path is coexistence-safe (merged, `4a57564`); this slice flips the
  Coexistence card in `BloomwireWhatsapp.vue` from **disabled / "Coming soon"** to a usable flow wired to the
  dedicated Phase 17D.1 endpoint, so a customer can connect an **existing** WhatsApp Business App number.
- **What changed (frontend only):**
  1. **Coexistence card enabled.** Removed the disabled/"Coming soon" state; the card is now selectable (teal
     "Available now" badge + "Connect existing number" CTA). Its prerequisites list is unchanged.
  2. **New flow, shared form.** A `flow` = `standard | coexistence` ref reuses the same credential-free
     Embedded-Signup form + `useWhatsappEmbeddedSignup` composable; on `FINISH` /
     `FINISH_WHATSAPP_BUSINESS_APP_ONBOARDING` it submits only the safe fields (`code`, `business_id`,
     `waba_id`, `phone_number_id`).
  3. **Dedicated endpoint.** New API method `WhatsappChannel.createBloomwireCoexistenceEmbeddedSignup` →
     `POST /api/v1/accounts/:id/bloomwire/whatsapp/coexistence_embedded_signup`, via new Vuex action
     `inboxes/createBloomwireWhatsAppCoexistenceEmbeddedSignup` (same safe-DTO contract as Standard).
  4. **Standard unchanged.** Register New Number still posts to `…/bloomwire/whatsapp/embedded_signup` via
     `createBloomwireWhatsAppEmbeddedSignup` (regression-locked by tests).
  5. **i18n.** `COEXISTENCE.STATUS` → "Available now"; added `CTA`, `CONNECT_BUTTON`, `FORM_TITLE`, `FORM_DESC`.
- **What was NOT changed:** native `/whatsapp/authorization` + `Whatsapp.vue`; role/permission guards
  (`canSelfServeManagedWhatsapp` in `ChannelFactory` / `useBloomwireCapabilities` — agents/staff still cannot
  reach WhatsApp setup); backend controller/service/routes; the webhook router/job; the data model. No new
  tables, no duplicate chat/message store.
- **Security:** **no secrets exposed** (UI never shows App Secret / Verify Token / Webhook URL / API token /
  provider_config; the payload carries only the 4 non-secret signup fields — test-asserted) · **no
  provider-credential mutation** · **no live Meta/WhatsApp calls** (SDK + `postMessage` mocked) · **no Enterprise
  code touched.**
- **Validation:** Vitest — `BloomwireWhatsapp.spec.js` 15/15, new `whatsappChannel.spec.js` 4/4, hook
  `useWhatsappEmbeddedSignup.spec.js` 10/10; regression `store/inboxes/actions` 20/20, `ChannelFactory` 9/9,
  `ChannelList` 8/8, `useBloomwireCapabilities` 9/9. ESLint clean (`--max-warnings=0`) on all changed JS/Vue;
  `inboxMgmt.json` valid JSON.
- **Residual risks / parked:** real coexistence Meta Embedded-Signup is **owner-operated E2E only** (no automated
  real-Meta); dev remains `9b09f9e` until an explicit deploy; **17C.4** verify / go-live UX still parked.

### Phase 17D.2 — WhatsApp Business App Coexistence webhook proof — MERGED
- **PR:** #109 · **merge SHA** `4a57564d7c1fbc54aeafbf9049f61b5b7a8b0795` · **approved head**
  `fbbbe14f06d6f49e5ff629b34788fd347718caf9` · **Status:** merged into `version_1` (final tip `4a57564`).
  **Type:** backend/webhook proof (specs + one minimal safe
  guard) + proof doc. **No frontend enablement · no DB migration/schema · no real Meta/WhatsApp calls (fake
  payloads only) · no native `/whatsapp/authorization` carve-out · no per-channel webhook override · no app-side
  duplicate chat storage · no secrets · no deploy · no production.**
- **Why:** prove the existing global webhook router (ADR-0005) + stock `Webhooks::WhatsappEventsJob` safely handle
  WhatsApp Business App **Coexistence** traffic before frontend enablement (17D.3). The Coexistence card stays
  **disabled / "Coming soon"** until then.
- **What (proven):**
  1. **Global router routing — safe, no change.** The router keys only on `metadata.phone_number_id` + channel
     alignment; it never inspects `connection_mode`, so a coexistence-created channel
     (`source=bloomwire_managed`, `connection_mode=coexistence`) routes identically. Wrong `phone_number_id` fails
     closed; routing is account-scoped.
  2. **`smb_message_echoes` — safe, already supported (no change).** The job routes echoes to
     `IncomingMessageWhatsappCloudService(..., outgoing_echo: true)` — the **outgoing** path — so an echo is not a
     duplicate inbound customer message; stays account/inbox-scoped; no secrets logged.
  3. **`smb_app_state_sync` — was unhandled → now safely ignored (minimal change).** Added an
     `app_state_sync_event?` guard + `handle_app_state_sync` to `Webhooks::WhatsappEventsJob`: it logs one
     redacted, content-free line and returns — **no inbound message processing, no message/conversation, no
     crash**. Echo + inbound behavior unchanged.
  4. **No duplicate storage** — no app-side chat/message tables; existing Chatwoot processing only.
- **Files:** `app/app/jobs/webhooks/whatsapp_events_job.rb` (only production change — the app-state-sync guard) ·
  `docs/bloomwire/whatsapp-coexistence-webhook-proof.md` (proof) · specs
  (`spec/services/bloomwire/webhooks/whatsapp_router_spec.rb`, `spec/jobs/webhooks/whatsapp_events_job_spec.rb`,
  `spec/support/bloomwire_whatsapp_e2e_helpers.rb`).
- **Not done (future):** **17D.3** frontend enablement (Coexistence card stays disabled until then).
- **Validation:** targeted `rspec` router + events-job = **43 examples, 0 failures**; broader webhook regression
  (router, job, PII logging, request logging, inbound e2e) = **58 examples, 0 failures**; RuboCop clean. **No real
  Meta calls** (fake payloads, no HTTP). Native flows unchanged; `BloomwireWhatsapp.vue` untouched (still disabled).

### Phase 17D.1 — WhatsApp Business App Coexistence backend contract — MERGED
- **PR:** #107 · **merge SHA** `ebdcba2831fd40330eaefd5a6dfe87f97a00b867` · **approved head**
  `67b63cdf3b5cd15c1ac0ec0271cf75d992ca1fc4` · **Status:** merged into `version_1` (final tip `ebdcba2`, after
  PR #106). **Type:** backend contract (account-scoped endpoint + service). **No frontend enablement · no DB
  migration · no real Meta/WhatsApp calls (mocked in tests) · no native `/whatsapp/authorization` carve-out · no
  per-channel webhook override · no secrets exposed · no deploy · no production.** (Dev remains at `9b09f9e`.)
- **Why:** the backend for **"Connect Existing WhatsApp Business App" (Coexistence)** — the option the 17C.3
  wizard shows **disabled / "Coming soon"**. This slice lands the endpoint + service contract only; the UI card
  stays disabled until a later frontend phase (17D.3).
- **What:**
  - **Endpoint** `POST /api/v1/accounts/:account_id/bloomwire/whatsapp/coexistence_embedded_signup`
    (`Api::V1::Accounts::Bloomwire::Whatsapp::CoexistenceEmbeddedSignupsController`), wired under the **same**
    account-scoped Bloomwire WhatsApp namespace as the 17C.2 `embedded_signup` route. Admin-only; **404/inert**
    unless native WhatsApp restricted AND `managed_whatsapp_onboarding` enabled; `Current.account`-scoped; safe
    DTO + sanitized errors. Native `/whatsapp/authorization` untouched.
  - **Service** `Bloomwire::WhatsappCoexistenceEmbeddedSignupService < Bloomwire::WhatsappEmbeddedSignupService`
    (17C.2). It **inherits the entire safe 17C.2 seam** — fail-closed readiness + encryption-before-token-storage,
    token exchange + phone info + **`subscribe_app_to_waba` only** (global router; never
    `override_waba_callback`/`subscribe_waba_webhook`/`channel.setup_webhooks`), encrypted token via
    `Bloomwire::WhatsappCredentialWriter`, non-secret `Bloomwire::WhatsappSetup` mapping — and only overrides two
    things: it marks the channel `provider_config['connection_mode'] = 'coexistence'` (source still
    `bloomwire_managed`) and adds `connection_mode: 'coexistence'` to the `channel` + `setup` sections of the safe
    DTO so Standard vs Coexistence are distinguishable without exposing any secret.
- **Not done (future slices):** **17D.2** webhook/coexistence proof; **17D.3** frontend enablement (the wizard
  Coexistence card stays **disabled/"Coming soon"** until then). No `WhatsappSetupRequest` removal.
- **Validation:** service spec (Meta stubbed — coexistence channel + `ready_for_webhook` mapping the router
  resolves; token only in provider_config; app-to-WABA subscribe, never per-channel override; fail-closed
  not-ready/encryption persist nothing) + request spec (admin allowed with `connection_mode: coexistence` on
  channel + setup; agent denied; 404 when Bloomwire OFF / onboarding OFF / native unrestricted; 422 not_ready /
  encryption; cross-account denied; body has no token/api_key/provider_config). **14 targeted examples, 0
  failures**; RuboCop clean; route resolves. **No real Meta calls** (service/client instance-doubles — no HTTP).

### Phase 17D.0 — WhatsApp Business App Coexistence discovery contract — MERGED
- **PR:** #106 · **merge SHA** `f9aeac7245bb6e9869c25233ed68377f77062e90` · **approved head**
  `1b8ae29dfb5183456548623c44e54e698fcd9994` · **Status:** merged into `version_1` (before PR #107). **Type:**
  discovery / docs only (`docs/bloomwire/whatsapp-coexistence-discovery.md`). **No code · no route · no frontend ·
  no DB migration · no real Meta/WhatsApp calls · no secrets · no deploy · no production.** (Dev remains at `9b09f9e`.)
- **Why:** lock the Coexistence backend contract (safe seam, credential/DTO boundary, global-router handoff) via an
  evidence/report-only discovery before enabling the disabled "Connect Existing WhatsApp Business App" card — so
  17D.1 could implement it without leaking credentials, duplicating messages, or weakening the native flow.
- **What:** the discovery document — current-`version_1` evidence, the intended `connection_mode=coexistence`
  contract, open questions, and the 17D.1/17D.2/17D.3 plan. No behavior change.
- **Validation:** docs-only (CI docs governance green on PR #106). No tests/code touched.

### Phase 17C.3 — Customer frontend WhatsApp connection wizard (connection-choice + number registration) — MERGED
- **PR:** #104 · **merge SHA** `bf81c7c62f5c9f8621142250e37b47e51b86ed82` · **approved head**
  `1bc432fcc127a5b78cf7c2bb6ca4c8ce4301f4bd` · **Status:** merged into `version_1` (new tip `bf81c7c`).
  **Type:** frontend feature (Vue). **No backend Ruby/routes/services/controllers change · no DB migration · no
  real Meta/WhatsApp calls (mocked in tests) · no native `/whatsapp/authorization` carve-out · no manual
  credentials UI · no "Add Agents" step · no secrets exposed · no deploy · no production.** (Dev remains at
  `9b09f9e`.)
- **Why:** the customer-facing UI on top of the 17C.2 endpoint — Settings → Inboxes → Add Inbox → WhatsApp
  Business → **choose a connection method** → register the number with Meta → ready inbox. Managed mode only;
  native flows untouched.
- **What:**
  - **Connection-choice screen (first step):** "Connect WhatsApp Channel" presents **two** options —
    (1) **Connect Existing WhatsApp Business App** (badge **Coexistence**) shown **disabled / "Coming soon"** with
    its prerequisites listed; it **never calls the backend** (no coexistence backend support yet); and
    (2) **Register New Number** (badge **Standard**, "Available now") which continues into the number-registration
    flow. Wording uses "Connect with Meta" / "Register WhatsApp number" / "Register New Number" — no "Connect
    Facebook" primary label.
  - **Capability plumbing:** `useBloomwireCapabilities` now exposes **`canSelfServeManagedWhatsapp`** — an opt-in
    capability that **defaults to FALSE** (unlike the stock-safe-true capabilities), so it only appears on an
    explicit server `true` (admin + native WhatsApp restricted + `managed_whatsapp_onboarding`); hidden in stock.
  - **Card + factory gate:** `ChannelList` shows the WhatsApp card in managed mode (even though native WhatsApp /
    inbox-creation are restricted), and `ChannelFactory` renders the new `BloomwireWhatsapp.vue` wizard **in place
    of** the native WhatsApp setup when the capability is granted. Agents (no capability) never see it.
  - **Wizard `BloomwireWhatsapp.vue`:** an optional inbox-name + WhatsApp-number **confirmation** form (NO App
    Secret / Verify Token / Webhook URL / API token / provider_config fields) → **"Register WhatsApp number" /
    "Connect with Meta"** launches Meta Embedded Signup (`useWhatsappEmbeddedSignup`) and posts **only** the
    non-secret signup credentials (code/business_id/waba_id/phone_number_id) to the 17C.2 endpoint via the new
    `inboxes/createBloomwireWhatsAppEmbeddedSignup` action + `WhatsappChannel.createBloomwireEmbeddedSignup`.
    Success renders a **safe DTO only** (inbox id/name, masked number from the backend/Meta source of truth,
    status Ready) with **Open inbox** + **Inbox settings** — and deliberately **no "Add Agents" step** (Chatwoot's
    existing inbox-agent management owns that). A customer-entered inbox name is applied best-effort via the
    existing inbox-update API (no endpoint contract change). Failures show a single sanitized generic message —
    "We couldn’t complete WhatsApp registration. Please try again or contact Bloomwire support." — never a raw
    Meta/server payload or token.
- **Not done (later slices):** **Coexistence backend** (the disabled card is UI-only until then); 17C.4
  verify/go-live UX; removal of the parked `WhatsappSetupRequest`.
- **Validation:** Vitest — `useBloomwireCapabilities` (default-false + explicit-true), `ChannelFactory` (wizard
  renders in managed mode / native otherwise / whatsapp_call unaffected), `ChannelList` (card shown only with the
  capability), and `BloomwireWhatsapp` (**choice screen: exactly two options; Coexistence disabled/coming-soon +
  8 prerequisites + never calls the backend; Register New Number continues to the form**; no credential fields;
  posts only signup credentials; success shows Open inbox + Inbox settings + **no Add-Agents route**; sanitized
  error hides raw payloads; cancel → no call; custom name → existing update API). **36 new/updated tests pass**;
  ESLint clean; i18n JSON valid. **No real Meta calls** (Meta SDK + store mocked). Native `Whatsapp.vue` and the
  native embedded-signup component are unchanged; stock behavior preserved (capability defaults false).

### Phase 17C.2 — Dedicated Bloomwire WhatsApp Embedded Signup endpoint + service — MERGED
- **PR:** #102 · **merge SHA** `84481ed1eeceadf91860f03a1515b01bb7d7abd4` · **approved head**
  `c8bd01e4b78165060539014d93a13f431dc1a12e` · **Status:** merged into `version_1` (new tip `84481ed`).
  **Type:** feature (account-scoped endpoint + service). **No DB migration · no frontend wizard · no real
  Meta/WhatsApp calls (all stubbed in tests) · no native `/whatsapp/authorization` carve-out · no
  `channel.setup_webhooks` / `override_callback_uri` · no secrets printed/returned · no deploy · no production.**
  (Dev remains at `9b09f9e`.)
- **Why:** implement the customer-side Embedded-Signup backend (ADR-0008) on the 17C.1 foundation, WITHOUT
  touching native embedded signup and WITHOUT weakening any native flow.
- **What:**
  - **Endpoint** `POST /api/v1/accounts/:account_id/bloomwire/whatsapp/embedded_signup`
    (`Api::V1::Accounts::Bloomwire::Whatsapp::EmbeddedSignupsController`). Admin-only (`check_admin_authorization?`);
    **404/inert** unless native WhatsApp is restricted AND `managed_whatsapp_onboarding` is enabled (the feature
    half of `canSelfServeManagedWhatsapp`); `Current.account`-scoped (no cross-account). Safe DTO only; sanitized
    generic error messages (never raw Meta payloads).
  - **Service** `Bloomwire::WhatsappEmbeddedSignupService`: fail-closed preflight (platform readiness via
    `GlobalWhatsappConfig#platform_ready`; **encryption required outside dev/test before any token storage**;
    code/waba present) → Meta steps (`Whatsapp::TokenExchangeService` + `Whatsapp::PhoneInfoService` +
    `FacebookApiClient#subscribe_app_to_waba` — **app-to-WABA subscription only, the GLOBAL router; never
    `override_waba_callback`/`subscribe_waba_webhook`/`channel.setup_webhooks`**) → atomic DB (a
    `source:'bloomwire_managed'` Cloud channel shell saved `validate:false` so no live `validate_provider_config`
    / no auto webhook / no template sync, then the encrypted token written via `Bloomwire::WhatsappCredentialWriter`,
    an `Inbox`, and the `ready_for_webhook` mapping via `Bloomwire::WhatsappSetupCreator`). Meta errors are
    sanitized to `:meta_error` (class-only logs) and persist nothing.
  - **Token/credential** stored ONLY in encrypted `Channel::Whatsapp#provider_config`; `Bloomwire::WhatsappSetup`
    holds only non-secret routing ids. Chatwoot remains source of truth for account/user/inbox/channel.
- **Not done (later slices):** frontend wizard (17C.3), verify/go-live UX (17C.4), manual fallback; no removal of
  `WhatsappSetupRequest`.
- **Validation:** service spec (Meta stubbed — bloomwire_managed channel + inbox + ready mapping the router
  resolves; token only in provider_config; app-to-WABA subscribe, no per-channel webhook/override; fail-closed
  not-ready/encryption/meta-error persist nothing) + request spec (admin allowed; agent denied; 404 when
  Bloomwire OFF / onboarding OFF / native unrestricted; 422 not_ready / encryption; cross-account denied; DTO has
  no token/api_key/provider_config). Native regression (embedded signup + inbox) **31 ex, 0 fail**; **full
  Bloomwire scope 700 examples, 0 failures (1 pre-existing pending)**; RuboCop clean. **No real Meta calls** (all
  stubbed via service/client doubles — no WebMock/HTTP).

### Phase 17C.1 — Backend foundation for customer WhatsApp Embedded Signup — MERGED
- **PR:** #100 · **merge SHA** `ac79a888e825f3c018924685c79c2bb47695e325` · **Status:** merged into `version_1`
  (new tip `ac79a88`; approved head `47b8b5e`). **Type:** backend foundation (capability + service + readiness).
  **No DB migration · no new store · no secrets stored/printed · no Meta/WhatsApp calls · no frontend wizard · no
  native `/whatsapp/authorization` carve-out · no deploy · no production.** (Dev remains at `9b09f9e`.)
- **Why:** first backend slice (C1 only) of the customer self-serve WhatsApp onboarding (Embedded Signup first,
  ADR-0008). Adds the seams a later wizard will use, with no behavior change to native flows.
- **What:**
  1. **New capability `canSelfServeManagedWhatsapp`** (`Bloomwire::Capabilities`) — `admin &&
     restrict_native_whatsapp_setup? && Bloomwire::Features.enabled?(:managed_whatsapp_onboarding)` (administrator
     **and** Bloomwire mode ON with native WhatsApp restricted **and** the explicit `managed_whatsapp_onboarding`
     feature enabled — which is master-gated **and privacy-dependent**, so privacy hardening is required too).
     Mutually-exclusive counterpart of `canManageNativeWhatsappSetup`; agents → false; Bloomwire OFF / feature OFF
     / privacy OFF / native-not-restricted → false. Existing capabilities (`canManageNativeWhatsappSetup`,
     `canCreateInbox`, …) unchanged. _(Review Blocker 1: gate on the existing managed-onboarding feature, not just
     the native restriction.)_
  2. **New service `Bloomwire::WhatsappSetupCreator`** — creates/updates the internal **non-secret**
     `Bloomwire::WhatsappSetup` router mapping (account/inbox/channel/phone_number_id/waba_id/display, status
     `ready_for_webhook`) for an **already-existing** channel+inbox. Accepts only explicit non-secret inputs
     (**no api_key/token/provider_config** — raises on such kwargs); idempotent per `channel_whatsapp_id`;
     fails closed (safe symbol errors) on cross-account inbox/channel, missing `phone_number_id`, or a
     `phone_number_id` already claimed by another channel. **When `ready_for_webhook`, it also enforces
     router handoff-safety** (mirrors `WhatsappRouter.channel_aligned_with_payload?`): Cloud (`whatsapp_cloud`)
     provider + `provider_config['phone_number_id']` match + `channel.phone_number == "+<display>"`, else
     `:unsupported_provider` / `:phone_number_id_mismatch` / `:display_phone_number_mismatch` (no value leaked) —
     so no "ready" row the global router would refuse is ever persisted. _(Review Blocker 2.)_ Creates **no**
     account/user/inbox/channel; **no** Meta call; never mutates `provider_config`.
  3. **Readiness:** `WHATSAPP_CONFIGURATION_ID` is now a **presence-only** Embedded-Signup prerequisite in
     `Bloomwire::GlobalWhatsappConfig` — missing → named blocker ("WHATSAPP_CONFIGURATION_ID is missing") + gates
     `platform_ready`; surfaced on the 17B page as Present/Missing (value never shown; it is not a secret). App
     Secret / verify token remain presence-only, values never rendered.
- **Not done (out of C1 scope):** no dedicated embedded-signup endpoint, no token exchange, no Meta API client
  calls, no app-to-WABA subscription, no frontend wizard, no Channel::Whatsapp/Inbox creation here, no manual
  fallback, no native `/whatsapp/authorization` carve-out, no `channel.setup_webhooks`.
- **Validation:** capability specs (feature ON→admin true when native restricted, feature OFF→false, privacy OFF→
  false, agent→false, OFF→stock, native caps not weakened) + `WhatsappSetupCreator` specs (create/idempotent/
  cross-account-reject/missing-pnid/pnid-conflict/**router-alignment: unsupported-provider + pnid-mismatch +
  display-mismatch fail closed**/no-secret/router resolves) + readiness specs (configuration_id present→no blocker,
  missing→blocker+not-ready). **Full Bloomwire scope 683 examples, 0 failures (1 pre-existing pending)**; RuboCop
  clean. Regression: SuperAdmin Global Config stays read-only; native `/whatsapp/authorization` stays blocked under
  managed restrictions; router + setup #1 unchanged.

### Phase 17B — SuperAdmin "Global WhatsApp Config" page (read-only) — MERGED
- **PR:** #98 · **merge SHA** `6eac9faf2cf50bf9910da4ae62179c73cfb96957` · **Status:** merged into `version_1`
  (new tip `6eac9fa`). **Type:** read-only SuperAdmin UI. **No DB migration · no new store · no secrets stored ·
  no deploy · no production · no Meta/WhatsApp calls.** (Dev remains at `9b09f9e`.)
- **Why:** complete ADR-0008 by turning the post-17A read-only WhatsApp Setups surface into a clean **Global
  WhatsApp Platform Config** page (webhook front-door + Meta-app credential *status* + router + readiness +
  connected-inbox list), instead of anything resembling customer setup/provisioning.
- **What:** new `Bloomwire::GlobalWhatsappConfig` (secret-free read-only summary) drives a rebuilt setups
  `index` → **Global WhatsApp Config**: global webhook callback URL · Meta App ID (public; **required
  readiness prerequisite** — Embedded Signup needs it, so a missing `WHATSAPP_APP_ID` blocks `platform_ready`) ·
  **App Secret / verify token = Present/Missing only** · router enabled/disabled · platform readiness + named blockers ·
  **"Last webhook received: Not tracked yet"** · read-only connected-inbox list (account, inbox, masked
  phone/`phone_number_id`, setup status, readiness). Nav → "WhatsApp › Global Config".
- **Secret-storage decision (owner-approved):** there is **no encrypted global-secret store** (InstallationConfig
  is plaintext; App Secret + verify token are **ENV/ops-managed** deployment secrets, read via
  `GlobalConfigService`). PR B is therefore **read-only**: it shows **presence only** via `config_present?`,
  **never displays or saves** App Secret / verify token, adds **no plaintext storage, no migration, no new store**.
  (Future editable secrets would need a separate encrypted `Bloomwire::PlatformConfig` design/ADR — parked.)
- **Not changed / not reintroduced:** no customer provisioning, no manual "New setup mapping", no account/user/
  inbox creation, no `Bloomwire::WhatsappSetup` create/edit here; router + webhook + setup #1 unchanged. Feature
  toggles stay on the existing "Bloomwire Features" page (linked, not duplicated). `WhatsappSetupRequest` still parked.
- **Validation:** new service spec (presence-only, never leaks values, callback URL, blockers, inbox count) +
  request specs (page renders; **secrets shown Present/Missing, values never rendered even when configured**;
  non-platform-admin blocked; master-OFF hides surface). **Full Bloomwire scope = 657 examples, 0 failures (1
  pre-existing pending)**; RuboCop clean. No deploy · no production · **no Meta/WhatsApp calls** · no secrets printed.

### Phase 17A — Remove SuperAdmin customer-provisioning + manual setup-mapping UI (architecture pivot)
- **PR:** #97 · **merge SHA** `8719de2` · **Type:** removal / dead-code. **No DB migration · no table drops · no data deleted.**
- **Why:** the SuperAdmin "Provision new WhatsApp customer" flow and the standalone "New setup mapping" CRUD
  were over-engineered and duplicated Chatwoot's native account/user/inbox responsibilities. New architecture
  (see ADR-0008): **SuperAdmin WhatsApp = Global WhatsApp Platform Config only; account/user creation stays
  native (SuperAdmin → Accounts/Users); customers complete WhatsApp setup from Account Settings → Inboxes → Add
  Inbox; the internal `phone_number_id → inbox/channel` mapping remains but is created by the customer-side
  wizard (PR C), not manual Ops UI.**
- **Removed:** `bloomwire_customer_provisionings` controller/route/view + `Bloomwire::CustomerProvisioningService`;
  the `new/create/edit/update` actions + `new`/`edit`/`_form` views of `bloomwire_whatsapp_setups` (route →
  `only: [:index, :show]`); the 16C `send_owner_activation` action + `Bloomwire::BusinessOwnerActivator` + the
  "Business owner access" card (redundant — native Devise invite/reset covers owner access now that provisioning
  is gone); nav "New Provision" link + index "Provision/New mapping/Edit" links + empty-state button; obsolete
  specs. Boundary/CRUD specs refactored off `CustomerProvisioningService`.
- **Kept intact:** global webhook + `Bloomwire::Webhooks::WhatsappRouter`; `Bloomwire::WhatsappSetup`
  model+table (**router mapping** — `ready_for_webhook.where(phone_number_id:)`); encrypted
  `Channel::Whatsapp#provider_config` + `Bloomwire::WhatsappCredentialWriter`; readiness calculator; the
  read-only setups index/show/readiness/credentials surfaces (transitional → Global Config in PR B). **Existing
  setup #1 / account #1 data untouched; router still resolves it.**
- **Parked:** `Bloomwire::WhatsappSetupRequest` intake queue is **deprecated** (superseded by the PR C wizard) —
  **not removed in 17A**; kept read/update-only, table retained (future removal = a separate data-cleanup migration).
- **Validation:** new routing spec proves removed routes are absent (create/edit/update/provision/activation) while
  index/show/readiness/credentials + parked setup-requests stay routable; **full Bloomwire spec scope = 647
  examples, 0 failures (1 pre-existing pending)**; router + whatsapp_events_job regression green; RuboCop clean.
  No deploy · no production · no Meta/WhatsApp calls · no secrets · no DB drops.

### Phase 16C — Business-owner activation (set-password after provisioning)
- **PR:** #95 · **merge SHA** `9b09f9e` · **Type:** owner-only SuperAdmin/Ops action. **No DB migration.**
- **Why:** `CustomerProvisioningService` creates the business owner **confirmed with a throwaway password and no
  email**, so a provisioned owner had no way to log in. This adds the missing activation step.
- **What:** a **"Send activation email"** action on the WhatsApp **setup detail** page
  (`POST .../bloomwire_whatsapp_setups/:id/send_owner_activation`). It sends Devise **set-password (reset)
  instructions** to the setup account's **administrator(s) only** (never agents) via the new
  `Bloomwire::BusinessOwnerActivator` (mirrors `PlatformAdminInviter#send_password_setup`, best-effort/rescued).
  Owner then sets a password and signs in to the **native** Chatwoot WhatsApp inbox.
- **Reuse, not duplication:** uses native `Account#administrators` + Devise `recoverable`. Creates **no new**
  accounts/users/account_users/inboxes/conversations/messages; changes **no roles**; creates **no** `PlatformAdmin`
  grant; **no** global `BusinessOwner`; does not duplicate data. **The only intended mutation** is Devise's
  recoverable/reset-password fields (`reset_password_token` digest + `reset_password_sent_at`) on the targeted
  administrator user(s), needed to send the set-password instructions.
- **Security:** gated by the existing `/super_admin` platform-admin boundary + master-mode (`ensure_bloomwire_mode_enabled`);
  **never** exposes the reset token/password/link in UI, logs, or audit; safe audit via `AdminUserAudit`
  (field-names only); SMTP failure is rescued (no 500).
- **Validation:** service spec + request spec (admin-only targeting, authorization, master-OFF unavailable,
  no-platform-grant, no-new-records / no-role-change, safe audit, no-secret, SMTP-failure) — **15 examples, 0 failures** on the
  new specs; setups/readiness/provisioning/credentials regression green; RuboCop clean. No deploy; no Meta/WhatsApp
  calls; no secrets.
- **Files:** `app/services/bloomwire/business_owner_activator.rb` (new) · `super_admin/bloomwire_whatsapp_setups_controller.rb`
  · `config/routes.rb` · `views/super_admin/bloomwire_whatsapp_setups/show.html.erb` · specs · docs.
- **DEV runtime (2026-06-30 → 2026-07-01) — `DEV PASS` (end-to-end):** deployed `version_1 @ 9b09f9e` to dev
  (deploy run `28461253274`; rails+sidekiq `/app/.git_sha` match · health 200 local+public · 0×5xx · postgres/redis
  volumes preserved · no pending migrations). **Feature end-to-end verified on dev:** the setup-detail **"Business
  owner access"** card renders, **"Send activation email"** works and targeted the **real account administrator**
  `User #2` / `sameen@bloomwire.lk` (account #1 admin). The owner **received the email, set a password, logged in,
  and reached the native Chatwoot inbox** — confirmed. `reset_password_sent_at` was set at send-time then **cleared
  by Devise after the successful reset** (expected; `reset_password_token` also cleared = consumed). Safe audit row
  written (`action=send_owner_activation`, field-names only: `changed_fields=[]`, `blocked_fields=[]`); **no** reset
  token/password/link exposed in UI/audit/docs; **no** `PlatformAdmin` grant created by the activation (`User #2`'s
  pre-existing `owner` grant is old — **0** new grants in the last 30m/12h); roles unchanged (`User #2`=administrator;
  `sameen.android@gmail.com` / `User #50`=agent, SMTP sender/dev only, never made admin); **no** Meta/WhatsApp calls;
  **no** production deploy. SMTP verified with booleans/masked output only — no secrets printed. (Devise tokens do
  appear in Sidekiq job-arg logs for all Devise emails — pre-existing Chatwoot behavior, not 16C.)
- **Mailer root cause & fix (why the earlier block cleared):** the earlier `PASS-BUT-BLOCKED` was caused by the dev
  **global SMTP env being empty**, so stock Chatwoot `config/initializers/mailer.rb` correctly fell back to
  `:sendmail`, which had no working MTA → `Errno::EPIPE` (no delivery). Phase 15F **templated** emails worked because
  they use the **DB-backed `Bloomwire::EmailSetting`** SMTP path; Devise/16C use the **global ActionMailer (ENV)**
  path. **Fix (operational, dev only):** populated the dev global `SMTP_*` env from the owner's local
  `#PERSONAL EMAIL SETTINGS` block (`SMTP_PORT=587`, STARTTLS on) and **recreated rails + sidekiq** →
  `delivery_method=:smtp` on both. **No `Bloomwire::EmailSetting` change · no code change · no credential values
  printed · no production deploy.**

### Docs — Product framing correction
- **PR:** _pending_ · **Type:** docs-only (no code, no runtime behavior, no deploy).
- **What:** corrected the misleading "WhatsApp-first SaaS product" wording to the canonical framing —
  **Bloomwire is a managed business messaging SaaS platform built additively on the Chatwoot engine.**
  Chatwoot remains the technical engine + source of truth (accounts, users, account_users, inboxes, contacts,
  conversations, messages). **WhatsApp is the first go-to-market managed channel / current implementation
  priority — not the permanent product boundary;** future channels (SMS, Microsoft, Instagram, Telegram, …) may
  be added later without replacing the Chatwoot foundation. WhatsWay/WhatsAway = inspiration/benchmark only.
  Also corrected the ledger §1 "WhatsWay / Chatwoot-derived OSS base" wording to "built additively on the
  Chatwoot engine."
- **Files:** `docs/bloomwire/PROJECT-CONTEXT.md`, `docs/bloomwire/SESSION-LOG.md`, `AGENTS.md`, `CLAUDE.md`,
  `docs/bloomwire/implementation-ledger.md` + `.html`, `docs/bloomwire/change-log.md`.
- **Preserved invariants:** Chatwoot Accounts/Users; business owner/admin = `account_users.role administrator`;
  staff/agent = `account_users.role agent`; Bloomwire adds managed channel setup/binding/control-plane (not a
  duplicate account/user system); no global `BusinessOwner`; no duplicate conversations/messages/contacts; no
  overbuilding multi-channel now. **No code, no migration, no deploy, no secrets.**

### Phase 15F.UI — Email Templates UI Polish & Responsive Upgrade
- **PR:** #90
- **Merge SHA:** `88e07010ddd7cea743cf1f02a91b5851ee8e43ac` (merged into `version_1`)
- **Dev status:** **DEV PASS** — deployed to dev (`88e0701`), runtime QA passed 2026-06-30: responsive CSS rules
  live — **1440 = 3 columns** (library | editor | sample preview); **1280/1024 = 2 columns + sample preview
  full-width below**; **768 = stacked**. Owner-only gate intact; no migration; SMTP unchanged; no
  DNS/SMTP/WhatsApp/Meta changes; no secrets.
- **Type:** Owner-only SuperAdmin **UI/UX + responsive** polish for Email Settings → Email Templates.
  **CSS + view-wrapper only — no behavior, controller, model, route, or DB change.**
- **Why:** the flow worked but felt cramped/dense, the panels competed, the Send-from-Template composer sat too
  low and under-emphasised, the toolbar was cramped, the preview read like a debug area, and the 3-panel grid
  jumped straight from 3 columns to 1 at 1200px (no graceful medium/tablet reflow).
- **What changed (all in `super_admin/index.scss` + 3 ERB partials; every form/link/id/validation/button-state
  preserved):**
  - **Responsive 3 → 2 → 1 grid:** `bw-email-grid` is `library | editor | sample-preview` on desktop; at
    ≤1280px it becomes `library | editor` with the sample preview reflowing full-width below; at ≤880px it stacks.
  - **Toolbar:** search takes its own row, then category + Filter wrap below — never crowded in the narrow column.
  - **Template list:** scrollable list, hover lift, and an accent left-bar on the active row.
  - **Polished preview:** both the Sample preview and the composer's Final preview render inside an email-client
    "window" frame (`bw-preview-frame`) so they read as product previews, not a debug dump. (Same shared
    branded-email partial — preview still equals delivered email.)
  - **Prominent Send section:** a clearly separated section header ("Send a real email from this template") above
    an **accent-topped** composer card (`bw-card--composer`); the composer's form/preview split is now a
    responsive `bw-composer-grid` (2-col → 1-col ≤980px).
  - **Spacing/hierarchy:** larger panel padding + grid gaps for breathing room.
- **Not changed:** no SMTP credential/provider change; no DNS; no WhatsApp/Meta; no DB migration; no controller/
  model/route change; owner-only gate intact; CTA-label interpolation + send-feedback banner + button states
  unchanged.
- **Validation:** Bloomwire email request specs (render the templates tab + composer + previews) green
  (**53 examples, 0 failures** on the render specs); SCSS compiles (Vite build CI); **dev runtime QA passed**
  on `88e0701` (responsive grid rules live at 1440/1280/1024/768, owner-only gate intact). Before/after
  screenshots = owner-assisted (MCP browser had no authenticated owner session).
- **Scope note:** Templates tab + shared page shell/status cards only; other Email Settings tabs untouched.

### Phase 15F.6 — Email CTA Button Rendering Fix
- **PR:** #89
- **Merge SHA:** `53e3e7bffacbede7f0515ed82cffbd04c9693fca` (fast-forwarded into `version_1`)
- **Dev status:** **DEV PASS** — deployed to dev (`53e3e7b`), runtime QA passed 2026-06-30: scheme-less CTA URL
  blocked before SMTP; valid `https://` renders the email-safe purple button (absolute href); delivered HTML has
  no `[www.google.com]Accept Invitation`; text fallback `Accept Invitation: https://…`; preview == delivered.
- **Type:** Owner-only SuperAdmin email-rendering + validation bugfix (Send from Template CTA). **No DB migration.**
- **Root cause:** the template's stored `cta_url` (`{{invitation_link}}`) passed the template-level
  `cta_url_safe_scheme` validation (placeholder is allowed), but the **RESOLVED** CTA URL (after the owner fills a
  variable) was **never validated**. A scheme-less value like `www.google.com` flowed through `SendTemplateEmailService`
  to the mailer, producing a **relative `<a href="www.google.com">`**. Email clients (e.g. Gmail) neutralize a
  relative/scheme-less href in HTML email, so the styled button collapsed to raw text and the URL leaked —
  delivered as `[www.google.com]Accept Invitation` instead of a purple button.
- **What changed:**
  - **Resolved-URL validation:** new `Bloomwire::EmailTemplate.absolute_cta_url?` (requires absolute
    `http(s)://`). `SendTemplateEmailService` now **blocks before SMTP** with `invalid_cta_url` when a CTA link is
    present but not absolute — message: *"Enter a full URL starting with https:// for the button link
    (e.g. https://example.com)."* (Also blocks `javascript:`/`data:` injected via a variable value.)
  - **Email-safe button:** the shared `_branded_email.html.erb` now renders the CTA as a **table + `td bgcolor`**
    button (robust across Outlook/Gmail/Apple Mail), inline styles only, label + href HTML-escaped, and only when
    the URL is absolute — so a broken/relative button is never emitted.
  - **Preview == delivered:** the composer disables Send + shows a *"Button link must be a full URL"* block when
    the resolved link is not absolute, and the Final preview (same shared partial) hides the button — matching the
    blocked send (no fake working button).
  - **Text fallback** unchanged and correct: `Accept Invitation: https://…` (never `[url]label`).
- **Not changed:** no DB migration; no SMTP secret/credential change; no DNS; no WhatsApp/Meta; no auth/audit
  (15G.2/15G.3) behavior; CTA label interpolation (15F.2) and send-feedback UX (15F.3) preserved.
- **Validation:** model unit (`absolute_cta_url?`), service (scheme-less blocks pre-SMTP, absolute sends, no-CTA
  sends), mailer (table button + absolute href + no `[url]label`; defense-in-depth skip for non-absolute), request
  (composer block + message, valid send, preview block-state). Full Bloomwire email + 15G.2 + 15G.3 suite
  **123 examples, 0 failures**; RuboCop clean. No SMTP secret in body/logs.

### Phase 15F.3 — Email Send Feedback UX Polish
- **PR:** #86
- **Merge SHA:** `bf6aa15d8816a2276365ca6e0451e16e6023ba0c` (fast-forwarded into `version_1`)
- **Dev status:** **DEV PASS** — deployed to dev (`bf6aa15`), runtime QA passed 2026-06-30: composer-local
  success/blocked/invalid banners visible at `#bw-composer`, redirect keeps `template_id`, Email Logs success +
  blocked rows recorded, double-send guard present, no SMTP secret in any rendered HTML.
- **Type:** Owner-only SuperAdmin UX (Send-from-Template feedback). **No DB migration.**
- **Why:** After a template send the only feedback was a flash at the **top** of the page; the page appeared to
  just refresh, so the owner couldn't tell whether the email was sent, blocked, or failed.
- **What changed:**
  - **Composer-local result banner:** the "Send from Template" composer now renders a visible
    success/blocked/failed banner (`#bw-send-result`) right at the composer — success → *"Email sent
    successfully to <recipient>"*, blocked/failed → *"Email was not sent: <safe reason>"* (colour-coded by
    status; `role="status"`/`aria-live`). The global flash still shows too.
  - **Land on the composer:** `send_email` redirects to the Email Templates tab with the selected
    `template_id` **and `#bw-composer` anchor**, so the owner lands on the result without scrolling. CRUD redirects
    unchanged.
  - **Status + Email Logs link:** the banner shows the latest delivery-log status/time/recipient for the template
    and a **"View Email Logs"** link.
  - **Double-send guard:** the Send button uses `data-disable-with="Sending…"` (rails-ujs/Turbo) so a second
    click during submit is avoided.
  - **Consistent messaging:** `SendTemplateEmailService` result messages standardised to the
    "sent successfully" / "was not sent: <reason>" shape; Email Log status (success/blocked/failed) matches the
    banner. No SMTP secret or raw exception secret is ever shown (errors stay sanitized).
- **Not changed:** no DB migration, no SMTP secret/credential change, no WhatsApp/Meta, no auth/audit (15G.2/15G.3)
  behavior; existing successful send/log behavior preserved (all three outcomes still write an Email Log row).
- **Deferred follow-ups:** (a) **composer "Update preview" GET query-string hardening** (POST-based preview) →
  **Phase 15F.5** (future); (b) **Email deliverability / domain authentication** → **Phase 15F.4** (PR #87,
  report-only / docs-only); (c) optional **auth-audit polish** → **Phase 15G.4** (future).
- **Validation:** send request specs (incl. visible-result-near-composer for success/blocked/invalid, composer
  anchor, template stays selected, Email Log row, no-secret); full Bloomwire email + 15G.2 + 15G.3 suite
  **113 examples, 0 failures**; RuboCop clean.

### Phase 15F.4 — Email Deliverability + Domain Authentication (investigation, report-only)
- **PR:** _pending_
- **Merge SHA:** _pending merge_
- **Type:** **Investigation / documentation only.** No code · no DB migration · **no DNS change** · **no SMTP
  credential change** · **no production deploy** · **no WhatsApp/Meta/provider credentials touched**.
- **Why:** Email send + template UX are DEV PASS and mail is actually delivered, but messages to the owner's
  `bloomwire.lk` mailbox land in **junk/spam** instead of the inbox. This entry documents the current dev sending
  behavior, why it can be junked, and the recommended production setup. (Formalises the deliverability follow-up
  noted under Phase 15F.3; tracked separately so 15F.3 stays scoped to the Send Feedback UX.)
- **Current dev SMTP behavior (read-only, masked):** `smtp.gmail.com:587`, `login` auth + STARTTLS; SMTP username
  **and** `from_email` are both `@gmail.com` (**personal Gmail**, not Google Workspace for `bloomwire.lk`); From
  display-name is `"Bloomwire"`; no Reply-To and no Return-Path override (envelope sender = the gmail.com username).
  Password present (length only) — never printed.
- **Why it can land in junk (diagnosis):** This is **not** an SPF/DKIM/DMARC *failure*. Sending *as* `gmail.com`
  through Gmail's own authenticated servers means SPF passes, DKIM is signed `d=gmail.com`, and DMARC is aligned for
  `gmail.com` → auth passes. The spam-foldering is a **brand-identity / reputation / content** problem:
  (1) brand display-name `"Bloomwire"` on a **free `@gmail.com`** address (display-name impersonation heuristic);
  (2) branded content whose CTA/invite links point to **dev.unecast.com** (sender domain ≠ link domain; a
  low-reputation dev host) — a classic phishing signal; (3) **no sending reputation** for the `bloomwire.lk` brand
  because the brand domain is not the actual sender. _(Pending owner confirmation from the junked message's
  `Authentication-Results` / `Received-SPF` / DKIM `d=` / `From` / `Return-Path` headers.)_
- **Recommended production setup (NOT applied — requires owner DNS/provider action):**
  - **Dedicated sending subdomain:** `mail.bloomwire.lk` or `notify.bloomwire.lk`.
  - **Transactional provider:** Postmark / Resend / AWS SES / Mailgun / SendGrid / Brevo.
  - **SPF (do not replace existing):** put SPF on the **subdomain only** — `v=spf1 include:<provider> -all`; leave
    the root `bloomwire.lk` SPF untouched.
  - **DKIM:** publish the provider's DKIM selector CNAME/TXT on the subdomain.
  - **DMARC:** start `_dmarc.bloomwire.lk` `v=DMARC1; p=none; rua=mailto:dmarc@bloomwire.lk` (monitor), then tighten
    to `quarantine` → `reject` after alignment is confirmed.
  - **From == authenticated domain:** e.g. `noreply@mail.bloomwire.lk` (From domain == DKIM domain → alignment +
    brand match); set a real **Reply-To** if replies are wanted.
  - **Links:** production CTA/links use the real brand/app domain (not `dev.unecast.com`).
  - **Bounce/complaint handling:** enable provider webhooks → record into the Email Logs.
- **App send flow:** unchanged and still **PASS** — this is a deliverability/DNS/provider matter, not an app bug.
- **Impact:** **Does NOT block Phase 16 dev work** (dev mail is delivered). **Blocks production / client email
  readiness** until the DNS/provider setup above is completed.
- **Validation:** read-only SMTP-config inspection on dev (masked, no secrets printed); no code/tests changed;
  docs-only.

### Dev QA Sign-off — 2026-06-30 (owner-confirmed)
Independent dev-server runtime QA on `version_1` @ `ea3487b624d896601247fd0baf2c574e4f11820b`. Owner confirmed
receipt of both dev QA emails: **"You're invited to join QA Biz Ltd on Bloomwire"** and **"Hello there"** (CTA
"Open Globex"). Sign-off:

| Area | Status |
|---|---|
| Auth Integrity (Phase 15G.2) | **DEV PASS** |
| Auth Go-Live Guardrails (Phase 15G.3 — admin-edit audit + auth smoke) | **DEV PASS** |
| Email Settings / SMTP (Phase 15F) | **DEV PASS** |
| Email Templates UX Completion (Phase 15F.2) | **100% DEV PASS** |

- **No production deploy** was performed; **audit rows were not purged**; **no WhatsApp/Meta/provider
  credentials** were touched.
- **Phase 16 is READY to start** (all auth + email flows are DEV PASS and the email receipts are confirmed).

**Phase roadmap / numbering (authoritative):**

| Phase | Scope | Status |
|---|---|---|
| **15F.2** | Email Template UX Completion | **100% DEV PASS** (PR #84, merged `ea3487b`) |
| **15F.3** | Email **Send Feedback UX Polish** | PR #86 — **pending review/deploy** (held for review) |
| **15F.4** | Email **Deliverability + Domain Authentication** | PR #87 — **report-only / docs-only** |
| **15F.5** | **POST-based composer preview / query-string hardening** | **future follow-up** (not yet started) |
| **15G.4** | Optional **auth-audit polish** (record `type` in `blocked_fields`, trim `changed_fields` noise) | **future follow-up** |

> Note: the POST-based composer preview / query-string hardening is **Phase 15F.5** — it is **not** 15F.3
> (15F.3 is the Send Feedback UX Polish). Earlier drafts that called it "15F.3" have been corrected.

### Phase 15F.2 — Email Template UX Completion + QA Findings Polish
- **PR:** #84
- **Merge SHA:** `ea3487b624d896601247fd0baf2c574e4f11820b` (fast-forwarded into `version_1`)
- **Dev status:** **100% DEV PASS** — deployed to dev (`ea3487b`), runtime QA passed, owner confirmed receipt of
  both dev QA emails on 2026-06-30 (see "Dev QA Sign-off" below).
- **Type:** Owner-only SuperAdmin UX/correctness (Email Templates composer + send + logs). **No DB migration.**
- **Why:** Dev QA passed core flows on `ba76e21`, but Email Templates was **not 100% done** — the composer
  only generated 6 fixed inputs, the preview silently used SAMPLE data for blank variables while the real send
  sent blank (preview ≠ delivered), invalid emails were only caught by SMTP, and Email Logs showed the template
  name but not the literal sent subject. This PR closes those gaps to make Email Templates production-usable
  before Phase 16.
- **What changed:**
  - **Dynamic composer variables:** `Bloomwire::EmailTemplate#used_variables` now parses **every** `{{variable}}`
    in subject + body + CTA link (de-duplicated, custom variables supported), and the composer generates one
    input per detected variable with a humanized label (`recipient_name → Recipient name`,
    `custom_order_id → Custom order id`).
  - **One resolver for preview + send:** new `EmailTemplate#composition_for` / `#resolved_variables` /
    `#missing_variables` are the SINGLE source both the live "Final preview" and the real send use, so the
    preview equals the delivered email. Blank variables are **never** silently filled with SAMPLE data — they
    stay as visible `{{placeholders}}` and the send is blocked.
  - **Blank-on-first-load (review fix):** the composer opens with **empty** variable inputs — `SAMPLE_VARS` are
    shown only as **placeholder/helper text** (and in the separate "Sample preview"), never prefilled as real
    values. The Send button stays disabled until the owner intentionally fills every required variable, so
    sample data can never be accidentally sent.
  - **CTA button label (review fix):** the CTA **label** is now included in variable detection
    (`used_variables`), interpolation (`composition_for`), and the leftover-`{{placeholder}}` block
    (`SendTemplateEmailService`). A `{{variable}}` used **only** in the button label now generates a composer
    input, renders identically in the preview and the delivered email, and **blocks the send** if left unfilled —
    completing the "no raw `{{placeholder}}` is ever delivered" guarantee (subject/body/CTA URL unchanged).
  - **Validation (pre-send):** `SendTemplateEmailService` now blocks an **invalid recipient email** and **any
    leftover `{{placeholder}}`** (subject, body, CTA label, CTA URL) before opening SMTP (in addition to missing
    recipient / SMTP not ready), with a blocked Email Log + clear message. The composer shows an inline "fill
    these in" warning and disables Send.
  - **Email Logs:** the tab now shows the **literal sent subject** (already stored per-send) alongside
    template, recipient, status, actor, timestamp.
  - **Sample preview** (editor Panel 3) relabeled "Sample preview / Sample data only — not the send preview".
- **Template CRUD:** create / edit / duplicate / deactivate(archive) / reactivate behavior preserved; a new
  custom-variable template now flows create → save → generated input → preview → send → log.
- **Not changed:** no DB migration, no SMTP secret/credential change, no WhatsApp/Meta, no Auth-Integrity
  (15G.2) or admin-audit (15G.3) behavior. Existing successful send/log behavior preserved (now requires all
  variables filled).
- **Deferred follow-ups:** (a) the composer's "Update preview" uses a GET round-trip, so composer values appear
  in the preview URL query string — tracked as **Phase 15F.5** (POST-based preview / query-string hardening); not
  fixed here (out of scope, not risk-free). (b) optional auth-audit polish (record `type` in `blocked_fields`,
  trim `changed_fields` noise) → **Phase 15G.4**.
- **Validation:** model + service + send-request specs (incl. dynamic vars, custom vars, CTA-label vars,
  preview==send, blank-blocks, invalid-email-blocks, blank-on-first-load); full Bloomwire email + 15G.2 + 15G.3
  suite **109 examples, 0 failures**; RuboCop clean. No secrets in code/logs/specs (fake values only).
- **Phase 16 remains BLOCKED** until this PR is merged, deployed to dev, and runtime QA passes.

### Phase 15G.3 — Auth Go-Live Guardrails (audit + smoke + runbook)
- **PR:** _pending_
- **Merge SHA:** _pending merge_
- **Type:** Security/audit guardrails (SuperAdmin console + ops; one additive table; no behavior change to
  business/account roles, WhatsApp, or secrets)
- **Why:** finalize auth guardrails before go-live, building on 15G.2. The prior RCA had **no provable trail**
  of who/what mutated a user; this adds one, plus a documented login smoke and runbook rules.
- **What changed:**
  - **Audit trail:** new Bloomwire-owned table `bloomwire_admin_audit_logs` + `Bloomwire::AdminAuditLog` +
    `Bloomwire::AdminUserAudit`. Every `super_admin/users#update` records one row: `actor_id`, `target_user_id`,
    `controller`, `action`, `changed_fields` (columns changed), `blocked_fields` (auth-sensitive params that were
    submitted but stripped by 15G.2). **Field NAMES only — never values.** Auditing never breaks the request.
  - **Auth smoke:** `.github/scripts/auth-smoke.sh` — optional, operator-run dev/staging login smoke using a
    **dedicated disposable test admin**. Enforces a **host allowlist (default-deny)** — only `dev.unecast.com`
    (+ `SMOKE_ALLOWED_HOSTS` for a future staging host) is allowed; every unknown host, incl. production, is
    refused. Also refuses the owner account; password read from a file (never argv/`ps`); `SMOKE_VALIDATE_ONLY=1`
    runs just the guards; verifies sign-in + deployed `/app/.git_sha`. Not auto-wired (no test-admin secret in
    CI). Guard contract is covered by `spec/scripts/bloomwire_auth_smoke_spec.rb`.
  - **Runbook §7:** password changes only via Devise reset (never the generic Users edit), the audit
    fields/exclusions, and the auth-smoke procedure.
- **Auth fields never stored in the audit:** `password`, `password_confirmation`, `encrypted_password`,
  `reset_password_token`, `reset_password_sent_at`, raw hashes, secrets.
- **Dev runtime verification (15G.3 task 1):** dev deployed SHA `f140717…`; owner account login-ready
  (SuperAdmin, confirmed, owner active, recovery reset applied — fingerprint changed); `/super_admin/sign_in`
  = 200; the deployed code carries the 15G.2 edit-form/param protections (CI spec green on `f140717`).
- **Not changed:** no rollback, no password reset (recovery already done separately), no production change, no
  WhatsApp/Meta/provider credentials, no business/account role semantics, no Devise/secret/session config.
- **Validation:** RuboCop clean; new audit request spec (3) + 15G.2 auth-integrity (10) + user-flow (6) green;
  `bash -n` on the smoke script OK. No secrets/hashes printed (specs assert no secret value lands in the audit).
- **Migration:** `20260630000001_create_bloomwire_admin_audit_logs` (additive). **Deploy required:** Yes after
  review/merge (runs the migration); not performed here.

### Phase 15G.2 — Auth Integrity Hardening (before go-live)
- **PR:** _pending_
- **Merge SHA:** _pending merge_
- **Type:** Security hardening (SuperAdmin console; no DB data change, no deploy)
- **Why:** Forensic RCA of an owner login failure (`sameen@bloomwire.lk` rejected with "Invalid Password")
  found **no** deploy/permissions/secret cause (secret + Devise pepper stable; `grant!`/`revoke!`/`reactivate!`/
  inviter(existing)/`EnsurePlatformOwnerService` never touch user auth; no migration/seed mutates the hash). The
  **only** code path that could change an existing SuperAdmin's password was the **generic Administrate User
  edit form's password field** (a non-blank submit, e.g. **browser autofill**). This PR closes that vector.
- **What changed (minimal):**
  - `UserDashboard#form_attributes` drops **`:password`** and **`:confirmed_at`** from the **edit** form (new-user
    create still sets an initial password). The edit form no longer renders a password input.
  - `SuperAdmin::UsersController#resource_params` strips an auth-sensitive denylist **on update only** —
    `password, password_confirmation, encrypted_password, reset_password_token, reset_password_sent_at,
    confirmed_at` — defense-in-depth so the generic edit can never mutate them even if a field is force-posted.
    `:type` remains stripped in Bloomwire Mode (unchanged). Password changes go **only** through the Devise
    reset flow.
- **Auth-sensitive fields now protected from the generic Users edit:** `encrypted_password`, `password`,
  `password_confirmation`, `reset_password_token`, `reset_password_sent_at`, `confirmed_at`, `type`.
- **Not changed:** no DB data, no password reset, no rollback, no migrations, no deploy, no Devise/secret/session
  config, no platform-admin/account-role logic. New-user create + the platform-admin invite (new email) still set
  an initial password as before.
- **Security:** no secrets/hashes printed; specs compare only SHA-256 fingerprints of the stored hash.
- **Validation:** RuboCop clean; **new auth-integrity request spec (10 examples)** + regression on the related
  super_admin specs (**48 examples**) green. Tests: generic edit (name) keeps hash · force-posted password on
  update ignored (original still valid, injected rejected) · edit form renders no password field · confirmed_at
  not settable via generic update · grant/revoke/reactivate leave hash/type/confirmed_at · inviter(existing) keeps
  hash · account-role assignment leaves hash/type/confirmed_at · non-owner access unchanged.
- **Deploy required:** Yes (after review/merge; not performed here). Owner login recovery (password reset) is a
  separate, approval-gated step — **not** in this PR.

### Phase 15G.1 — Fix false-success dev deploy (stdin-consumed deploy script)
- **PR:** _pending_
- **Merge SHA:** _pending merge_
- **Type:** CI/CD bugfix (infra-only; no application runtime code)
- **Summary:** The manual Dev/Staging deploy could report **success while leaving the app on the OLD build**.
  `deploy-remote.sh` is piped to the server via `ssh … bash -s`, and `docker compose run --rm rails db:migrate`
  attached **stdin** — so it **consumed the rest of the piped script**. After `db:migrate`, bash hit EOF and
  exited `0`, silently skipping **step 4 (recreate rails+sidekiq)**, **step 5 (smoke: health + SHA verify)**, and
  step 6. The migration applied, but the running containers were never swapped and the smoke checks never ran.
- **Fix (one line):** `… run --rm -T rails bundle exec rails db:migrate </dev/null` — `-T` disables stdin/TTY
  attach and `</dev/null` guarantees the command cannot read the piped script. (`up -d` is detached and the
  smoke `exec -T` was already safe; this was the only `compose run`.)
- **Why it matters:** prevents a false-positive deploy where dev silently runs stale code; smoke now actually
  gates success (health 200 + in-container `/app/.git_sha` == target SHA).
- **Observed once on dev:** deploy of `version_1` (`3bf260f`) created the `bloomwire_email_delivery_logs` table
  but left `app-rails-1` on `fdf94d8`; caught by independent `/app/.git_sha` verification. A corrected re-deploy
  is required to actually run `3bf260f` (migration is idempotent; no rollback needed — additive table).
- **Not changed:** no application code, no migrations, no compose files, no `.env`, no secrets, no production
  path. Postgres/redis volumes untouched.
- **Security:** no secrets read or printed; no live Meta/WhatsApp calls; Enterprise untouched.
- **Validation:** `bash -n .github/scripts/deploy-remote.sh` OK; PR CI green (see PR). Runtime re-deploy is
  gated on review/merge (not performed in this PR).
- **Deploy required:** Yes — after merge, re-run Deploy Dev/Staging (`dev`, `version_1`, `run_migrations=true`).

### Phase 15F.1 — Send-from-Template composer (owner-only)
- **PR:** _pending_
- **Merge SHA:** _pending merge_
- **Type:** Feature (SuperAdmin / Bloomwire owner console; builds on Phase 15F)
- **Summary:** Added an owner-only **"Send from Template"** composer on the Email Templates tab. Discovery
  confirmed the prior "Send Test Email" button only linked to the Test Email tab (a generic sample send) — there
  was no way to fill template variables and send the rendered template. The composer exposes 9 fields (recipient,
  the 6 `{{variables}}`, plus button label/link), an **"Update preview"** round-trip that renders the final
  branded email with the entered values, and a **"Send Email"** action.
- **Review fix pass (this PR):**
  - **Delivered email now matches the preview.** A single shared partial
    (`app/views/bloomwire/email/_branded_email.html.erb`) is rendered by BOTH the composer preview AND the
    mailer, so they cannot drift. The mailer's new `template_email` sends **multipart HTML + plain-text** — the
    HTML carries the branding, CTA **button**, and footer; the text part is a fallback with the same key values.
    Placeholders are interpolated before sending; no raw `{{...}}` remains for supplied values.
  - **Per-send Email Logs.** New Bloomwire-owned table `bloomwire_email_delivery_logs` + model; every template
    send writes one row (**success / failed / blocked**) with recipient, template, status, timestamp, actor, and
    a **sanitized** error. The Email Logs tab now shows these rows (plus the latest test-email result).
  - New `Bloomwire::SendTemplateEmailService` owns the template send (preflight + enabled-gate + logging);
    `SendTestEmailService` was reverted to its original Test-Email-only role. Preflight + secret-filtering are
    now centralized on `Bloomwire::EmailSetting` (`block_reason` + `sanitize_secret`).
- **Why:** Owners need to send a real, variable-filled, on-brand email from a chosen template and audit each
  send — ahead of Phase 16 onboarding emails.
- **Honesty / safety:** Preflight + **enabled-gated** — blocks honestly (and records a `blocked` log) when the
  recipient is blank, SMTP is incomplete, or outbound email is disabled; **never fakes success**; the Send button
  is disabled until SMTP is ready. The SMTP password is never rendered, logged, or stored (errors sanitized).
- **Access:** owner-only via the existing `Bloomwire::RequiresPlatformOwner` gate on both controllers; non-owner
  platform admins and customer/business users are blocked (send + Email Logs).
- **Not changed:** no WhatsApp/Meta/provider credentials or code, no Enterprise code, no `BusinessOwner` role, no
  `users.type` for business roles, no chat/message tables, Devise/password-reset mailers untouched, no new
  dependencies, no production deploy.
- **Security:** no secrets exposed · no provider-credential mutation · **no** live Meta/WhatsApp calls (mailer
  stubbed on delivery paths; the suite makes no real SMTP connection) · Enterprise code untouched · the new log
  table never stores credentials and only stores sanitized errors.
- **Validation:** RuboCop clean on all changed Ruby; **71 examples, 0 failures** for the Bloomwire email suite,
  including: owner can send (→ success log) · non-owner blocked (send + logs) · missing recipient → blocked log ·
  incomplete SMTP → blocked log · disabled SMTP → blocked log · failed send → failed log with sanitized error ·
  HTML **and** text parts contain replaced values + CTA, no raw `{{...}}` · Email Logs renders recipient/template/
  status · password never in logs/response/HTML · final-preview round-trip uses the shared branded shell.
- **Residual:** SMTP password remains plaintext-at-rest (documented Phase 15F debt, encryption still parked);
  Office365 SMTP AUTH may still be blocked by tenant Security Defaults (a Microsoft-365 config matter, not code).
- **Migration:** `20260629000003_create_bloomwire_email_delivery_logs` (additive; new Bloomwire-owned table).
- **Runtime impact:** new owner-only UI action + new table · **Deploy required:** Yes — run the migration
  (after review/merge; not done here).

### Phase 15G — CI/CD Foundation (PR CI + manual Dev/Staging deploy)
- **PR:** _pending_
- **Merge SHA:** _pending merge_
- **Type:** CI/CD / process (infra-only; no application runtime code)
- **Summary:** Added repo-root GitHub Actions. `ci.yml` validates PRs targeting `version_1` — RuboCop,
  ESLint, Vitest, Vite asset build (`assets:precompile`), a curated Bloomwire RSpec suite (52 spec files)
  on ephemeral Postgres+Redis, a migration/schema-sync check, a docs-governance check, and a
  self-contained basic secret scan. `deploy-dev.yml` is a manual (`workflow_dispatch`) Dev/Staging deploy
  over SSH that builds the image with the exact `GIT_SHA`, optionally migrates, recreates only
  `rails`+`sidekiq` (`--no-deps`, preserving postgres/redis volumes), and runs post-deploy smoke
  (health 200, in-container SHA match, postgres/redis still Up). Remote logic lives in
  `.github/scripts/deploy-remote.sh`; full guide in [`deployment-runbook.md`](./deployment-runbook.md).
- **Why:** Safer, auditable, less-manual dev/staging deploys and consistent PR gating before Phase 16.
- **Runner:** GitHub-hosted only (Option A). No self-hosted runner this phase.
- **Not changed:** no application runtime code, no migrations, no Enterprise code, no provider/credentials,
  no production deploy path, no Docker/compose files, no `.env`. The server-local
  `docker-compose.bloomwire-production.yaml` overlay is untouched (gitignored).
- **Security:** CI reads **no** secrets and makes **no** live Meta/WhatsApp calls (specs WebMock-blocked);
  deploy credentials are per-environment GitHub Environment secrets, never printed; the SSH key is written
  `600` and removed after the run; Postgres/Redis volumes are never destroyed.
- **Validation:** YAML parse OK (`ci.yml` 8 jobs, `deploy-dev.yml` 1 job); all embedded shell + the remote
  script pass `bash -n`; the Bloomwire spec selector resolves to 52 files. Live CI/deploy runs happen on the
  PR / on first manual dispatch (after secrets are configured).
- **Residual:** `dev`/`staging` GitHub Environments + SSH secrets must be configured before the deploy
  workflow can run; `actionlint`/`shellcheck` were not available locally (validated via YAML parse + `bash -n`).
- **Runtime impact:** None (infra/docs only) · **Deploy required:** No (it enables deploys; it does not perform one).

### Phase 15F — Owner-only Email Settings (DB-backed SMTP + templates)
- **PR:** #78
- **Merge SHA:** _pending merge_
- **Type:** Feature (SuperAdmin / Bloomwire owner console)
- **Summary:** Added an owner-only `Bloomwire → Email Settings` page (Overview / Configuration /
  Email Templates / Test Email / Email Logs) inside the existing SuperAdmin shell. Two Bloomwire-owned
  tables: `bloomwire_email_settings` (DB-backed SMTP config; ENV `SMTP_*` only as bootstrap defaults) and
  `bloomwire_email_templates` (6 seeded system templates with `{{variable}}` preview + create / edit /
  duplicate / deactivate / reactivate). Preflight-validated Test Email (real send when complete, honest
  "blocked" otherwise — never fakes success).
- **Why:** Phase 16 onboarding needs configurable outbound email + reusable transactional templates owned
  by the Bloomwire Platform Owner.
- **Access:** owner-only (`Bloomwire::PlatformAdmin` active owners); platform admin/support + customer/
  business users blocked; `/super_admin` boundary unchanged.
- **Not changed:** no WhatsApp/Meta/provider credentials, no Enterprise code, no `BusinessOwner` role, no
  `users.type` for business roles, no chat/message tables, Devise/password-reset mailers untouched.
- **Validation:** model + service + mailer + request specs (52 examples, 0 failures); RuboCop clean;
  existing SuperAdmin specs regression-green (39/0). Browser QA on dev pending (post-approval).
- **Review fixes (post-#78 review):** (1) Overview tab copy made honest — it no longer implies password
  resets/transactional emails already use the DB-backed SMTP; it states Devise/password-reset is unchanged
  and transactional sending is parked. (2) System-template **keys are immutable** — `:key` is not permitted
  on update and a model validation blocks changing a system template's key (future routing depends on stable
  keys); keys are auto-generated on create. (3) CTA URL scheme validation (http/https or `{{placeholder}}`
  only) — closes the previously-flagged non-blocking CTA href concern.
- **Security:** SMTP password is **write-only** in the UI (masked, never rendered/logged/printed). No live
  Meta/WhatsApp calls (tests never send real mail). No provider-credential mutation. No Enterprise touched.
- **Residual / SECURITY DEBT:** `smtp_password` is stored **plaintext** in DB because Active Record
  encryption is not configured on this install. **Encryption-at-rest is a parked Phase 15F follow-up.**
  Also parked: transactional wiring of business-invitation/welcome/plan-change/receipt/ticket mailers to
  the DB-backed config; per-message delivery logging (Email Logs shows the last test result only).
- **Runtime impact:** New owner-only page + 2 new tables (migration). **Deploy required:** Yes (after approval).

### Phase 15E.1 — Documentation Governance Guardrail
- **PR:** #77 (docs-only; amends the Phase 15E PR)
- **Type:** Docs / process
- **Summary:** Added a mandatory **Bloomwire Documentation Governance** rule to `AGENTS.md` and
  `CLAUDE.md`, a **Documentation Governance** section (§10) + Definition of Done to the implementation
  ledger (`.md` + `.html`), and created this change log.
- **Why:** Every Bloomwire-owned change must stay transparent and documented; future agents must not
  make hidden/undocumented changes.
- **Not changed:** no runtime application code, no migrations, no Enterprise, no provider/credentials.
- **Validation:** docs-only diff; HTML self-contained + well-formed; ledger and changelog agree.
- **Residual:** none.
- **Runtime impact:** None · **Deploy required:** No

### Phase 15E — Implementation Ledger
- **PR:** #77
- **Type:** Docs
- **Summary:** Added the Bloomwire Implementation Ledger (`docs/bloomwire/implementation-ledger.md`
  + `.html`): ownership, stable baseline, phase-by-phase log (13B–15D), permission model, WhatsApp
  architecture, OSS/Enterprise stance, intentionally-not-changed list, parked/residual items,
  operational rules.
- **Why:** A clear internal reference before Phase 16 customer onboarding.
- **Baseline documented:** `4084a23eb4a83b1ee41e298811a91d52d6fb6044` (after Phase 15C).
- **Not changed:** no runtime application code, no migrations, no Enterprise, no provider/credentials.
- **Validation:** docs-only diff; HTML self-contained (no CDN/JS).
- **Residual:** none.
- **Runtime impact:** None · **Deploy required:** No

---

## Released

_(none yet — entries move here when the `version_1` line is tagged/released, with their merge SHAs.)_

---

<sub>Bloomwire Change Log · docs only, no runtime behavior · baseline `4084a23eb4a83b1ee41e298811a91d52d6fb6044`.</sub>
