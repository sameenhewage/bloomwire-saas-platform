# Bloomwire — Session Log & Agent Continuity Journal

> **New chat / new agent? Start here.** This file is the fast catch-up so context is never lost
> between sessions. It complements (does **not** duplicate) the formal phase history.
>
> **Read order for a fresh session:**
> 1. `AGENTS.md` + `CLAUDE.md` (root) and `app/AGENTS.md` + `app/CLAUDE.md` — operating rules.
> 2. **`docs/bloomwire/PROJECT-CONTEXT.md`** — what the project **is** (managed business messaging SaaS on the Chatwoot engine; WhatsApp-first to market) + durable identity/data/ops rules.
> 3. The **graphify** code graph (`app/graphify-out/graph.json`) — graph-first, auto-refreshed by git hooks.
> 4. **This file** — §A Current State, §B How we work, §C Session journal.
> 5. `docs/bloomwire/implementation-ledger.md` (+ `.html`) and `change-log.md` — full per-phase history.
> 6. `docs/bloomwire/deployment-runbook.md` — deploy/ops detail. `projects/bloomwire-chatwoot-platform/CONTEXT.md` — project contracts.
>
> **Maintenance rule (every agent):** when you finish a slice/phase, **update §A Current State** and
> **prepend a §C journal entry**. Keep §B stable. Don't paste secrets. This is the single living
> "what's happening now" doc.

---

## A. Current State  *(keep this live — update at the end of every session)*

- **`version_1` tip (repository HEAD):** `e9fcef99705eee792cf99c04baa9edc24eee880e` (`e9fcef9`) — PR #125 merged (Phase **17F.2B** Category → Add WhatsApp Inbox launcher, frontend-only) on top of PR #124 (`0c3f32d`) / PR #123 (`9fe522f`) / PR #122 (`6894d93`). The Phase **17F.3** implementation branch `feature/bloomwire-phase-17f3-guided-membership-alignment` is based on this exact tip (fail-closed base check passed) and must open a PR into `version_1`; do not merge without GPT-5.5 exact-head review.
- **Dev deployed runtime SHA:** `e9fcef99705eee792cf99c04baa9edc24eee880e` (`e9fcef9`) — deployed to DEV by manual `deploy-dev.yml` run `28732366110` (success); Rails + Sidekiq report `e9fcef9`; no pending migrations (no schema change); local + public health 200; Sidekiq retry 0 (no new); PostgreSQL + Redis preserved; production untouched. **Phase 17F.2B DEV runtime PASS** validated on this SHA (authenticated account-1 admin; launcher on both eligible rows; account-scoped existing WhatsApp wizard reached; Standard + Coexistence reused; zero membership/inbox/channel/setup/contact/conversation/message deltas; no Meta signup; **not Gate B PASS**).
- **Latest completed / merged:** **PR #125** — Phase **17F.2B** Category → Add WhatsApp Inbox launcher (frontend-only), merged at `e9fcef9`, DEV-deployed run `28732366110`, **DEV runtime PASS** (not customer-onboarding cert; not Gate B). Before it: **PR #124** — docs-only record of the **Meta Embedded Signup launch/cancel preflight PASS — account 1**, merged at `0c3f32d`; **PR #123** — docs-only 17F.2A status-evidence correction, merged at `9fe522f`; **PR #122** — Phase **17F.2A** managed WhatsApp onboarding entry restoration, merged at `6894d93`, DEV-deployed run `28699117487`, Gate A PASS for UI/runtime scope; **PR #121** (17F.2 discovery + contract, docs-only, `ada23bc`); **PR #120** (17F.1 closure docs, `bb2a3d7`); **PR #119** — Phase **17F.1** read-only "Categories & Inboxes" admin overview (product code, gated), merged at `7bc59c7` and DEV-deployed + authenticated MCP validated (PASS) in 17F.1D; **PR #118** (17F.0 multi-inbox/category discovery docs, `6c0ab8c`); **PR #117** (17E.4D dev-release governance docs, `096f619`); **PR #116** (17E.4 contact ID hardening, `4525bea`, deployed + authenticated smoke PASS on dev in 17E.4D); PR #115 (17E.3, `3c45720`); PR #114 (17E.2, `d98f7d8`); PR #113 (17E.1, `5df9f9d`); PR #112 (17E.0, `8349689`); PR #111 (17D.3, `ea30579`); PR #109 (17D.2, `4a57564`); PR #107 (17D.1, `ebdcba2`); PR #106 (17D.0, `f9aeac7`); PR #104 (17C.3, `bf81c7c`); PR #102 (17C.2, `84481ed`); PR #100 (17C.1, `ac79a88`); PR #98 (17B, `6eac9fa`); PR #97 (17A, `8719de2`).
- **In-flight / open (NOT merged) — Coexistence onboarding infinite-wait hardening + sanitized trace:** branch `fix/bloomwire-coexistence-onboarding-trace` off `version_1` `d21a243`. RCA (Part 1, read-only) = **Stage A**: customer completed the Meta flow (3 Meta webhooks → `no handoff-safe setup`, 200) but the browser got no signal that resolved `runEmbeddedSignup()` → create POST never dispatched (0 in logs) → 0 records; indefinite hang because #127's second-signal timeout only arms after the first signal. Fix (Part 3): finite state + **overall watchdog armed at launch** (180s; covers zero-signal/never-settling SDK) + bounded backend create (45s) + guaranteed teardown (`cancel()` on unmount/route) + failure UX (sanitized error, attempt-id reference, manual Retry, no auto-retry). Trace (Part 2): one `onboarding_attempt_id` browser→controller; `Bloomwire::OnboardingTrace` → allow-listed structured JSON to the app log; new admin/account-scoped/feature-gated/rate-limited `onboarding_traces` endpoint; never logs code/token/phone/ids/Meta URL. No schema; Enterprise + router + Standard flow untouched; account-1 fixture untouched; **no Meta retry**. **GPT‑5.5 CHANGES REQUIRED addressed** (2 review passes): Standard-flow restored (Coexistence-only tracer), fresh attempt id per attempt, lifecycle-safe create (AbortController + stale guard), trace endpoint rejects forbidden/sensitive keys, and **double-submit attempt ownership** (wizard-owned `attemptActive` guard → a 2nd submit during signup/create is a pure no-op; one tracer/id/signup/POST; retry mints a fresh id). **Current exact-head validation (head `181d34ecabb67f01c929281739548ecaad11f960`):** composable **20** · wizard **32** · trace service **8** · trace endpoint **25** · WhatsApp backend regression **314 examples, 0 failures** · CI **8/8 green** · unresolved review threads **0**; ESLint/RuboCop/build clean; `git diff --check` clean; no secret in diff. Open PR — **unmerged and undeployed** (awaiting fresh GPT‑5.5 exact-head review); Parts 4–6 (deploy + Meta-side state + owner-assisted controlled retry with live trace) pending. (Earlier per-pass counts in the journal below are historical snapshots.)
- **In-flight / open (NOT merged) — WhatsApp channel tile intermittently disappears:** branch `fix/bloomwire-whatsapp-tile-race` off `version_1` `8fabfc33`. **Frontend-only** deterministic-state fix for `/settings/inboxes/new`: the WhatsApp tile flickered in/out across refreshes. RCA (proven): backend deterministic (`canSelfServeManagedWhatsapp=true` 10/10), but capabilities ship only on the account-show payload; `useBloomwireCapabilities` fell back to `false` while un-hydrated (couldn't tell loading from denied) and `ChannelList.vue` had **no loading state**, so it painted the terminal "MANAGED_BY_OPS" empty surface (for a managed account WhatsApp is the only tile). Fix: `capabilitiesLoaded` signal + `ChannelList` renders **loading skeleton → error+retry → tiles**, never an empty surface during load; `accounts/get` hydration on mount; guarded `currentAccount`. Agents blocked; account context + Standard/Coexistence unchanged. TDD: `ChannelList.spec` **24/24** (10 new race cases), FE **58/58**, ESLint + build clean. Runtime: case A + 304-cache captured (session was amaya/account-21); **case B + 20 hard refreshes need the account-1 admin session** (amaya can't reach account 1). `custom_roles` 500 = separate follow-up (unrelated; not on inbox-new). Open PR — do not merge.
- **In-flight / open (NOT merged) — WhatsApp Graph API version → v25.0:** branch `fix/bloomwire-whatsapp-graph-api-v25` off `version_1` `e8717b0`. Version-only, centralized (`Whatsapp::GraphApi::DEFAULT_VERSION` / `DEFAULT_WHATSAPP_GRAPH_API_VERSION`): the Coexistence flow had inherited **v22.0** on the frontend Embedded Signup SDK (`WHATSAPP_API_VERSION` was never passed to the browser → `utils.js` fallback) and **v24.0** on outbound message/media; both + the backend onboarding client now default **v25.0**, and `dashboard_controller` now feeds `whatsappApiVersion` to the popup. Webhook router (routes by `phone_number_id`) + Enterprise calling + template `v14.0` **untouched**. TDD: FE utils RED-proven → v25.0; BE all Graph URLs `/v25.0/`; WhatsApp backend **278/0** (Enterprise call-flow pre-existing fail, unrelated). Open PR — do not merge (awaiting GPT‑5.5 review); runtime v25.0 evidence pending post-deploy.
- **In-flight / open (NOT merged) — Coexistence onboarding callback fix (Stage-B hang):** branch `fix/bloomwire-coexistence-callback-transition` off `version_1` `e8717b0`. **Frontend-only** root fix in `useWhatsappEmbeddedSignup.js`: a **bounded completion timeout** (armed once the first Meta signal arrives; default 60s) so a never-delivered second signal (FB.login `authCode` **xor** postMessage `businessData`) fails closed with a safe error instead of an infinite "Registering…" spinner — the exact cause the account‑21 onboarding hung with **zero** backend create requests. Duplicate Meta events still yield **one** create POST; reject/timeout → sanitized error + retryable form; account context preserved. TDD: composable **14/14** (single-signal timeouts RED-proven), caller **16/16**, backend coexistence **20/0**; ESLint + `git diff --check` clean; no secret; no backend/router/DB/config change; `WHATSAPP_CONFIGURATION_ID` unchanged (`0643fcdbad9c`). Open PR — do not merge (awaiting GPT‑5.5 review). Separate follow-up: `custom_roles` 500 on non-enterprise accounts.
- **In-flight / open (NOT merged):** **Phase 17F.3 — Guided TeamMember + InboxMember alignment** (product code; branch `feature/bloomwire-phase-17f3-guided-membership-alignment` off `version_1` `e9fcef9`; PR **#126**). **Scope: staff-access alignment only.** **GPT‑5.5 CHANGES REQUIRED fixes applied (server-authoritative):** the endpoint is **identity-only** — request carries only `team_id` + `inbox_id` (`user_ids` removed from strong params **and** the FE payload). `Bloomwire::CategoryInboxAlignment` **recomputes eligibility (currently-derived, unambiguous pair) + additive drift from fresh DB state inside the transaction** and adds only server-computed diffs; it **never** trusts client membership IDs (the dialog preview is display-only). Fails closed (422) for **unrelated / ambiguous / unlinked / stale** pairs; cross-account → 404. One shared algorithm extracted to `Bloomwire::CategoryInboxDerivation`, used by BOTH the overview and the alignment (overview output unchanged — 15 specs). **Atomicity boundary corrected:** membership writes are **database-atomic** (full rollback on failure); the stock `InboxMember after_create` round-robin (local Redis `LPUSH`) is **outside the DB transaction** and self-heals from `inbox.inbox_members` via `InboxRoundRobinService` (upstream callback **not modified**). No Meta/WhatsApp/HTTP/external call; no schema; no persisted Team↔Inbox mapping. **Frontend:** "Align staff access" only on a linked/derived drifted inbox for a category-admin (agents/feature-OFF/ambiguous → fail closed); Confirm sends only `{team_id, inbox_id}` with a **double-submit guard**; success refreshes the existing overview. **Validation:** backend request spec **19/0** + overview regression **15** unchanged + RuboCop clean; Vitest categoryInboxes **4 files/54** (incl. double-submit) + ESLint clean; `git diff --check` clean; no secrets; safe DTO `{id,name}` only. **17F.3 IMPLEMENTED (staff-access alignment only) — not a customer-onboarding certification; full Gate B / real Meta Coexistence certification remains required before production/customer go-live.** The existing **"Bloomwire WA Dev"** fixture must remain untouched. Do not merge · do not deploy · do not run Meta signup · do not onboard a customer — awaiting fresh GPT-5.5 exact-head re-review.
- **17B secret-storage decision (owner-approved):** no encrypted global-secret store exists (InstallationConfig is plaintext; App Secret + verify token are **ENV/ops-managed**, read via `GlobalConfigService`). PR B is **read-only presence-only** — never displays/saves secret values; **no plaintext storage, no migration, no new store**. Editable secrets = parked (future encrypted `Bloomwire::PlatformConfig` design/ADR).
- **Architecture (ADR-0008):** SuperAdmin WhatsApp = **Global WhatsApp Platform Config only** (17B builds it); account/user creation stays **native**; customers set up WhatsApp via **Account Settings → Inboxes → Add Inbox** (PR C, Embedded Signup first); the internal mapping is created by the wizard, not Ops UI. `Bloomwire::WhatsappSetupRequest` **deprecated/parked** (removed after PR C).
- **Working tree:** Phase 17F.3 implementation branch (backend service+controller+route + frontend dialog/API-client/InboxSummary/Index + specs + i18n); local untracked artifacts (PDFs, `ui-design/`) remain untouched and must not be included in the PR.
- **Next up (not started — pick with owner):**
  1. **Real Meta Coexistence certification resource:** obtain a second distinct controlled WhatsApp Business number for the original new-inbox isolation contract; do not modify the existing **“Bloomwire WA Dev”** fixture.
  2. **Coexistence go-live readiness:** after the second number exists, run the full owner-operated Real Meta Coexistence certification on DEV before production enablement or first customer Coexistence onboarding. The account-1 launch/cancel preflight is not completion, creation, or routing proof.
  3. **Deferred observability:** last-webhook-received telemetry (non-secret Redis/InstallationConfig timestamp) → surface it on the Global Config page (currently "Not tracked yet").
  4. **Prod SMTP parity (important):** populate the **production** global `SMTP_*` env — the same empty-env root cause would block prod activation/reset/invite emails (dev-only fix so far).
  5. Owner-assisted before/after screenshots for 15F.6 + 15F.UI; **Phase 15F.5** (POST preview hardening); **Phase 15F.4** (prod email deliverability, PR #87).

---

## B. How we work  *(stable conventions for this stream)*

**Branch & PR**
- One branch **per phase off `version_1`** → PR **into `version_1`**. **Never push directly** to `version_1` / `main`.
- Open PR, report URL + CI + mergeable, then **stop**. **Do not self-merge.**

**Review → merge → deploy gate**
- Owner runs an external **"GPT-5.5" review**; they relay *"APPROVED at exact SHA <sha>"*.
- **Verify head == approved SHA before merging.** If a rebase changes the head SHA, it needs a **fresh** GPT-5.5 re-review of the new SHA.
- Merge only on explicit owner approval: `gh pr merge <n> --merge --admin` (branch protection requires admin override). Docs-only PRs: same gate.

**Deploy dev** (only after merge, on owner go — see `deployment-runbook.md` for detail)
- `gh workflow run deploy-dev.yml --ref version_1 -f environment=dev -f ref=version_1 -f run_migrations=true -f skip_smoke=false -f prune=false`
- **Never:** production deploy · volume prune · DNS / SMTP-credential / WhatsApp / Meta changes · printing secrets.
- **Post-deploy verify:** `/app/.git_sha` (rails+sidekiq) == version_1 SHA · UI footer SHA matches · health 200 local+public · no pending migrations · rails+sidekiq recreated · postgres/redis preserved · 0×5xx · SMTP unchanged.

**Runtime QA (server-side, password-safe)**
- Need an authenticated owner action via HTTP → create a **temp QA owner** with `rails runner` on the server; write its password to a file **inside the container** (`chmod 600`) and **never print it**; drive with `curl` cookie-jar login. Sanctioned for HTTP QA only.
- **Cleanup after:** delete QA-created templates + delivery logs **by the temp actor's `actor_id`**, then the temp owner + its `Bloomwire::PlatformAdmin` grant (only if another active owner remains). **Preserve** audit rows, the 6 system templates, and the real owner. `shred -u` temp files.
- **Screenshots:** **owner-assisted only.** The MCP/Chrome-DevTools browser has no authenticated owner session (redirects to `/super_admin/sign_in`). **Do NOT** create a throwaway owner or handle passwords/cookies for screenshots.

**Docs governance (mandatory)** — every behavior-changing Bloomwire PR updates `change-log.md` + `implementation-ledger.md` + `.html` in the same PR; after merge, stamp the exact merge SHA + DEV PASS via a docs-only PR. Keep phase numbering consistent.

**Gotchas learned**
- `docker exec -i … rails runner -` **consumes the SSH heredoc stdin** — later commands in the same heredoc won't run. Use `docker exec … rails runner '<script>'` (no `-i`, script as arg) when more commands follow, or put the `-i` form last.
- `curl` treats `[ ]` as URL globbing → use **`curl -g`** for URLs with `compose[...]` params.
- **Two SMTP paths (don't confuse them):** (1) **global Devise/transactional** mail (password reset, 16C activation, platform-admin invite) uses **ENV `SMTP_*`** via `config/initializers/mailer.rb` — if `SMTP_ADDRESS` is blank it silently falls back to `:sendmail` (no MTA on dev → `Errno::EPIPE`, no delivery); (2) **per-account templated** email (15F) uses the **DB-backed `Bloomwire::EmailSetting`** SMTP. Fixing global mail = populate the global `SMTP_*` env (Gmail: port 587 + STARTTLS) and **recreate rails+sidekiq** (recreate, not restart, to reload `.env`). Verify with `ActionMailer::Base.delivery_method` == `:smtp` (booleans/masked; never print values).

**Infra / key paths**
- Dev SSH alias **`contabo-dev`**; containers `app-rails-1`, `app-sidekiq-1`, `app-postgres-1`, `app-redis-1`.
- `bw-*` design system + responsive grid: `app/app/javascript/dashboard/assets/scss/super_admin/index.scss` (vite entry `app/app/javascript/entrypoints/superadmin.js`; bundle at `/vite/assets/superadmin-*.css`).
- Email Settings views: `app/app/views/super_admin/bloomwire_email_settings/` (`_composer.html.erb` owns `#bw-composer`, `#bw-send-result`, `compose[...]`, `send_email` form).
- Shared branded email partial: `app/app/views/bloomwire/email/_branded_email.html.erb`. Service: `app/app/services/bloomwire/send_template_email_service.rb`. Model: `app/app/models/bloomwire/email_template.rb`.
- Specs (from `app/`): `DISABLE_ENTERPRISE=true bundle exec rspec <paths>`; lint `bundle exec rubocop --force-exclusion <files>`. CI = 8 required checks.

**Invariants** — no `users.type` for business roles · no `BusinessOwner` without design · no duplicate chat/message source of truth · no Enterprise dependency · WhatsApp-first · safe DTOs only · never expose secrets.

---

## C. Session journal  *(newest first — prepend new entries)*

### 2026-07-06 — Admin "Remove WhatsApp Inbox" (managed deprovision) (product code; open branch; NOT merged)
- **GPT‑5.5 CHANGES REQUIRED (2nd pass, reviewed `2a96f49`) — fixed:** (1) `.purge!` no longer swallows
  `RecordNotDestroyed` — a surviving inbox logs a sanitized `removal_failed` and RE-RAISES for Sidekiq retry (only a
  fresh `Inbox.exists?`=false counts as idempotent success); the `RecordNotFound` race stays a safe no-op. (2–3)
  `#prepare` verifies `perform_later` acceptance (false / not-`successfully_enqueued?` / raised → confirmed failure),
  **restores the prior routeable status** on failure (deterministic) and returns `:enqueue_failed` → controller
  **503** (retriable); 202 only for a confirmed-accepted job. (4) sanitized `removal_started`/`removal_succeeded`/
  `removal_failed` audit events. (5) Settings-level gate test (`canRemoveManagedWhatsappInbox`: capability OFF hides,
  ON+managed cloud shows). (6) real 15s timeout-abort FE test. Re-validated: service 24 · job 1 · request 8 ·
  component 11 · settings-gate 4; full WhatsApp backend regression **490/0** (1 pending); FE 64; ESLint + RuboCop +
  vite build clean; no secret in diff. New head pending push; awaiting fresh GPT‑5.5 exact-head review.
- **GPT‑5.5 CHANGES REQUIRED (1st pass, reviewed `cecac65`) — fixed:** (1–4) heavy purge moved OUT of the request into a
  dedicated idempotent job (`Bloomwire::WhatsappInboxDeprovisionJob`); the request `#prepare` now authorizes/verifies,
  blocks routing, enqueues, and returns **202 `removal_started`**; `.purge!` re-verifies state each run, uses **no
  single giant transaction** (batched per-record destroy!), and is concurrency/retry/idempotency-safe (no-op when
  gone; rescues the RecordNotFound race; lets unexpected errors propagate for Sidekiq retry). (5–6) the Remove UI is
  gated on `canSelfServeManagedWhatsapp` (same capability as onboarding; opt-in default FALSE → hidden when OFF).
  (7) the FE removal request is bounded by an `AbortController` + 15s timeout, aborted on unmount/route-leave, with a
  leftFlow guard so no late alert/emit fires. (8) success wording is now **"removal started"** (accepted async), not
  "removed". Re-validated: service 16 · job 1 · request 6 · component 10; full WhatsApp backend regression **481/0**
  (1 pending); FE 59; ESLint + RuboCop + vite build clean; no secret in diff.
- **Context:** PR #131 was GPT‑5.5 approved at `9498ce7`, merged to `version_1` (merge `a6b26e8`) and deployed to DEV
  (Rails+Sidekiq `a6b26e8`, health 200/200, no pending migrations, no new 5xx, Postgres/Redis preserved, account‑1
  1/1, account‑21 0/0/0; backend already-connected detection + served bundle verified — the authenticated
  browser-visual smoke is blocked on missing DEV admin creds). This feature is the **separate** focused PR started
  after that merge.
- **Why:** managed-mode admins cannot delete a WhatsApp inbox (stock destroy → 403 via
  `restrict_managed_provider_inbox_destroy!`). Adds a dedicated deprovision that does NOT weaken that guard.
- **Backend:** `Bloomwire::WhatsappInboxDeprovisionService` + `DELETE …/bloomwire/whatsapp/inboxes/:id` (admin-only,
  account-scoped, feature-gated 404). Block routing (`setup_status -> 'blocked'`, committed) → destroy the setup
  mapping (else orphaned) → destroy the inbox (cascades conversations/messages/contact_inboxes/members/reporting/
  webhooks + `Channel::Whatsapp`). Shared Contacts preserved. Idempotent (repeat → 404). Meta-safe: only
  `source: bloomwire_managed` channels → `teardown_webhooks` never fires. Sanitized audit; frees the local
  `phone_number_taken` guard.
- **Frontend:** admin-only "Remove inbox" action on the inbox settings page → destructive modal (title, irreversible
  warning, name, MASKED number last-4, Standard/Coexistence mode, Meta-boundary note, Cancel + red Delete); disables
  repeat clicks; safe alerts; returns to the inbox list. No full number / pnid / WABA / credential rendered.
- **Validation:** service 11 · request 6 · component 8; full WhatsApp backend regression **492/0** (1 pending); FE 57
  (removal 8 + wizard 45 + api 4); ESLint + RuboCop + vite build clean; no secret in diff. No schema/migration; stock
  destroy guard + global duplicate guard + router + Enterprise untouched; no Meta call; DEV account‑1 fixture not
  touched by tests. Branch `feat/bloomwire-remove-whatsapp-inbox` off `version_1` `a6b26e8`; open PR — do not merge
  (awaiting GPT‑5.5 exact-head review).

### 2026-07-06 — Duplicate WhatsApp-number UX (preflight + safe error mapping) + sensitive-parameter log filtering (product code; open branch; NOT merged)
- **GPT‑5.5 CHANGES REQUIRED (reviewed `fb77e55`) — 3 items fixed:** (1) **lifecycle-safe bounded preflight** —
  `attemptSeq`/`seq` + timer/abort reset established BEFORE the first await; bounded (8s) + `AbortController` (signal
  store→API→axios) aborted on unmount/route-leave; a **stale/leftFlow check runs immediately after the await, before
  creating a tracer or opening Meta** (a late preflight response can no longer open the popup after the flow left);
  `attemptActive` released on every terminal preflight path; a visible "checking" state disables the submit action;
  fails open; authoritative post-Meta guard unchanged. (2) **availability-oracle throttling** — the
  `phone_availability` endpoint is rate-limited per `(account, actor)` (20/60s) → **429**; the raw number is never
  logged; `{ status }`-only contract preserved. (3) **exact-key filtering** — replaced broad `:code`/`:phone_number`
  substring symbols with **anchored regexes** so `error_code`/`status_code`/`country_code`/`phone_number_verified`
  stay visible and `website_token` is preserved, while required sensitive keys render `[FILTERED]`. Re-validated:
  service 8 · request 9 · filter 3 · wizard **45** (+4 preflight-lifecycle); WhatsApp backend **337/0**; ESLint +
  RuboCop + vite build clean; no secret in diff. New head pending push; awaiting fresh GPT‑5.5 exact-head review.
  **The "Remove WhatsApp Inbox" feature is intentionally out of this PR — separate focused PR after #131 is
  approved+merged.**
- **Root cause (proven):** on DEV a Standard signup used a number already connected as the account‑1 fixture; the
  backend correctly returned **422 `phone_number_taken`** (safe message), but the wizard discarded the safe
  `code`/message and showed only the generic "We couldn't finish connecting WhatsApp." Separately the Meta auth
  `code` was logged unfiltered in the Rails Parameters line.
- **Fix 1 — advisory preflight:** new admin-only, account-scoped, feature-gated (404) endpoint
  `POST …/bloomwire/whatsapp/phone_availability` (`Bloomwire::WhatsappPhoneAvailability`): normalizes the typed
  number to `+<digits>` (like `Channel::Whatsapp`/`PhoneInfoService`), GLOBAL existence check (mirrors the
  authoritative unique guard), returns ONLY `{ status: available | already_connected }` (no tenant leak). Wizard
  blocks the Meta popup on `already_connected` + shows the specific warning; **fails open**; authoritative post-Meta
  guard unchanged.
- **Fix 2 — safe error-code mapping (Standard + Coexistence):** wizard maps `error.response.data.code`
  (`phone_number_taken`/`phone_number_id_conflict`/`invalid_phone_number`) to specific safe messages; else generic;
  never raw exceptions.
- **Fix 3 — copy:** "Use a number that is not already connected to another Bloomwire inbox." under the number field.
- **Fix 4 — log filtering:** added `code, auth_code, business_id, waba_id, phone_number_id, display_phone_number,
  access_token, phone_number` to `config.filter_parameters` (bare `:token` omitted to preserve `website_token`);
  verified `[FILTERED]`.
- **Validation:** service 8 · request 7 · filter 2 · wizard 41 (+9); WhatsApp backend **334/0**; ESLint + RuboCop +
  vite build clean; `git diff --check` clean; no secret in diff. No schema/migration; authoritative guard + router +
  Enterprise + account‑1 fixture untouched; no Meta retry; preflight read-only (account‑21 stays 0/0/0). Branch
  `fix/bloomwire-duplicate-number-ux-and-log-filtering` off `version_1` `209bfb0`; open PR — do not merge (awaiting
  GPT‑5.5 exact-head review).

### 2026-07-06 — Coexistence onboarding infinite-wait hardening + sanitized end-to-end trace (product code; open branch; NOT merged)
- **GPT‑5.5 CHANGES REQUIRED (2nd pass, reviewed head `4d041b5`) — remaining blocker fixed: double-submit attempt
  ownership.** `register()` mutated attempt state (tracer / attempt id / support reference / `attemptSeq` /
  `AbortController` / timer) **before** the composable's in-flight guard, so a rapid second click could mint a second id,
  bump `attemptSeq`, and supersede/abort the first valid attempt (its create/trace then suppressed as "stale"). Fix: a
  wizard-owned **`attemptActive` guard** set the instant an attempt starts (before ANY attempt-state mutation) and
  cleared only on a terminal state (success/failure/cancel/timeout/route-leave/unmount). A second submit while a signup
  OR create is active is now a **pure no-op** — exactly one tracer, one attempt id, one Meta signup launch, one create
  POST (first id); no supersede, no abort of the active attempt, no support-ref change. Manual retry after a terminal
  failure still mints a fresh id; Standard flow unchanged. RED-proven (without the guard a double-submit mints 2
  tracers). Wizard spec **29 → 32**; composable 20 · trace service 8 · trace endpoint 25; WhatsApp backend **314/0**;
  ESLint + vite build clean; `git diff --check` clean; no secret; no migration; no router/Enterprise change; **no Meta
  retry; no record mutation.** New head pending push; fresh exact-head GPT‑5.5 review requested; do not merge/deploy.
- **GPT‑5.5 CHANGES REQUIRED (reviewed head `5d4f763`) — 4 blocking findings fixed:** (1) **Standard flow restored** —
  tracer created only for Coexistence (per attempt); Standard/native = no-op tracer (no attempt id, no browser trace,
  no trace endpoint, not `mode=coexistence`; Standard create payload has no `onboarding_attempt_id`). (2) **Fresh
  attempt id per attempt** — minted at attempt start (not mount); retry uses a different id + support reference,
  carried end-to-end; no stale timers/events. (3) **Lifecycle-safe create** — cancellable timer + `AbortController`
  (signal threaded store→API→axios), cleared/aborted on success/failure/route-leave/unmount/retry, plus a per-attempt
  stale guard so a late response can't change UI/navigate/emit trace/refresh the store. (4) **Forbidden trace payloads
  rejected** — endpoint inspects the raw body before strong-params and returns 4xx with NO log for any non-allow-listed
  or sensitive top-level key (code/token/phone/phone_number_id/waba_id/business_id/app_id/configuration_id/url/query/
  message/metadata/…); unknown event → 422; logging-infra failure still 204. Suite after this first fix pass (historical
  snapshot; superseded — current exact-head counts are in Current State above: composable 20 · wizard 32 · trace service
  8 · trace endpoint 25 · backend 314/0): composable 20 · wizard 29 ·
  trace service 8 · trace endpoint 25; WhatsApp backend **314/0**; ESLint + RuboCop + vite build clean; no secret in
  diff; no migration/schema; no router/Enterprise change; Standard restored to pre-PR behavior; no Meta retry; no
  record mutation. New head pending push; fresh exact-head GPT‑5.5 review requested; do not merge/deploy.
- **Part 1 RCA (Stage A, evidence-based, read-only):** on deployed `d21a243`, a live Coexistence attempt completed
  the Meta flow (3 Meta webhooks 04:17–04:19 today → `[BLOOMWIRE ROUTER] no handoff-safe setup`, 200 OK) but the
  browser received no signal that resolved `runEmbeddedSignup()` → the create POST was **never dispatched** (0
  coexistence POSTs in the whole current-container log window 07-05 15:57→07-06 04:31) → **0 records** for the
  target account; the hang was indefinite → PR #127's second-signal timeout never armed (arms only after the first
  signal). Not D/E/F. Exact browser sub-stage wasn't logged (no client trace → Part 2 adds it). No records mutated;
  no Meta retry; account-1 fixture untouched.
- **Part 3 fix:** finite state + **overall watchdog armed at launch** (default 180s; bounds zero-signal /
  never-settling SDK) + kept second-signal timer + **bounded backend create** (45s) + guaranteed teardown
  (settle-once + `cancel()` on unmount/route change clears timers/listener/`isAuthenticating`/processing). Failure
  UX: spinner stops, sanitized message, support reference (short attempt id), manual Retry, no auto-retry, no
  partial records.
- **Part 2 trace:** one `onboarding_attempt_id` browser→controller; `Bloomwire::OnboardingTrace` → one allow-listed
  structured-JSON line per event to the app log (22 events); new admin-only, account-scoped, feature-gated (404),
  rate-limited endpoint `POST …/bloomwire/whatsapp/onboarding_traces` (strict event + metadata allow-list; unknown
  event → 422; logging failure → 204). Never logs code/token/phone/phone_number_id/WABA/business/App ID/Config
  ID/Meta URL. Standard/native flow untraced.
- **Initial validation (HISTORICAL snapshot at first push; superseded — current exact-head counts are in Current State
  above: composable 20 · wizard 32 · trace service 8 · trace endpoint 25 · backend 314/0):** composable 20 · wizard 25 ·
  trace service 8 · trace endpoint 8; WhatsApp backend regression
  **281/0**; ESLint + RuboCop clean; vite build ok; no secret in diff; no schema/migration; Enterprise untouched;
  webhook router unchanged. Branch `fix/bloomwire-coexistence-onboarding-trace` off `version_1` `d21a243`; open PR
  — do not merge (awaiting GPT‑5.5 review). Parts 4–6 (deploy + Meta-side state check + owner-assisted controlled
  retry with live trace evidence) pending post-approval; **no onboarding retried**.

### 2026-07-05 — WhatsApp channel tile intermittently disappears — deterministic-state fix (product code; open branch; NOT merged)
- **Defect:** on `/app/accounts/:id/settings/inboxes/new`, the WhatsApp channel tile appeared on one refresh and
  was absent on another (same user/account/URL/deployed build `8fabfc33`) — demo-blocking, non-deterministic.
- **RCA (proven, not guessed):** backend deterministic — on deployed `8fabfc33`, `Bloomwire::Capabilities.for` for
  account-1's admin returns `canSelfServeManagedWhatsapp=true` + `canCreateInbox=false` **10/10**, and all Bloomwire
  flags resolve `true` (DB + Redis cache aligned). Capabilities are emitted **only** on the account-show payload
  (`_account.json.jbuilder`, `if @current_account_user.present?`); the bootstrap `_user` accounts array omits them.
  The **frontend** was the fault: `useBloomwireCapabilities` returns `canSelfServeManagedWhatsapp=false` as a
  fallback whenever the account payload has not hydrated (it can't distinguish "loading" from "denied"). For a
  managed account WhatsApp is the **only** permitted tile (all others need `canCreateInbox=false`), so `ChannelList.vue`
  — which had **no loading state** — painted the terminal "MANAGED_BY_OPS" empty surface whenever the filtered list
  was momentarily empty. `accounts/get` swallows failures silently (no retry/error); `initializeEnabledFeatures`
  dereferenced `currentAccount.value.features` unguarded.
- **Fix:** `useBloomwireCapabilities` exposes `capabilitiesLoaded`; `ChannelList.vue` hydrates the account on mount
  and renders loading skeleton → recoverable error+retry → tiles → managed empty state only when genuinely loaded
  with no permitted channel. Never an empty surface during loading. Agents blocked; account context +
  Standard/Coexistence entry unchanged. Frontend-only; no backend/DB/router/auth/config/Enterprise change.
- **`custom_roles` 500:** Enterprise controller `Current.account.custom_roles` on a non-enterprise build; NOT on the
  inbox-new page (verified) → unrelated → **separate follow-up** (skip the fetch without the enterprise custom-roles
  capability). Not touched here.
- **Validation:** `ChannelList.spec.js` 24/24 (14 existing + 10 new race cases); `useBloomwireCapabilities.spec.js`
  +`capabilitiesLoaded`; focused FE 58/58; ESLint + `vite build` clean; no secrets. Runtime: case A + account-show
  304-cache + no-custom_roles-on-inbox-new captured on deployed build (authenticated session **amaya/account-21**);
  case B (missing) + mandatory **20 hard refreshes** need the **account-1 admin** session (amaya cannot access
  account 1) — pending. Branch `fix/bloomwire-whatsapp-tile-race` off `version_1` `8fabfc33`; open PR — do not merge
  (awaiting GPT‑5.5 exact-head review + the account-1 runtime verification).

### 2026-07-05 — WhatsApp / Meta Graph API version contract → v25.0 (product code; open branch; NOT merged)
- **Task:** the approved Meta Graph API version is **v25.0**; audit the whole Coexistence flow and make every WhatsApp/
  Meta Graph call use v25.0 explicitly, centralized, no scattered version strings, no behavior change beyond v25.0.
- **Audit result:** frontend Embedded Signup SDK silently used **v22.0** — `WHATSAPP_API_VERSION` was **never passed to
  the browser** (`dashboard_controller` set `FACEBOOK_API_VERSION` but not `WHATSAPP_API_VERSION`), so
  `window.chatwootConfig.whatsappApiVersion` was empty and `utils.js` fell back to a hard-coded `v22.0`. Outbound
  message/media used **v24.0** (`WHATSAPP_CLOUD_API_VERSION` unset). Backend code fallbacks were **v22.0**
  (`FacebookApiClient`, `HealthService`). Runtime DB `WHATSAPP_API_VERSION` was already `v25.0` (so the backend
  onboarding client already resolved v25.0, but the browser + message path did not).
- **Fix (centralized):** new `Whatsapp::GraphApi::DEFAULT_VERSION = 'v25.0'` (BE) + `DEFAULT_WHATSAPP_GRAPH_API_VERSION`
  (FE `utils.js`); all Coexistence-flow defaults now reference them (`FacebookApiClient`, `HealthService`,
  `WhatsappCloudService` message/media, `initializeFacebook`/`setupFacebookSdk`). `dashboard_controller` now passes
  `WHATSAPP_API_VERSION` (default v25.0) to the window config so the popup is config-driven with a v25.0 safety net.
  Per-surface ops overrides preserved.
- **Explicitly not changed:** global Meta webhook router (routes by `phone_number_id`; version-independent; unchanged),
  Enterprise WhatsApp calling (own `WHATSAPP_CALLING_API_VERSION_FALLBACK`), template-management surface
  (`business_account_path` + CSAT stay `v14.0` — separate follow-up), Instagram/Messenger/Shopify/reports.
- **TDD:** FE `utils.spec.js` RED-proven (4/5 failed on v22.0) → GREEN; BE `facebook_api_client_spec` all Graph URLs
  `/v25.0/` (never `/v1x|20–24/`); `whatsapp_cloud_service_spec` message/media `/v25.0/` + override; `dashboard_
  controller_spec` window config `whatsappApiVersion: 'v25.0'`. WhatsApp backend regression **278/0** (Enterprise
  call-flow **pre-existing** 6/6 fail on clean base, confirmed via stash — unrelated). RuboCop + ESLint clean; vite build
  ok; no secret in diff. Branch `fix/bloomwire-whatsapp-graph-api-v25` off `version_1` `e8717b0`; open PR — do not merge
  (awaiting GPT‑5.5 review). Runtime verification (sanitized browser/log v25.0 evidence) pending post-deploy.
### 2026-07-05 — Coexistence onboarding callback fix — Stage-B transition hang (product code; open branch; NOT merged)
- **Context:** the first live Coexistence onboarding for **account 21 (Pizza hut)** hung at "Registering your WhatsApp
  number…". Read-only incident investigation classified it **Stage B**: the browser received a Meta response and entered
  the registering state, but **no** `POST …/bloomwire/whatsapp/coexistence_embedded_signup` ever reached the backend
  (account 21 stayed at 0 Inbox/Channel/Setup; Meta sent 2 webhooks for the new number → global router fail-closed 200,
  existing fixture untouched; `WHATSAPP_CONFIGURATION_ID` active = `0643fcdbad9c`).
- **Root cause (source-traced):** owner `useWhatsappEmbeddedSignup.js`. The run Promise resolved only when **both** the
  FB.login `authCode` and the postMessage `businessData` were present (`resolveIfReady`), with **no** settlement path if
  only one arrived → it **never settled** → `isAuthenticating` stayed `true` → `BloomwireWhatsapp.vue`'s
  `await runEmbeddedSignup()` (before the create POST) hung → infinite `PROCESSING` loader, no POST.
- **Fix (smallest root):** a **bounded completion timeout** armed only once the first signal arrives (does not limit time
  in the Meta popup); a never-delivered second signal now rejects safely within `timeoutMs` (default 60s). Both arrival
  orders still resolve once; the `settled` guard keeps duplicate Meta events → **one** resolution → **one** create POST;
  reject/timeout → caller shows the sanitized generic error, ends the spinner, leaves the form retryable; account context
  preserved. **Frontend-only** — no backend/endpoint/router/DB/config/schema change; no Meta call added; no secrets.
- **TDD:** composable spec **14/14** (both single-signal timeouts RED-proven as 5s hangs before the fix; no-spurious-
  timeout; duplicate→one); caller spec **16/16** (signup reject → safe error + no create dispatch + retryable); backend
  coexistence request+service specs **20/0** (contract unaffected). ESLint clean; `git diff --check` clean; no secret in
  diff. Branch `fix/bloomwire-coexistence-callback-transition` off `version_1` `e8717b0`; open PR (do not merge — awaiting
  GPT‑5.5 review). **Follow-up (separate slice):** `GET …/custom_roles` → 500 `NoMethodError` on non-enterprise accounts.

### 2026-07-05 — Phase 17F.3 — GPT‑5.5 CHANGES REQUIRED fixes on PR #126 (server-authoritative alignment)
- **Primary fix — server-authoritative alignment:** the endpoint no longer trusts client-submitted `user_ids`. The
  request is now **identity-only** (`team_id` + `inbox_id`); `user_ids` was removed from the controller strong params
  **and** the frontend payload. `Bloomwire::CategoryInboxAlignment` recomputes, **inside the transaction from fresh DB
  state**, (a) eligibility — the pair must be a currently-derived, unambiguous pair — and (b) the additive drift, then
  adds only those server-computed differences. It **fails closed (422)** for unrelated / ambiguous / unlinked / stale
  pairs and **404** for cross-account ids. A **stale preview** (memberships changed after the UI rendered) is handled
  because the server recomputes fresh (association caches reset) rather than trusting a client list.
- **One derivation algorithm:** extracted `Bloomwire::CategoryInboxDerivation` (`matched_teams` / `derived_pair?` /
  `additive_drift`) and refactored `Bloomwire::CategoryInboxOverview` to reuse it — the overview and the alignment now
  share ONE algorithm (overview request specs still 15/0, output unchanged).
- **Transaction/Redis correction (no overstatement):** comments/docs now say **database-atomic** (not fully
  side-effect atomic). The stock `InboxMember after_create` round-robin is a **local Redis `LPUSH`** that is **outside
  the DB transaction** and can survive a DB rollback; it self-heals from `inbox.inbox_members` via
  `AutoAssignment::InboxRoundRobinService` (`reset_queue unless validate_queue?`). The upstream callback was **not**
  modified. Added a DB-rollback test (full rollback of membership rows) and a round-robin boundary test (queue
  reconcilable with the DB source of truth).
- **Frontend:** the dialog Confirm now posts only `{team_id, inbox_id}` (preview stays display-only); added a direct
  **double-submit** test proving a single in-flight request while `isSubmitting=true`. 17F.1 + 17F.2B tests preserved.
- **Validation:** backend `category_inbox_alignment_spec.rb` **19/0** (client-`user_ids` ignored ×2; server recompute;
  bidirectional additive; stale-safe; unrelated/ambiguous/unlinked/stale-ambiguous fail-closed; cross-account 404; agent
  401; database-atomic rollback; Redis boundary; no mapping; no external; feature-OFF 404); overview **15/0** unchanged;
  RuboCop clean; Vitest categoryInboxes **4 files/54**; ESLint clean; `git diff --check` clean; no secrets; no schema.
- **Unchanged guarantees:** no schema/migration, no persisted Team↔Inbox mapping, no Enterprise, no Meta/WhatsApp/HTTP
  call; not a customer-onboarding certification; full Gate B still required before production/customer go-live. Do not
  merge/deploy/run Meta/onboard/touch the existing fixture. Awaiting fresh GPT‑5.5 exact-head re-review.

### 2026-07-05 — Phase 17F.3 — Guided TeamMember + InboxMember alignment implemented (product code; open PR; NOT merged)
- **Base (fail-closed):** `origin/version_1` = `e9fcef99705eee792cf99c04baa9edc24eee880e` (PR #125 merge, verified). Branched
  `feature/bloomwire-phase-17f3-guided-membership-alignment` from that exact tip.
- **Recorded — Phase 17F.2B DEV runtime PASS** (prior deploy step, carried into this PR's docs; no separate docs-only PR):
  deployed SHA `e9fcef9`, run `28732366110`, authenticated account-1 admin, launcher on both eligible rows, account-scoped
  existing WhatsApp wizard reached (no team/category param), Standard + Coexistence reused, zero deltas, no Meta signup,
  **not Gate B**.
- **Discovery:** categories = existing **Team** convention; `TeamMember`/`InboxMember` are the join models (InboxMember's
  stock `after_create` round-robin is a **local Redis** op, not external). The 17F.1 overview already exposes the actionable
  drift per **linked** pair (`derived_inboxes[].drift.*`), so the overview DTO was **not** changed. Auth = `check_admin_authorization?`;
  scoping via `Current.account.teams/.inboxes.find` (cross-account → 404); feature via `BLOOMWIRE_CATEGORY_ADMIN_UI` (404 off).
- **Decision (helper vs existing APIs):** the existing `team_members` + `inbox_members` endpoints are two independent
  HTTP calls / transactions → sequential FE composition can leave **partial completion**. Per the atomicity requirement +
  the permitted 17F.3 contract, implemented a **local-only, admin-only, feature-gated transactional helper**
  `Bloomwire::CategoryInboxAlignment` (`POST /bloomwire/category_inbox_alignment`) that wraps both **additive**
  `TeamMember` + `InboxMember` writes in ONE `ActiveRecord::Base.transaction` — additive (never removes), idempotent,
  account-scoped, rolls back fully on failure, **no external/Meta call, no schema, no persisted Team↔Inbox mapping**.
- **Frontend:** overview offers "Align staff access" only on a linked/derived inbox with drift for a category-admin
  (agents / feature-OFF / **ambiguous → fail closed**). `MembershipAlignmentDialog.vue` previews current + additive diff
  ("no staff removed"); Cancel = no write; Confirm = alignment endpoint only; success refreshes the existing overview
  data source; failure shows a safe error and never falsely shows aligned.
- **TDD RED→GREEN:** backend `spec/requests/bloomwire/category_inbox_alignment_spec.rb` **13/0** (admin/agent/feature-OFF;
  cross-account team + inbox; invalid member; same-account; idempotent; no-op aligned; transaction rollback; no Meta/external;
  no persisted mapping); overview regression **15** unchanged; RuboCop clean. Frontend Vitest categoryInboxes **4 files/53**
  (new `MembershipAlignmentDialog.spec.js` + InboxSummary align-action + Index wiring, RED before impl); ESLint clean;
  `git diff --check` clean; no secrets; **no schema/migration**; safe DTO `{id,name}` only (no email/phone/secrets).
- **Files:** backend `app/services/bloomwire/category_inbox_alignment.rb`, `app/controllers/api/v1/accounts/bloomwire/category_inbox_alignments_controller.rb`,
  `config/routes.rb`; frontend `dashboard/api/bloomwire/categoryInboxAlignment.js`, `categoryInboxes/MembershipAlignmentDialog.vue`,
  `categoryInboxes/InboxSummary.vue`, `categoryInboxes/Index.vue`, `i18n/locale/en/categoryInboxes.json`; + specs + governance docs.
- **Status:** **IMPLEMENTATION COMPLETE (17F.3) — staff-access alignment only; not a customer-onboarding certification.**
  Existing "Bloomwire WA Dev" fixture untouched. Do not merge · do not deploy · do not run Meta signup · do not onboard a
  customer · do not start production work. Awaiting GPT-5.5 exact-head review.

### 2026-07-05 — Phase 17F.2B — Category → "Add WhatsApp Inbox" launcher implemented (frontend-only; open PR; NOT merged)
- **Base (fail-closed):** fetched latest `origin/version_1` = `0c3f32d2e02d7d8d6d980b556614d31d9cfd4de6` (PR #124
  merge; confirmed the expected merge commit is the tip). Branched `feature/bloomwire-phase-17f2b-category-add-whatsapp-launcher`
  from that exact tip — verified the branch is based on the latest `origin/version_1`.
- **Owner-approved dependency change (recorded in this implementation PR, per owner decision — no separate docs-only
  contract PR):** 17F.2B implementation **may begin before full Gate B certification**; **full Gate B / Real Meta
  Coexistence certification remains MANDATORY before production/customer go-live and before any end-to-end
  customer-onboarding certification claim.**
- **What (frontend-only):** added an **"Add WhatsApp Inbox"** launcher to each Category/Team row in
  `categoryInboxes/Index.vue`. It is a `router-link` that deep-links to the **existing** normal Add-Inbox flow
  (`settings_inboxes_page_channel`, `sub_page=whatsapp` → the existing Standard/Coexistence managed wizard) via
  `useAccount().accountScopedRoute`, preserving the account context. Gated by `canAccessCategoryAdmin &&
  canSelfServeManagedWhatsapp`. It **reuses the existing wizard** (no duplicate), performs **no writes / no backend
  call / no membership (TeamMember/InboxMember) alignment** (that is Phase 17F.3), creates **no Category model / table
  / entity / persistent Inbox↔Team mapping**, and adds **no backend endpoint / schema / migration / per-customer
  webhook / credential mutation / Enterprise code**. On return, the overview refreshes via its existing
  `onBeforeMount → categoryInboxOverviewAPI.get` data source; no fabricated Category↔Inbox relationship.
- **TDD RED→GREEN:** added launcher tests first; 4 were RED pre-implementation (admin sees launcher; account-scoped
  wizard route `settings_inboxes_page_channel`/`whatsapp`; no team/category param; declarative no-write click). After
  implementation: `categoryInboxes/Index.spec.js` **20 passed** (12 existing 17F.1 + 8 new); categoryInboxes directory
  regression **3 files / 35 tests**; ESLint clean on changed files; `git diff --check` clean; no secrets in diff.
- **Files (frontend only):** `categoryInboxes/Index.vue`, `categoryInboxes/specs/Index.spec.js`,
  `i18n/locale/en/categoryInboxes.json` + governance docs (change-log, ledger md/html, this SESSION-LOG). No
  schema/migration/backend/workflow/Enterprise.
- **Status:** **IMPLEMENTATION COMPLETE (17F.2B) — frontend launcher only; not a customer-onboarding certification.**
  Existing "Bloomwire WA Dev" fixture untouched. Do not merge · do not deploy · do not run Meta Embedded Signup · do
  not onboard a customer · do not start 17F.3. Awaiting GPT-5.5 exact-head review.

### 2026-07-05 — DEV Meta Embedded Signup launch/cancel preflight recorded (docs-only status evidence)
- **Secure DEV config update:** `WHATSAPP_APP_ID` present = true; `WHATSAPP_CONFIGURATION_ID` present = true;
  `platform_ready=true`. The two existing blank DEV `InstallationConfig` rows were updated securely and atomically; no
  duplicate rows were created; values were never printed, logged, or exposed. Rails and Sidekiq SHA remained
  `6894d93459cdba0fbc503a7d68b4f54b42a54571`; PostgreSQL and Redis were preserved; production was untouched.
- **Browser result:** **Meta Embedded Signup launch/cancel preflight PASS — account 1**.
- **Browser evidence:** authenticated legitimate account-1 administrator; `canCreateInbox=false`;
  `canSelfServeManagedWhatsapp=true`; normal UI path Settings → Inboxes → Add Inbox → WhatsApp Business → Coexistence;
  real Facebook OAuth popup launched for WhatsApp Business App onboarding; popup was cancelled before any number
  selection or onboarding completion; no onboarding persistence POST occurred.
- **Zero deltas:** account-scoped `Channel::Whatsapp` 1 → 1, `Inbox` 1 → 1, `Bloomwire::WhatsappSetup` 1 → 1; global counts
  remained 1 / 1 / 1; Contact 6 → 6; Conversation 6 → 6; Message 116 → 116; Sidekiq retry 0 → 0; Sidekiq dead 49 → 49;
  relevant application requests had no 5xx.
- **No mutation / no exposure:** no credential, subscription, callback, routing mapping, contact, conversation, message,
  inbox, channel, or setup mutation occurred; no secret or full identifier was recorded.
- **Boundary:** this is **not Gate B PASS**, not Embedded Signup completion PASS, not new Coexistence inbox creation or
  routing proof. Full Gate B / Real Meta Coexistence certification remains **BLOCKED / DEFERRED** because no second
  distinct controlled WhatsApp Business number is available. **17F.2B remains NOT STARTED**. Existing WhatsApp fixture
  remains do-not-touch. No popup preflight rerun, product code, tests, schema, workflow, config, DEV, production, roles,
  memberships, inboxes, channels, setups, or credentials changed in this docs-only PR; no deploy is authorized.

### 2026-07-04 — Standard inbox global-router supporting smoke recorded (docs-only status evidence)
- **Evidence classification:** **Existing Standard inbox global-router supporting evidence only**. Captured on DEV (`contabo-dev`) against the existing **“Bloomwire WA Dev”** Standard inbox at Rails/Sidekiq SHA `6894d93459cdba0fbc503a7d68b4f54b42a54571`; no smoke rerun is authorized after the captured run.
- **Supporting smoke result:** existing Standard inbox global-router smoke = **PASS as supporting evidence only**. One owner-assisted inbound text (`BW-STD-SMOKE-20260704T1100Z`) reached the global router with one 200 controller completion, one `Webhooks::WhatsappEventsJob` processing mention, one persisted incoming message, one target conversation/contact/contact-inbox path, zero duplicates, zero cross-account/inbox leakage, zero 401/no-handoff/5xx, and zero matching Sidekiq retry/scheduled jobs. One outbound reply (`BW-STD-SMOKE-REPLY-20260704T1108Z`) was created through the normal `Messages::MessageBuilder` → `SendReplyJob` path, reached final status `read`, had a masked source id present, and had zero duplicate/cross-account/retry/error findings.
- **Operational evidence:** local/public health remained 200; pending migrations remained false; Rails/Sidekiq SHA remained `6894d93459cdba0fbc503a7d68b4f54b42a54571`; fixture counts for `Channel::Whatsapp`, `Inbox`, and `Bloomwire::WhatsappSetup` remained one each; the existing fixture stayed aligned and ready for webhook; intended admin access passed, outside-account access failed closed, and no unassigned non-admin was available in current config.
- **What this proves:** the existing Standard inbox can receive a real inbound WhatsApp message through the global webhook router, route by the existing masked `phone_number_id` (`****8541`), persist exactly one target conversation/message path, send one normal outbound reply, preserve account/inbox isolation, avoid duplicate processing, and keep DEV operational health stable.
- **What this does not prove:** not Coexistence signup PASS, not Embedded Signup PASS, not new inbox creation PASS, not new-inbox isolation PASS, not Real Meta Coexistence onboarding certification, not full Gate B PASS, and not proof that the platform is ready for customer Coexistence onboarding.
- **Gate B / certification status:** Real Meta Coexistence onboarding certification remains **BLOCKED / DEFERRED** until `WHATSAPP_APP_ID` and `WHATSAPP_CONFIGURATION_ID` are restored, `platform_ready=true`, and a second distinct controlled WhatsApp Business number is available for the original new-inbox isolation contract. The existing **“Bloomwire WA Dev”** fixture remains do-not-touch; do not delete, migrate, rename, detach, modify, re-onboard, or bypass the unique phone-number constraint.
- **Scope of this update:** docs only (`change-log.md`, `implementation-ledger.md`, `implementation-ledger.html`, `SESSION-LOG.md`, `phase-17f2-guided-inbox-category-flow-discovery.md`). No product code, tests, schema/migrations, workflows, environment, DEV data/config, production, additional runtime smoke, or 17F.2B implementation changed.

### 2026-07-04 — Phase 17F.2A acceptance split correction before Standard smoke evidence (docs-only; owner-approved revised Option C)
- **Owner decision:** do **not** delete, migrate, rename, detach, or modify the existing **“Bloomwire WA Dev”** inbox, `Channel::Whatsapp`, `WhatsappSetup`, credentials, conversations, messages, contacts, or routing mapping. Do **not** re-onboard the same number, bypass the unique phone-number constraint, or call Gate B PASS.
- **Accepted 17F.2A scope:** PR #122 merged at `6894d93459cdba0fbc503a7d68b4f54b42a54571`; DEV deploy run `28699117487` succeeded for that SHA. Exact wording recorded: **Phase 17F.2A product implementation: PASS. DEV deployment: PASS. Gate A: PASS. Phase 17F.2A UI/runtime scope: DEV PASS.** This covers only the managed WhatsApp New Inbox entry, non-blank Add Inbox surface, admin/agent authorization, and feature-OFF / stock-compatible behavior.
- **Gate A evidence (owner-approved):** authenticated DEV normal navigation confirmed Settings → Inboxes, New Inbox visible for the authorized administrator, click-through to non-blank `/settings/inboxes/new`, WhatsApp Business card visible, Standard + Coexistence options visible, no provider secret fields exposed, cancel/back without creating records, safe unavailable state instead of blank where applicable, agent denied, feature-OFF/stock-compatible behavior preserved, and real Meta/WhatsApp calls = **0**.
- **Certification split:** former Gate B is renamed **Real Meta Coexistence onboarding certification** and is **BLOCKED / DEFERRED** because no second distinct controlled WhatsApp Business number is available; the only controlled DEV number is already connected to **“Bloomwire WA Dev”**; the same number cannot create a second `Channel::Whatsapp`; destructive removal/migration is not approved. `WHATSAPP_APP_ID` and `WHATSAPP_CONFIGURATION_ID` are now present and `platform_ready=true`, but that is necessary evidence only, not Gate B PASS. This remains a readiness/test-fixture limitation, **not a confirmed product defect**.
- **Zero certification resource deltas:** the later launch/cancel preflight created no fixture and changed no `Channel::Whatsapp`, `Inbox`, `Bloomwire::WhatsappSetup`, credential, subscription, callback, routing mapping, contact, conversation, or message; existing fixture untouched; production untouched.
- **Future hard gate:** Real Meta Coexistence onboarding certification remains mandatory before production enablement of customer Coexistence onboarding, before first real customer Coexistence onboarding, and before any claim that Bloomwire Coexistence onboarding is end-to-end certified. It remains blocked until a second distinct controlled WhatsApp Business number exists.
- **Existing supporting evidence status at this point:** later entries record the completed Standard inbox global-router supporting evidence and the account-1 Meta Embedded Signup launch/cancel preflight. Neither is Coexistence signup PASS, Embedded Signup completion PASS, new inbox creation PASS, Gate B PASS, or new-inbox isolation PASS.
- **17F.2B dependency:** **17F.2B remains NOT STARTED**. It must not begin until the existing full Gate B / Real Meta Coexistence certification passes. This docs-only status-evidence correction does **not** change that contract; any future dependency change requires a separate explicit owner-approved contract-change decision and GPT-5.5 review.
- **Scope of this correction:** docs only (`change-log.md`, `implementation-ledger.md`, `implementation-ledger.html`, `SESSION-LOG.md`, `phase-17f2-guided-inbox-category-flow-discovery.md`). No product code, tests, schema/migrations, workflows, environment, DEV data/config, production, or additional runtime smoke changed.

### 2026-07-04 — Phase 17F.2A implementation details before merge (historical; superseded by acceptance split above)
- **Preceding merge:** verified PR #121 at exact approved head `f52633a` (CI 8/8, docs‑only 5 files, 0 unresolved
  threads, no scope drift) and admin‑merged (GPT‑5.5 gate approval; self‑approve blocked) → merge SHA
  `ada23bc10b0c316c8ad48772d3e31621d5c1bcb2`; **`version_1` tip = `ada23bc`**. Docs‑only — **not deployed**, DEV/prod
  untouched. Then branched `fix/bloomwire-phase-17f2a-whatsapp-onboarding-entry` off `ada23bc`.
- **Root cause (owner‑observed DEV blocker; verified in source):** the managed WhatsApp onboarding **entry** was
  non‑operable — `settings/inbox/Index.vue` gated the New Inbox button on `isAdmin && canCreateInbox` (managed mode ⇒
  `canCreateInbox=false`; `canSelfServeManagedWhatsapp` not imported), and `settings/inbox/ChannelList.vue` filtered
  **all** cards when both `canCreateInbox` and `canSelfServeManagedWhatsapp` are false with **no empty state** ⇒ a
  **blank** `/settings/inboxes/new`.
- **Fix (minimal, frontend‑only; TDD RED→GREEN):** `Index.vue` — import `canSelfServeManagedWhatsapp`; New Inbox entry
  now `isAdmin && (canCreateInbox || canSelfServeManagedWhatsapp)` (stock/native `canCreateInbox` behavior unchanged;
  agents still denied — gated on `isAdmin`). `ChannelList.vue` — when `visibleChannelList` is empty, render a **safe
  explicit unavailable state** (reused `INBOX_MGMT.MANAGED_BY_OPS.TITLE`/`.BODY`) with a **usable Back action** (`goBack`
  → `settings_inbox_list`) instead of a blank surface; the managed WhatsApp card still routes to the existing wizard
  (`settings_inboxes_page_channel`, `sub_page=whatsapp`); other provider cards stay hidden in managed mode; **no secrets
  exposed.** Files: `Index.vue`, `ChannelList.vue`, `Index.spec.js`, `ChannelList.spec.js`. **No** schema/migration,
  backend endpoint, new mapping, duplicate wizard, per‑customer webhook, or Enterprise code.
- **Validation (automated; supporting evidence only — NOT the runtime gate):** RED first proved 3 failing behaviors
  (managed‑WA New Inbox entry; ChannelList unavailable state; Back action) for the right reason; after the fix **targeted
  Vitest 22 passed** (Index 9 + ChannelList 13), **inbox‑settings directory regression 8 files / 76 tests passed**,
  **ESLint clean** on changed files, `git diff --check` clean, **no secrets**.
- **Historical acceptance note:** at PR-open time the deployed gates had not yet run. This was superseded after PR #122 merge, DEV deploy run `28699117487`, Gate A PASS, and the owner-approved acceptance split recorded in the journal entry above.
- **Historical status:** implementation completed in PR #122 and later merged/deployed; this entry preserves the implementation details, while the current acceptance boundary is now governed by the docs-only correction above.

### 2026-07-04 — Phase 17F.2 — Guided "Add WhatsApp Inbox to Category" — DISCOVERY & CONTRACT only (docs‑only, open)
- **Scope:** discovery + implementation contract ONLY. **No product code / tests / schema / migration / workflow / env
  changes; no implementation; no deploy.** Branch `docs/bloomwire-phase-17f2-guided-inbox-discovery` off `version_1`
  `bb2a3d7` (verified the remote tip still equals `bb2a3d7d6c22b52627b6b17f747b64972e6ea609`).
- **Deliverable:** `docs/bloomwire/phase-17f2-guided-inbox-category-flow-discovery.md` — full current‑architecture map
  (Standard + Coexistence setup, inbox/channel creation, `Bloomwire::WhatsappSetup`, Team/`TeamMember`,
  `InboxMember`, the 17F.1 overview, deep‑links, policies, isolation, feature flags/capabilities, transaction
  boundaries, validation/rollback), a failure/rollback matrix, a security/authz matrix, feature ON/OFF behavior, and
  the recommended UX/backend/frontend orchestration + slices + RED→GREEN tests + risks/non‑goals.
- **Key findings (code‑evidenced):** the existing WhatsApp setup services do all Meta calls **before** a single
  `ActiveRecord::Base.transaction` (channel→inbox→credential→`WhatsappSetup`) that rolls back cleanly (no orphans) — so
  the Meta step is **not** inside a DB transaction. `TeamMember` + `InboxMember` writes are already admin‑only,
  account‑scoped, transactional, idempotent and reversible. The 17F.1 overview already surfaces partial completion
  (unlinked / drift / not_configured / ambiguous). Therefore the guided flow needs **no new mapping and no
  Meta‑spanning transaction**.
- **Historical correction appended to PR #121 (owner‑observed DEV blocker — doc §0):** before PR #122, an owner test on
  authenticated DEV found no "New Inbox" button and a blank `/settings/inboxes/new` channel list. That historical blocker
  was later fixed by PR #122 and accepted for 17F.2A UI/runtime scope by deployed DEV Gate A.
- **Recommendation (superseded by owner-approved status-evidence corrections):** current status correction authorizes
  documentation of the 17F.2A DEV pass, supporting smoke, secure public-identifier config update, and launch/cancel
  preflight only. **17F.2B remains NOT STARTED** and must not begin until the existing full Gate B / Real Meta Coexistence certification passes. Any future change to that dependency requires a
  separate explicit owner-approved contract-change decision and GPT-5.5 review.
- **Governance corrections in PR #121:** 17F.0 relabelled **Merged (PR #118, `6c0ab8c`)** in change-log + ledger
  (md/html); SESSION-LOG distinguished repository `version_1` tip `bb2a3d7` from DEV deployed runtime SHA `7bc59c7` at
  that time. Historical evidence preserved.

### 2026-07-04 — Phase 17F.1D — Merge + DEV deploy + authenticated DEV validation (PASS) — Phase 17F.1 COMPLETE
- **Final gate + merge:** verified PR #119 head was still the reviewed `024b35a56776ce4a50f7cd72137ffd79b68c9803`, CI
  **8/8 green** on that exact SHA, **no migration/schema**, read‑only product code, **0 unresolved review threads**.
  Formal GitHub *Approve* was blocked (authenticated identity is the PR author → `Can not approve your own pull
  request`); recorded a **pinned approval comment** on `024b35a` and, per owner authorization (GPT‑5.5 review already
  recorded; branch policy `REVIEW_REQUIRED` was the only blocker), merged via the **admin path** pinned with
  `--match-head-commit 024b35a`. **Merge SHA `7bc59c74ba5f96fc7ed394b0335dc216d4ab6529`** (2‑parent merge; parents
  `6c0ab8c` + `024b35a`); `version_1` tip = `7bc59c7`; no unrelated commits.
- **DEV deploy (17F.1D):** `deploy-dev.yml` `env=dev ref=version_1 run_migrations=true skip_smoke=false prune=false`,
  run **`28694180364` SUCCESS**. Rails + sidekiq `/app/.git_sha = 7bc59c7` (SSH‑verified on the DEV box); local +
  public health 200; rails+sidekiq recreated; postgres/redis preserved; no pending migrations; no 5xx. Dev SHA now
  `7bc59c7` (was `4525bea`). **`BLOOMWIRE_CATEGORY_ADMIN_UI=true`** (+ `MODE_ENABLED=true`) on dev; capability
  admin=true / agent=false. Prod untouched.
- **Authenticated DEV MCP (Chrome DevTools):** **Admin+ON PASS** — real account 1 (2 categories + ambiguous, deep‑links,
  read‑only, 1 overview GET, 0 console, no secrets) and a synthetic full‑matrix account (7 categories, ambiguous +
  unlinked sections, 2 drift blocks, 3 Standard/2 Coexistence badges, statuses pending/configured/ready_for_webhook/
  blocked/**not_configured**, Team+Inbox+Agents deep‑links, read‑only, isolation, desktop/tablet/mobile). **Agent+ON
  PASS** — curl agent token → own‑account 401 + cross‑account 401 (0 overview keys; labels control 200); browser → nav
  absent, route redirect (0 rows, no flash), overview fetch 401. **Feature‑OFF PASS** — admin overview 404, existing
  endpoints 200, browser nav absent + redirect + existing screens render; flag then **restored to true** + re‑verified.
- **Counts:** 5xx=0 · console errors=0 (only a deliberate agent 401 probe) · graph.facebook.com=0 · myshopify.com=0 ·
  overview mutations=0 · secrets=0.
- **Cleanup:** synthetic DEV account + all synthetic users + temporary tokens removed (`SYNTH_*`=0); real account 1 +
  real admin preserved; DEV feature left **ON**; browser synthetic session cleared; **no real Meta/WhatsApp/Shopify**
  (synthetic WhatsApp channels used `source=embedded_signup`, no `api_key`, no external calls); masked screenshots;
  local unrelated‑files stash `pre-17F1-correction-unrelated-files` restored cleanly (pdfs + ui-design/) and dropped.
  **Production untouched.**
- **Status: Phase 17F.1 COMPLETE. Phase 17F.2 NOT started.**

### 2026-07-04 — Phase 17F.1 — Read‑only "Categories & Inboxes" admin overview (feature‑flagged; product code; open, NOT merged)
- **What:** built the administrator‑only, **read‑only** "Categories & Inboxes" overview from 17F.0 Option C, using
  existing Chatwoot primitives only. Branch `feature/bloomwire-phase-17f1-category-inbox-overview` off `version_1`
  `6c0ab8c`. **PR #119.** Gated by new master‑gated feature `BLOOMWIRE_CATEGORY_ADMIN_UI` (OFF ⇒ stock: no
  route/page/API/nav).
- **Backend:** `Bloomwire::Features` flag + `Bloomwire::Capabilities` opt‑in `canAccessCategoryAdmin`
  (`managed_capability(admin, Features.enabled?(:category_admin_ui))`); service `Bloomwire::CategoryInboxOverview`
  now classifies every WhatsApp inbox exactly once: linked (one matched Team), ambiguous (multiple matched Teams), or
  unlinked (zero matched Teams). The safe DTO includes id+name staff/collaborator summaries, matched team metadata,
  relationship status, `connection_mode`, `Bloomwire::WhatsappSetup#setup_status`, and a safe `not_configured` fallback
  when no setup row exists. It still never serializes `provider_config`, tokens, or secrets.
- **Frontend:** admin‑only Settings page `categoryInboxes/Index.vue` + `InboxSummary.vue` (reuse `SettingsLayout` /
  `BaseSettingsHeader` / `Label`; deep‑links to `settings_teams_edit`, `settings_inbox_show`, and `agent_list`;
  loading/empty/error+retry); explicit ambiguous and unlinked sections; capability in `useBloomwireCapabilities`; route
  guard `redirectIfCategoryAdminDisabled`; sidebar nav entry; i18n `en/categoryInboxes.json` + `SIDEBAR.CATEGORY_INBOXES`.
- **Permissions (backend‑enforced):** admin+ON 200 (all account teams/inboxes) · agent+ON **401 (no payload)** ·
  OFF **404 (any role)** · account‑scoped. Frontend hiding is UX only.
- **TDD / correction specs:** backend request spec now **15/15** with RED coverage for linked/ambiguous/unlinked
  relationships, setup fallback, and no external calls. Frontend targeted specs now **24/24** with RED coverage for the
  ambiguous section, retry action, Agents deep‑link, relationship labels, and setup fallback label.
- **Validation:** scoped category/capability Vitest **39/39**; curated Bloomwire RSpec **627 examples, 0 failures,
  1 pending**; full Vitest **3661 passed**; full RuboCop **2700 files inspected, no offenses**; full ESLint **0 errors**
  (existing warnings only); docs governance + secret scan + migration/schema diff guard clean; `git diff --check` clean.
- **Runtime proof (LOCAL full stack — Rails+Vite; Chrome DevTools MCP; synthetic local‑only account):** Admin+ON page
  rendered the Categories & Inboxes nav, linked row with drift, ambiguous section with matched teams, unlinked section,
  Standard/Coexistence labels, setup statuses including **Not configured**, Team/Inbox editor links, and the Agents
  deep‑link. Network proof: `GET …/category_inbox_overview` returned **200** with safe DTO fields only. Agents link
  navigated to `/settings/agents/list`. Console had no application errors. Screenshot saved locally at
  `/tmp/pr119-category-inboxes-runtime.png`. **Cleanup:** synthetic account/users/inboxes/teams/setups/sessions verified
  zero; local Rails/Vite stopped; no production; DEV untouched.
- **Security:** no secrets exposed; no provider‑credential mutation; no live Meta/WhatsApp/Shopify; no Enterprise.
- **NOT changed / parked:** no schema, no writes, no new Category entity; contact visibility / inbox assignment /
  Standard‑Coexistence setup controllers / native `/whatsapp/authorization` / global webhook router untouched. A
  persistent Inbox↔Team mapping or data‑tag stays **out of scope** (separate owner‑approved design per 17F.0). This
  slice is read‑only; the guided add/assign write flow is a later slice. **Do not merge / deploy / start 17F.2
  without owner direction.**

### 2026-07-03 — Phase 17F.0 — Multi‑WhatsApp‑Inbox / Category Admin UI discovery (docs‑only, open)
- **Delivered** `docs/bloomwire/phase-17f0-multi-inbox-category-admin-ui-discovery.md` (exec summary, architecture map,
  code evidence w/ paths, runtime UX findings, permission matrix, Mermaid data‑flows, gap analysis, UX option
  comparison, recommended UX, implementation slices, TDD plan, risks, non‑goals, go/no‑go). Branch
  `docs/bloomwire-phase-17f0-multi-inbox-admin-ui-discovery` off `version_1` `096f619`; DEV runtime `4525bea`.
- **Method:** 4 read‑only code sub‑agents (inbox mgmt · teams/inbox‑team mapping · staff/permissions ·
  conversation/contact isolation + dataflow) + authenticated DEV admin runtime inspection (Chrome DevTools MCP, PHI
  masked): inbox list/settings, WhatsApp Standard/Coexistence setup, Teams (2: "Area 1"/"Area 2"), Agents (8), contacts,
  nav/IA. Verified **all Bloomwire gates ON on DEV**.
- **Architecture conclusion (evidence‑backed):** `Inbox` and `Team` are **independent** — no FK, no `team_id` on
  `inboxes`, no join table (`app/db/schema.rb`, `team.rb`, `inbox.rb`). So "Category/Department = Team + Inbox(es)" is
  **convention‑only**: name a Team as the category + add the same staff to **both** `InboxMember` and `TeamMember`
  (Chatwoot auto‑assign already intersects `inbox.member_ids ∩ team.member_ids`). **No new Category entity needed.**
  Admin‑vs‑agent boundaries are already **backend‑enforced** (Inbox/Team/User/Conversation/Contact policies + Bloomwire
  gates). The **only real gap is membership drift** (staff on Team but not Inbox, or vice‑versa) + the absence of a
  unified surface.
- **LOCKED Phase 17F permission model (backend‑enforced; doc §5a):** **Admin** lists/views/configures **every** inbox,
  starts & manages the approved **Standard + Coexistence** managed setup, and manages inbox members/teams/staff.
  **Agent** sees **only** `InboxMember`‑assigned inboxes + their reachable conversations/contacts, and **cannot** create
  a WhatsApp inbox / access Standard or Coexistence setup / modify provider config / bypass via direct routes/API —
  verified: `InboxPolicy` (admin‑only writes; scope=`assigned_inboxes`), managed embedded‑signup controllers enforce
  `check_admin_authorization?` (agent → not‑authorized even via direct API), `PermissionFilterService` +
  `ContactVisibility`. **17F.1**: "Categories & Inboxes" overview is **administrator‑only** (shows all account inboxes);
  agent operational selectors stay assigned‑inbox‑only; **no agent‑facing WhatsApp setup CTA/route**. These are 17F
  invariants; frontend hiding alone is not sufficient.
- **Recommended UX: Option C (Hybrid)** — thin Bloomwire "Categories & Inboxes" overview that composes existing stores
  and **deep‑links** the existing Chatwoot inbox/team/agent editors + a guided "add WhatsApp inbox → assign to
  category(team) → assign staff to both memberships" flow (writes both memberships at once ⇒ closes drift). Slices:
  17F.1 read‑only overview → 17F.2 guided add → 17F.3 unified staff membership → 17F.4 category↔inbox mapping +
  enforcement — **DEFERRED & NOT authorized by 17F.0** (default = no schema, no new entity; any persistent mapping/data‑tag ⇒ separate design review + explicit owner approval) → 17F.5 UI
  states/responsive → 17F.6 authenticated DEV E2E. All feature‑flagged (OFF ⇒ stock Chatwoot). **Go/No‑Go for 17F.1: GO.**
- **Docs‑only** (this doc + change‑log + ledger md/html + SESSION‑LOG). No product code · no migration/schema · no
  deploy · production untouched · no real Meta/WhatsApp/Shopify. **This ships in a docs‑only PR — do not auto‑merge.**

### 2026-07-03 — Phase 17E.4D — Dev deploy + authenticated runtime validation (PASS)
- **Merged PR #116** (17E.4 contact ID hardening) at **`4525bea6baf8c17315436982f0d70106508b9c57`** (admin merge; branch
  policy required a review, CI was 8/8 green; pinned to head `74b4519`).
- **Deployed `version_1 @ 4525bea` to DEV only** via `deploy-dev.yml` (manual; prod hard-blocked), **run
  `28684004558` — SUCCESS**. `run_migrations=true` no-op (0 pending in `3c45720..4525bea`), `prune=false`,
  postgres/redis volumes preserved. Post-deploy: `/app/.git_sha = 4525bea…`, local + public health 200, login
  renders, rails + sidekiq up, pg/redis reachable, **no pending migrations**, no 5xx. **Dev SHA is now `4525bea`.**
- **Enabled `BLOOMWIRE_RESTRICT_AGENT_CONTACT_VISIBILITY=true` on dev** (InstallationConfig; cache cleared; runtime
  resolves true) and **kept it enabled** (never enabled/modified in prod).
- **Authenticated runtime smoke (gate ON) — PASS.** Admin regression via the owner's existing MCP session
  (dashboard, WhatsApp Standard+Coexistence "Available now", inbox list, conversations, contacts list/search; no
  500/secret/Meta). 17E.4 targeted via a synthetic account (fake data; Shopify client stubbed — no real egress),
  run in-process through the real controller stack: **contact merge** agent in-scope 200 / out-of-scope
  mergee+base → 404 (contacts intact) / admin cross → 200; **conversation-create** agent in-scope 200 /
  out-of-scope → 404 (0 side-effects) / admin → 200; **Shopify orders** agent out-of-scope → **422, 0 client
  calls (no egress)** / in-scope → 200 (stub) / admin → 200; **isolation regression** unassigned conversation →
  401 (never 500), out-of-scope contact → 404 (never 500), agent index only assigned-inbox contact, admin all,
  seam agent-scope = in-scope only.
  - *Note:* a first synthetic run showed false "leaks" because the admin cross-scope conversation-create attached
    the agent's `cB` to Inbox 1 (a **test-data contamination**, not a product bug); fixed by using a separate
    admin target contact, after which every assertion passed. The deployed merge/conversation 404s were correct
    throughout.
- **Evidence:** 0 console errors · 0 HTTP 5xx · 0 `graph.facebook.com` · 0 real `myshopify.com` requests · masked
  screenshot (WhatsApp Standard/Coexistence).
- **Cleanup:** synthetic accounts + users + inboxes + contacts + conversations destroyed (0 remaining); no temp
  token files; **real data unchanged** (account 1 still 5 contacts). No production; no real Meta/WhatsApp/Shopify.
- **This entry ships in a docs-only governance PR (do not auto-merge).**

### 2026-07-03 — Phase 17E.4 — Contact ID hardening (PR #116, product code, open)
- **Built (branch `feature/bloomwire-phase-17e4-contact-id-hardening` off `version_1` `3c45720`):** closes the
  direct, ID-based contact-visibility gaps deferred in 17E.2/17E.3 by routing 3 paths through the existing
  `Bloomwire::ContactVisibility.scope(account:, user:)` seam (one line each). **Product code YES; gated.** No
  migration/schema, no frontend, no routes, no real Meta.
  1. `Actions::ContactMergesController#contacts` → seam (out-of-scope base/mergee → RecordNotFound → 404).
  2. `ConversationsController#contact` → `seam.find(params[:contact_id])` (out-of-scope → 404; inbox authz unchanged).
  3. `Integrations::ShopifyController#contact` → `seam.find_by(id:)` (out-of-scope → nil → existing `validate_contact`
     renders 422 and halts BEFORE any Shopify call → NO external egress; no extra product code — an exploring
     subagent claimed a nil-guard was needed, but it had misread the `return unless` logic; verified against source).
- **Gate ON** blocks a gated agent on all three out-of-scope paths; **gate OFF == stock Chatwoot**; **admin** never
  narrowed; **CSAT** stays admin-only/protected (product code NOT touched).
- **RED→GREEN:** rewrote `hardening_followup_inventory_spec.rb` from characterization → hardening (15 ex). RED-proven:
  reverting the 3 controllers (`git stash`) fails exactly the 4 out-of-scope block cases (merge base/mergee,
  conversation attach, Shopify — stubbed client's `:get` called twice); re-applying is GREEN. Shopify no-egress
  asserted (`shopify_client` never `:get`; `a_request(/myshopify\.com/)` not made).
- **Validation:** new **15/15**; suite (hardening + multi_inbox_runtime_e2e + contact_isolation + contact_visibility
  + shopify_controller + contact_merges_controller) **73/73**; conversations_controller regression **80/80**; RuboCop
  clean; `git diff --check` clean; no migration/schema; secret scan clean. Files: 3 controllers + 1 spec.
  **PR #116 — open, non-draft, NOT merged.** No deploy · no production · no real Meta · dev `3c45720`.

### 2026-07-03 — Phase 17E.3D — Dev Validation Release (dev-only deploy; no PR)
- **Deployed `version_1 @ 3c45720` to DEV only** via `deploy-dev.yml` (manual dispatch; production hard-blocked in
  the workflow). Flags: `environment=dev`, `ref=3c45720` (exact SHA), `run_migrations=true` (no-op — 0 pending
  migrations in `9b09f9e..3c45720`), `skip_smoke=false`, `prune=false`.
- **Result: SUCCESS** (run 28673559748) — server smoke: local health 200, `/app/.git_sha =
  3c45720204fe4c57528dfd8d1ef43f8a34674612`, public health 200; rails + sidekiq recreated + up; postgres `Up 6 days`
  (never recreated → volume preserved); redis container recreated as a compose dependency but no `down -v`/prune →
  data preserved. Independent public checks from the workstation: `/health` 200, login page 200.
- **Dev deployed SHA is now `3c45720204fe4c57528dfd8d1ef43f8a34674612` (`3c45720`)** (was `9b09f9e`). Production
  untouched; no secrets printed; no real Meta; no customer data exported. Authenticated UI click-through remains
  owner-operated.

### 2026-07-03 — Phase 17E.3 — Owner-operated runtime E2E with mocked Meta (PR #115, test-only, open)
- **Built (branch `test/bloomwire-phase-17e3-runtime-e2e-mocked-meta` off `version_1` `d98f7d8`):** two RSpec
  integration specs proving the full multi-WhatsApp-inbox + customer/agent-visibility workflow end-to-end through
  the REAL runtime stack, with **Meta mocked only**. **Test-only — no product code, no migration/schema, no
  frontend, no routes.** Meta is stubbed at the seam (`Whatsapp::TokenExchangeService` / `PhoneInfoService` /
  `FacebookApiClient` + `Bloomwire::GlobalWhatsappConfig`); `WebMock.disable_net_connect!` blocks egress and an
  example asserts no `graph.facebook.com` call.
- **`app/spec/integration/bloomwire/multi_inbox_runtime_e2e_spec.rb` (22 ex):** Flow 1 admin creates Inbox 1
  (Standard) + Inbox 2 (Coexistence) via mocked embedded signup (each mapped to its own `Channel::Whatsapp` +
  `Bloomwire::WhatsappSetup`; safe DTO; non-admin forbidden); Flow 2 inbound webhook routes pnid1→Inbox 1,
  pnid2→Inbox 2 (connection_mode-agnostic), unknown + crossed pnid fail closed; Flow 3 category agent conversation
  isolation (cross-open → 401; admin both); Flow 4 contact isolation gate ON (list/search/show + sub-resource 404 +
  bulk label scoped; admin + gate-OFF unaffected); Flow 5 UI-sanity at the API. The signup-created inboxes are
  router-aligned, so setup → webhook → conversation/contact → isolation is one continuous flow.
- **`app/spec/integration/bloomwire/hardening_followup_inventory_spec.rb` (5 ex, 1 pending):** CHARACTERIZES (does
  NOT fix) the KNOWN, DEFERRED 17E.2 gaps with the gate ON — a CONTROL example proves the gate is active, then:
  **contact merge** + **conversation-create** are agent-reachable + unscoped (current behavior, gap open);
  **CSAT report** is admin-only (401 for agents — protected, not a vector); **Shopify orders** is statically
  reachable + unscoped but outside the mocked runtime (needs an integration hook + external stub) — pending/skip.
  No NEW/unexpected leak beyond the documented 17E.2 set → proceeded (verify + document, do not widen scope).
- **Validation:** new **27 examples, 0 failures, 1 pending**; regression (contact_isolation, contact_visibility,
  multi_whatsapp_inbox_category_contract, whatsapp_router, whatsapp_inbound_e2e, embedded_signups,
  coexistence_embedded_signups) = **109 examples, 0 failures, 1 pending**; RuboCop clean; `git diff --check` clean;
  secret scan clean; migration/schema guard empty. **PR #115 — open, non-draft, NOT merged.** No deploy · no
  production · no real Meta · dev remains `9b09f9e`.
- **Owner-operated browser E2E checklist (deferred to owner — no Capybara/system-spec harness in the repo):** run
  against a local instance (Meta stubbed/mocked, never real Meta): (1) log in as account admin → Inbox settings →
  add a managed WhatsApp inbox via Embedded Signup (mocked) twice → two inboxes appear; (2) feed a mocked inbound
  webhook per number → a conversation appears under the matching inbox; (3) log in as a category agent → confirm
  only that inbox's conversations + contacts are visible (no cross-category rows); (4) as admin → confirm both are
  visible; (5) with the gate ON, confirm an agent cannot open another category's contact. Capture screenshots for
  the record. Automated CI coverage is the request-level runtime E2E above.

### 2026-07-03 — Phase 17E.2 — PR #114 review blocker fix: bulk contact label actions scoped (product code, open)
- **Review verdict `REQUEST_CHANGES`** on PR #114 (reviewed head `2cf9c09`): the bulk-action path
  (`POST /api/v1/accounts/:id/bulk_actions`, `type=Contact`) **bypassed** the new `Bloomwire::ContactVisibility`
  seam — a gated agent who knew an out-of-scope `contact_id` could bulk **add/remove labels** on it
  (`Contacts::BulkActionService` → sub-services run `@account.contacts.where(id: ids)` with no visibility scoping).
- **Root cause / owner:** the mutation runs in an async job (`Contacts::BulkActionJob`) where `Current.user` is
  nil, but the controller `BulkActionsController#enqueue_contact_job` already has `current_user` and owns the `ids`
  param. **Smallest safe fix = filter the ids controller-side, before enqueue**, so unsafe raw ids never reach the
  async job. (Downstream sub-services don't receive the user, so they can't self-scope.)
- **Fix (product code, 1 controller):** new `BulkActionsController#scoped_contact_params` — when
  `Bloomwire::ContactVisibility.restricted_for?(account:, user:)` (gate ON + non-admin agent), replace `ids` with
  `Bloomwire::ContactVisibility.scope(account:, user:).where(id: ids).pluck(:id)`; **admins / gate-OFF pass ids
  through unchanged** (byte-identical params). **Delete stays admin-only** via the existing `authorize(Contact, :destroy?)`.
- **Bug caught by the new tests:** `contact_params` returns a **string-keyed** hash, so an initial symbol-key read
  (`permitted[:ids]`) was nil → in-scope labels silently dropped. Fixed to read/write the `'ids'` string key; the
  new in-scope A/C cases went RED immediately and surfaced it — exactly the guard they're meant to be.
- **Tests (+7 in `contact_isolation_spec`, async job run via `perform_enqueued_jobs`):** gated agent bulk-add label
  to own contact A → succeeds; add to out-of-scope B → B NOT mutated; remove from B → B NOT mutated; mixed [A,B]
  add → only A; shared C → succeeds; admin bulk-labels A+B (both inboxes) → succeeds; gate-OFF agent labels B →
  stock succeeds. **RED proof:** reverting only the controller (`git stash`) fails exactly the 3 "does-not-mutate-B"
  cases (B is mutated) → the tests fail if raw `@account.contacts.where(id: ids)` is used; re-applying is GREEN.
- **Validation:** `contact_isolation_spec` **20/20** + `contact_visibility_spec` **5/5**; bulk-path regression
  `bulk_actions_controller_spec` + `contacts/bulk_action_service_spec` + `contacts/bulk_action_job_spec` +
  `contacts_controller_spec` = **76/76** (stock/admin/gate-OFF unchanged); RuboCop clean; `git diff --check` clean;
  **no migration/schema · no frontend · no route**; secret-scan clean. **PR #114 — still open, non-draft, NOT
  merged; not deployed.** Dev remains `9b09f9e`. Remaining deferred: merge / CSAT / Shopify / conversation-create
  ID-based paths → 17E.3 hardening.

### 2026-07-03 — Phase 17E.2 — Contact isolation & UI/permission polish (PR #114, product code, open / ready for review)
- **Built (branch `feature/bloomwire-phase-17e2-contact-isolation-permission-polish` off `version_1` `5df9f9d`):**
  the backend contact-visibility fix that resolves the 17E.0/17E.1 caveat (stock Chatwoot contact list/search is
  account-wide). **Product code changed: YES**, but **gated** so **OFF == stock Chatwoot**. No migration/schema,
  no frontend, no route/workflow, no native `/whatsapp/authorization` / `Whatsapp.vue` / webhook-router change.
- **Decision:** a business **agent** (gate ON) may only list/search/open contacts **reachable through their
  assigned inboxes** (via `contact_inboxes`); **admins see ALL**; a **shared** contact (contact_inbox in ≥2
  inboxes) is visible to agents of any of those inboxes; **conversation isolation stays the primary enforcement**.
- **Implementation:** new gate `Bloomwire::Features.restrict_agent_contact_visibility?`
  (`BLOOMWIRE_RESTRICT_AGENT_CONTACT_VISIBILITY`, master AND-gated); new single seam
  `Bloomwire::ContactVisibility.scope(account:, user:)` (subquery `where(id: … joins(:contact_inboxes) …)` —
  distinct-safe, admin/stock/non-User → `account.contacts`); routed through `ContactsController#index/search/
  active/show` (+ `fetch_contact`), `Contacts::FilterService#base_relation`, global `SearchService#filter_contacts`,
  and `contacts/base_controller#ensure_contact` (sub-resources → 404 out-of-scope).
- **RED→GREEN:** wrote `contact_isolation_spec` + `contact_visibility_spec` first → RED (agent saw all contacts,
  5 leak failures) → implemented the gated seam → GREEN. Gotcha: the GlobalConfig cache lives in Redis (not rolled
  back by the DB transaction), so the specs `after { GlobalConfig.clear_cache }` to avoid leaking the enabled gate
  into unrelated specs (that was the root cause of 2 transient regressions in the stock contacts spec).
- **Deferred (documented limitation):** direct ID-based contact access via **merge / CSAT report / Shopify /
  conversation-create** is not scoped here (mutations/reports/integrations needing a known contact_id, not
  enumeration) — hardening follow-up. Export/import remain admin-only (safe).
- **Validation:** `contact_visibility_spec` **5/5** + `contact_isolation_spec` **13/13**; regression
  `contacts_controller_spec` **58/58**, `multi_whatsapp_inbox_category_contract` + `conversation_finder` +
  `permission_filter_service` + `contact_policy` **35/35**, `features_spec` **18/18**; RuboCop clean;
  `git diff --check` clean; secret-scan clean. Pre-existing enterprise `companies` failure proven via `git stash`
  (unrelated). **PR #114 — open, non-draft, ready for review (not merged).** No deploy · dev remains
  `9b09f9e`. Next: **17E.3** runtime E2E.

### 2026-07-03 — Phase 17E.1 — Multiple WhatsApp Inbox backend contract tests (PR #113, test-only, merged)
- **Built (branch `test/bloomwire-phase-17e1-multi-whatsapp-inbox-contracts` off `version_1` `83496896`):**
  automated backend contract coverage that turns the 17E.0 discovery finding ("one account can own multiple
  WhatsApp inboxes") into regression-locked tests. **Test-only — no product code changed** (existing code already
  satisfies the contract). No migration/schema; all Meta calls stubbed (no real Meta/WhatsApp).
- **Added (6 spec files; 1 new + 5 extended):**
  - `spec/services/bloomwire/whatsapp_embedded_signup_service_spec.rb` + `…coexistence…_service_spec.rb`: two
    different numbers → two distinct `Channel::Whatsapp` + `Inbox` + `Bloomwire::WhatsappSetup` (same account);
    duplicate `phone_number` → `:phone_number_taken`; duplicate `phone_number_id` → `:phone_number_id_conflict`
    (second channel rolled back); coexistence keeps `connection_mode=coexistence` for each.
  - `spec/requests/api/v1/accounts/bloomwire/whatsapp/embedded_signups_spec.rb` + `…coexistence…_spec.rb`: admin
    can register two numbers as two inboxes; duplicate → 422 (`phone_number_taken` / `phone_number_id_conflict`).
  - `spec/services/bloomwire/webhooks/whatsapp_router_spec.rb`: two numbers in ONE account each resolve to their
    own inbox; unknown pnid → nil; crossed pnid/display → fail-closed; Standard + Coexistence coexist (routing is
    connection_mode-agnostic).
  - NEW `spec/services/bloomwire/multi_whatsapp_inbox_category_contract_spec.rb`: Category = Team + Inbox —
    ConversationFinder + ConversationPolicy prove a category agent lists/opens ONLY their inbox (admin sees both);
    team-filtered assignment keeps a conversation within its category (a team-2-only assignee is rejected).
- **Validation:** targeted `rspec` on the 6 files = **73 examples, 0 failures**; RuboCop clean (no offenses);
  `git diff --check` clean; secret-scan clean. **No product code / no migration / no deploy / no production.**
  **Merged: PR #113 → `version_1` `5df9f9d74a59057e099e82c1e5471bfff0c8e449`; test-only.** Dev remains `9b09f9e`. Next: **17E.2** contact isolation (this session).

### 2026-07-03 — Phase 17E.0 — Multiple WhatsApp Inbox per Account discovery + ADR-0009 (PR #112, docs-only, merged)
- **Built (branch `docs/bloomwire-phase-17e0-multi-whatsapp-inbox-discovery` off `version_1` `ea30579`):** a
  docs-only discovery + ADR that **locks the multiple-WhatsApp-inbox-per-account business model** before the 17E
  hardening slices. No app code, tests, routes, migrations, deploy, or Meta calls.
- **Deliverables (6 docs files):** new `docs/bloomwire/whatsapp-multi-inbox-discovery.md`; new
  `projects/bloomwire-chatwoot-platform/docs/adr/0009-multi-whatsapp-inbox-category-model.md`; plus change-log /
  implementation-ledger (md + html) / this SESSION-LOG (stamp 17D.3 merged + record 17E.0).
- **Verdict — SUPPORTED (from the completed multi-inbox analysis):** one account can already own multiple WhatsApp
  inboxes/numbers with **no code change**. `Bloomwire::WhatsappEmbeddedSignupService#persist` creates a new
  `Channel::Whatsapp` + `Inbox` + `Bloomwire::WhatsappSetup` per call and blocks only a duplicate `phone_number`
  (global); Coexistence inherits it. Schema has **no per-account WhatsApp uniqueness**
  (`channel_whatsapp.phone_number` global-unique; `bloomwire_whatsapp_setups.account_id` non-unique index;
  `phone_number_id` global-unique-partial). `canSelfServeManagedWhatsapp` is a role/managed-mode guard, **not**
  count-based, so the Add-Inbox WhatsApp card never disappears. The global router resolves by `phone_number_id` →
  one setup → its own inbox (fail-closed).
- **Model:** Category = **Team + Inbox**; number = `Channel::Whatsapp` + `Inbox` + `Bloomwire::WhatsappSetup`;
  employee = `User`/agent; staff = TeamMembers + InboxMembers; message = `Conversation`; assignment =
  `assignee_id`/`team_id`. Agent inbox/conversation visibility is backend-scoped (`InboxPolicy::Scope`,
  `ConversationFinder`, `Conversations::PermissionFilterService`, `ConversationPolicy`); admin sees all.
- **Caveats recorded:** (1) **contacts** index/search is account-wide in stock Chatwoot → cross-category
  contact-record leak (conversations stay isolated), decision deferred to **17E.2**; (2) **no multi-inbox tests**
  yet → **17E.1**. Next: 17E.1 backend contract tests → 17E.2 UI/permission + contacts decision → 17E.3
  owner-operated runtime E2E (mocked Meta) before customer go-live. **Merged: PR #112 → `version_1`
  `83496896fcc7bcaa6ca076dbd2f346ee5eb4f7bc`; docs-only.** No deploy · dev remains `9b09f9e`. Next: **17E.1** backend contract tests (this session).

### 2026-07-03 — Phase 17D.3 — WhatsApp Business App Coexistence frontend enablement (PR #111, merged)
- **Built (branch `feature/bloomwire-phase-17d3-coexistence-frontend` off `version_1` `35a1a14`):** frontend
  enablement of the Coexistence card in the customer WhatsApp setup wizard. **Product truth:** *user expects* to
  connect an **existing** WhatsApp Business App number; *system* showed the card **disabled/"Coming soon"* (17C.3);
  *done* = card selectable → Meta Embedded Signup → dedicated coexistence endpoint → managed inbox, Standard flow
  untouched.
- **Changed (frontend only, 6 files):** `BloomwireWhatsapp.vue` (enable card; `flow` ref + `startCoexistence`;
  flow-aware form title/desc/button + dispatch), `whatsappChannel.js` (new
  `createBloomwireCoexistenceEmbeddedSignup`), `store/modules/inboxes.js` (new action
  `createBloomwireWhatsAppCoexistenceEmbeddedSignup`), `i18n/locale/en/inboxMgmt.json` (`STATUS`→"Available now";
  new `CTA`/`CONNECT_BUTTON`/`FORM_TITLE`/`FORM_DESC`), `specs/BloomwireWhatsapp.spec.js` (coexistence flow +
  card-enabled + standard-regression), new `api/specs/channel/whatsappChannel.spec.js` (endpoint URLs).
- **Endpoint:** Coexistence → `POST /api/v1/accounts/:id/bloomwire/whatsapp/coexistence_embedded_signup`
  (payload only `code`/`business_id`/`waba_id`/`phone_number_id`). Standard unchanged (`…/embedded_signup`).
- **Validation:** Vitest — component **15/15**, new API client **4/4**, hook **10/10**; regression
  `inboxes/actions` **20/20**, `ChannelFactory` **9/9**, `ChannelList` **8/8**, `useBloomwireCapabilities` **9/9**.
  ESLint clean (`--max-warnings=0`) on all changed JS/Vue; `inboxMgmt.json` valid JSON.
- **Security / boundaries:** no secrets or manual-credential UI (only the 4 non-secret fields — test-asserted);
  no live Meta/WhatsApp (SDK + `postMessage` mocked); native `/whatsapp/authorization` + `Whatsapp.vue` and the
  `canSelfServeManagedWhatsapp` role gate untouched; no backend/route/migration/schema change; no Enterprise code;
  no duplicate chat store. **Merged: PR #111 → `version_1` `ea305792dc83f864f8e1374ce0ca832f99f7d8f9`** (approved head `d9810b7`); no deploy · dev remains `9b09f9e`. Next: **17E** multi-WhatsApp-inbox (17E.0 discovery, this session) then **17C.4** verify / go-live UX.

### 2026-07-03 — Phase 17D.2 — WhatsApp Business App Coexistence webhook proof (PR #109, merged)
- **Built (branch `feature/bloomwire-phase-17d2-coexistence-webhook-proof` off `version_1` `5002942`):** a
  backend/webhook proof that the existing global router (ADR-0005) + stock `Webhooks::WhatsappEventsJob` safely
  handle Coexistence traffic before frontend enablement. **No frontend enablement** — `BloomwireWhatsapp.vue`
  untouched, Coexistence card stays disabled until 17D.3.
- **Investigation first:** read the router, the global webhook controller, the events job, and the coexistence
  service. Findings: (a) the router keys only on `metadata.phone_number_id` + channel alignment, never
  `connection_mode` → coexistence channels route identically; (b) the events job **already** handles
  `smb_message_echoes` → `IncomingMessageWhatsappCloudService(outgoing_echo: true)` (outgoing path, not a
  duplicate inbound); (c) `smb_app_state_sync` was **not** special-cased → it fell through to inbound processing.
- **RED → GREEN (only code change):** a failing test proved `smb_app_state_sync` called
  `IncomingMessageWhatsappCloudService`; added an `app_state_sync_event?` guard + `handle_app_state_sync` to
  `Webhooks::WhatsappEventsJob` that logs one redacted, content-free line and returns — no inbound processing, no
  message/conversation, no crash. Routing + echo required no code change (already safe).
- **Specs:** router coexistence context (routes by pnid; echo payload routes; wrong pnid fails closed;
  account-scoped) + events-job coexistence context (echo → outgoing path; app_state_sync → safe ignore, no
  service call, no message/conversation) + two fake payload helpers (`bw_echo_payload`, `bw_app_state_sync_payload`).
- **Validation:** targeted router + events-job = **43 examples, 0 failures**; broader webhook regression (router,
  job, PII logging, request logging, inbound e2e) = **58 examples, 0 failures**; RuboCop clean. Proof doc:
  `docs/bloomwire/whatsapp-coexistence-webhook-proof.md`. No real Meta (fake payloads, no HTTP); no migration/
  schema; no deploy; no production; no secrets; no app-side duplicate chat storage; native `/whatsapp/
  authorization` untouched. **Merged: PR #109 → `version_1` `4a57564d7c1fbc54aeafbf9049f61b5b7a8b0795`** (approved head `fbbbe14`); no deploy · dev remains `9b09f9e`. 17D.3 frontend enablement is next.
- **Gotcha:** the events job accesses payloads with symbol keys (indifferent-access via `perform_later`
  round-trip), while the router uses string keys — so job specs build symbol-keyed payloads (`params.deep_dup`)
  and router specs use string-keyed helpers.

### 2026-07-02 — Phase 17D.1 — WhatsApp Business App Coexistence backend contract (PR #107, merged)
- **Built (branch `feature/bloomwire-phase-17d1-coexistence-backend` off `version_1` `c4ca702`):** the backend
  contract for the "Connect Existing WhatsApp Business App" (Coexistence) option that the 17C.3 wizard shows
  disabled/"Coming soon". PR #107 (then in draft) already had the service + service spec + controller; this session
  **wired the route**, **added the request spec**, verified the boundary, updated docs, and — after CI went green —
  marked the PR **ready for review** (non-draft; not merged).
- **Route:** `POST /api/v1/accounts/:account_id/bloomwire/whatsapp/coexistence_embedded_signup` added under the
  SAME `namespace :bloomwire { namespace :whatsapp }` as the 17C.2 `embedded_signup` route. Native
  `/whatsapp/authorization` untouched.
- **Service** `Bloomwire::WhatsappCoexistenceEmbeddedSignupService < Bloomwire::WhatsappEmbeddedSignupService`:
  inherits the entire safe 17C.2 seam (fail-closed readiness + encryption-before-token-storage; token exchange +
  phone info + **`subscribe_app_to_waba` only** — global router, never override/`setup_webhooks`/
  `subscribe_waba_webhook`; token via `WhatsappCredentialWriter`; non-secret `WhatsappSetup` mapping). Overrides
  ONLY: `provider_config['connection_mode']='coexistence'` (source still `bloomwire_managed`) and adds
  `connection_mode: 'coexistence'` to the channel + setup DTO sections. Controller mirrors the 17C.2 controller
  (admin-only + managed-mode 404 guard + sanitized errors).
- **Validation:** `spec/services/.../whatsapp_coexistence_embedded_signup_service_spec.rb` +
  `spec/requests/.../coexistence_embedded_signups_spec.rb` — **14 targeted examples, 0 failures** (Meta stubbed via
  service/client instance-doubles — no HTTP); RuboCop clean on the 5 files; `rails routes -g coexistence` resolves
  the endpoint to the controller. Request spec covers admin-allowed (with `connection_mode: coexistence` on
  channel + setup), agent-denied, 404 (Bloomwire OFF / onboarding OFF / native unrestricted), 422 not_ready /
  encryption, cross-account denied, and no token/api_key/provider_config in the body.
- **Boundary check:** grep of the new files for `setup_webhooks`/`override_waba_callback`/`subscribe_waba_webhook`/
  `whatsapp/authorization` finds only boundary-documenting comments — no forbidden calls. Backend contract only:
  no frontend enablement (Coexistence card stays disabled), no migration, no deploy, no secrets, no real Meta.
- **Merged:** **PR #106** (17D.0 discovery, docs-only) → `version_1` `f9aeac7245bb6e9869c25233ed68377f77062e90`,
  then **PR #107** (17D.1 backend contract) → `version_1` `ebdcba2831fd40330eaefd5a6dfe87f97a00b867` (approved head
  `67b63cd`; merged onto the post-#106 base). CI 8/8 green on both. **No deploy · dev remains `9b09f9e` · no
  production · no migration · no real Meta/WhatsApp · no secrets.** Coexistence frontend card stays disabled/
  "Coming soon" until **17D.3**; **17D.2** (webhook/coexistence proof) is next.

### 2026-07-02 — Phase 17C.3 (UX revision) — connection-choice screen (PR #104, merged)
- **Change (review feedback, WhatsWay-style flow):** `BloomwireWhatsapp.vue` now opens on a **"Connect WhatsApp
  Channel"** choice screen before the number-registration form, with a `mode` state (`choose` → `register`):
  1. **Connect Existing WhatsApp Business App** — badge **Coexistence**, **disabled / "Coming soon"**, lists the
     prerequisites (app v2.24.17+, active 7+ days, supported country, Meta Business Account, QR scan, chat-history
     sync, companion devices may unlink, keep using both). It **never calls the backend** (no coexistence backend
     yet — the card is UI-only).
  2. **Register New Number** — badge **Standard**, "Available now" — continues into the existing Standard flow
     (confirm number + optional inbox name → Connect with Meta → safe DTO → Open inbox / Inbox settings).
- **Unchanged hard rules:** no Add-Agents step; no credential fields; Standard flow still posts only the
  non-secret signup credentials to the 17C.2 endpoint; sanitized generic error; safe DTO only; native
  `/whatsapp/authorization` + native `Whatsapp.vue` untouched; no backend/migration change.
- **Tests:** BloomwireWhatsapp spec grew to **10** (3 new choice-screen tests: exactly two options; Coexistence
  disabled/coming-soon + 8 prerequisites + no backend call; Register New Number continues to the form) — existing
  Standard-flow tests now navigate through the choice screen. **36 tests total** across the 4 spec files; ESLint
  clean; i18n JSON valid; no real Meta. **(PR #104 subsequently merged — see the Merged note below.)**
- **Gotcha:** the disabled Coexistence CTA has no `@click` handler at all (not just `disabled`) so it can never
  reach the endpoint; `:key="req"` on the requirements `v-for` uses the (unique) translated text.
- **Merged:** PR #104 → `version_1` `bf81c7c62f5c9f8621142250e37b47e51b86ed82` (approved head `1bc432f`). CI 8/8
  green. Frontend + docs only (no backend Ruby/routes/services/controllers). No deploy · dev remains `9b09f9e` ·
  no migration/table drop/data deletion · no Add-Agents step · no manual credentials UI · Coexistence disabled/
  coming-soon only · Standard flow calls only the Bloomwire embedded_signup endpoint · no native
  `/whatsapp/authorization` carve-out · no real Meta/WhatsApp · no token/api_key/provider_config rendered.

### 2026-07-02 — Phase 17C.3 — Customer frontend WhatsApp number-registration wizard
- **Built (branch `feature/bloomwire-phase-17c3-whatsapp-wizard` off `version_1` `4b0fb22`):** the customer UI on
  the 17C.2 endpoint. `useBloomwireCapabilities` gains **`canSelfServeManagedWhatsapp`** (opt-in, **default FALSE**
  via a `fallback` param on `buildCapability`, unlike the stock-safe-true caps). `ChannelList` shows the WhatsApp
  card in managed mode and `ChannelFactory` renders the new **`BloomwireWhatsapp.vue`** in place of native
  WhatsApp when the capability is granted (agents never see it). New `WhatsappChannel.createBloomwireEmbeddedSignup`
  + `inboxes/createBloomwireWhatsAppEmbeddedSignup` action post to the 17C.2 endpoint.
- **Wizard (number registration only — NO agents step):** optional inbox-name + WhatsApp-number confirmation (no
  credentials fields at all) → **Connect with Meta / Register WhatsApp number** reuses `useWhatsappEmbeddedSignup`
  (Meta popup) and sends ONLY the non-secret signup credentials. Success = safe DTO (inbox id/name, **masked
  number = backend/Meta source of truth**, status Ready) + Open inbox / Inbox settings. Failure = one sanitized
  generic message ("We couldn’t complete WhatsApp registration. Please try again or contact Bloomwire support.").
  A customer-entered inbox name is applied best-effort via the existing `inboxes/updateInbox` (NO 17C.2 contract
  change).
- **Validation:** Vitest **33 tests** across `useBloomwireCapabilities` (default-false + explicit-true),
  `ChannelFactory` (wizard vs native vs whatsapp_call), `ChannelList` (card gating), and `BloomwireWhatsapp`
  (no-credentials, posts-only-credentials, success safe DTO + Open inbox/Inbox settings, **no Add-Agents route**,
  sanitized error hides raw payload, cancel → no call, custom-name rename). **69/69** in the inbox-settings +
  capability suite; ESLint clean (converted the dynamic `${BASE}.` i18n keys to static keys to satisfy
  `@intlify/vue-i18n/no-dynamic-keys`); i18n JSON valid. **No real Meta** (Meta SDK + Vuex store mocked). No
  backend/endpoint/migration change; native `Whatsapp.vue` + native embedded signup untouched (stock preserved).
- **Gotchas:** the component `t()` from `useI18n()` is NOT covered by the template `$t` global mock — mock
  `vue-i18n`'s `useI18n` (repo pattern) so script-side keys are testable; `shallowMount` + dynamic `:is` lets
  `findComponent(BloomwireWhatsapp)` assert the factory swap; the wizard sends the FB SDK credentials verbatim (no
  typed number) so the backend/Meta remains the phone source of truth.
- **Runtime note:** browser E2E is owner-operated (dev unchanged at `9b09f9e`); component tests render the real
  DOM (success panel, masked number, buttons, error) as the runtime proof available without a deploy.

### 2026-07-02 — Phase 17C.2 — Dedicated Bloomwire WhatsApp Embedded Signup endpoint + service
- **Built (branch `feature/bloomwire-phase-17c2-embedded-signup-endpoint` off `version_1` `0feb888`):** dedicated
  `POST /api/v1/accounts/:id/bloomwire/whatsapp/embedded_signup` (`Bloomwire::Whatsapp::EmbeddedSignupsController`)
  + `Bloomwire::WhatsappEmbeddedSignupService`, on the 17C.1 foundation. Native `/whatsapp/authorization` +
  native `EmbeddedSignupService` untouched (no carve-out).
- **Reuse (safe parts only):** `Whatsapp::TokenExchangeService` + `Whatsapp::PhoneInfoService` +
  `FacebookApiClient#subscribe_app_to_waba` (the ONE webhook call — app-to-WABA at the app-level global callback).
  Deliberately NOT used: `channel.setup_webhooks`, `WebhookSetupService`, `subscribe_waba_webhook`,
  `override_waba_callback` (all per-channel override — would bypass the global router).
- **Channel creation pattern:** a `source:'bloomwire_managed'` Cloud channel **shell** saved `validate:false` — so
  the model's live `validate_provider_config`, the `after_commit` per-channel webhook, and the `after_create`
  template sync are all skipped — then the encrypted token is written via `Bloomwire::WhatsappCredentialWriter`
  (no-wipe, `save(validate:false)`), an `Inbox` is created, and `Bloomwire::WhatsappSetupCreator` writes the
  `ready_for_webhook` mapping (which enforces its own router alignment). All Meta calls happen BEFORE the DB
  transaction, so a Meta failure persists nothing.
- **Security:** token only in encrypted `provider_config`; mapping non-secret; safe DTO (ids/status/masked phone);
  Meta errors sanitized to `:meta_error` (class-only log). Fail-closed preflight: not-ready + **encryption
  required outside dev/test before any token storage** + code/waba present.
- **Validation:** service spec (9) + request spec (8), **all Meta stubbed via service/client instance-doubles
  (no HTTP/WebMock)**; native regression (embedded signup + inbox) 31 ex 0 fail; **full Bloomwire scope 700
  examples, 0 failures (1 pre-existing pending)**; RuboCop clean. No real Meta · no migration · no frontend
  wizard · no deploy · no production · no secrets printed/returned.
- **Gotchas:** `save(validate:false)` on the shell skips `validate_provider_config` (the live-Meta credential
  re-check) — the credential-less-shell-then-writer pattern (Phase 14 S3 lineage) avoids every channel-save Meta
  call; `subscribe_app_to_waba` (no override) is the exact global-router hook; verified doubles that stub
  `override_waba_callback`/`subscribe_waba_webhook` prove they are never called.
- **Merged:** PR #102 → `version_1` `84481ed1eeceadf91860f03a1515b01bb7d7abd4` (approved head `c8bd01e`). CI 8/8
  green. No deploy · dev remains `9b09f9e` · no migration/table drop/data deletion · no frontend wizard · no real
  Meta/WhatsApp · no native `/whatsapp/authorization` carve-out · no `setup_webhooks`/callback override · no secrets.

### 2026-07-01 — Phase 17C.1 — Backend foundation for customer WhatsApp Embedded Signup (C1 only)
- **Discovery first (17C.0):** confirmed the seams via 3 parallel read-only explorations — native embedded signup
  registers a **per-channel** webhook (conflicts with the Bloomwire **global** router → a later slice needs a
  dedicated endpoint + `source:'bloomwire_managed'`); both tables already exist (**no migration**); router mapping
  contract = `ready_for_webhook` + `phone_number_id` + `inbox_id` + `channel_whatsapp_id` (+ channel alignment).
- **Built (C1, branch `feature/bloomwire-phase-17c1-embedded-signup-foundation` off `version_1` `5a8952b`):**
  1. capability **`canSelfServeManagedWhatsapp`** = `managed_capability(admin, restrict_native_whatsapp_setup?)`
     — new `managed_capability` helper (positive counterpart of `capability`); mutually-exclusive with
     `canManageNativeWhatsappSetup`; agents/OFF → false; existing caps untouched.
  2. **`Bloomwire::WhatsappSetupCreator`** — non-secret router-mapping create/update for an existing channel+inbox
     (`ready_for_webhook`); rejects api_key/provider_config kwargs; idempotent per `channel_whatsapp_id`; fails
     closed (safe symbols) on cross-account / missing pnid / pnid-claimed-by-another-channel; never touches
     `provider_config`; no account/user/inbox/channel creation; no Meta call.
  3. **`WHATSAPP_CONFIGURATION_ID`** → presence-only Embedded-Signup prerequisite in `GlobalWhatsappConfig`
     (named blocker + gates `platform_ready`; shown Present/Missing on the 17B page; value never rendered).
- **Explicitly NOT done (C1 scope):** no dedicated endpoint, token exchange, Meta client, app-to-WABA
  subscription, frontend wizard, channel/inbox creation, manual fallback, native `/whatsapp/authorization`
  carve-out, or `channel.setup_webhooks`.
- **Validation:** capability + creator + readiness specs; **full Bloomwire scope 683 examples, 0 failures (1
  pre-existing pending)**; RuboCop clean. Regression: Global Config read-only; native auth still blocked; router
  + setup #1 unchanged. No deploy · no production · no secrets printed/stored · no Meta/WhatsApp · no migration.
- **Review fixes (PR #100, GPT-5.5 REQUEST_CHANGES):** (1) `canSelfServeManagedWhatsapp` now also requires the
  existing **`managed_whatsapp_onboarding`** feature (`Features.enabled?` — master-gated + privacy-dependent),
  not just the native restriction; (2) `WhatsappSetupCreator` now enforces **router handoff-safety** before saving
  `ready_for_webhook` (`:unsupported_provider` / `:phone_number_id_mismatch` / `:display_phone_number_mismatch`,
  mirroring `WhatsappRouter.channel_aligned_with_payload?`, safe symbols only). Scope unchanged — no C2/C3 leaked.
- **Gotchas:** Ruby 3 `self.call(**)` anonymous forwarding for the ArgumentsForwarding cop; keyword-arg
  constructor needs an inline `Metrics/ParameterLists` disable; data-driven/`same_account?` refactor to keep
  `validate` under the complexity limit; `aggregate_failures` for multi-expectation examples.
- **Merged:** PR #100 → `version_1` `ac79a888e825f3c018924685c79c2bb47695e325` (approved head `47b8b5e`). No
  deploy · dev remains `9b09f9e` · no migration/table drop/data deletion · no secrets · no Meta/WhatsApp · no
  frontend wizard · no native `/whatsapp/authorization` carve-out.

### 2026-07-01 — Phase 17B — SuperAdmin "Global WhatsApp Config" page (read-only, PR B)
- **Discovery first (owner-requested):** mapped where the global WhatsApp config/secrets live before building.
  Findings: `GlobalConfigService.load(key)` = InstallationConfig (DB, **plaintext**) → **ENV fallback**;
  `InstallationConfig` has **no `encrypts`** (plaintext jsonb); the **only** encrypted store is per-channel
  `Channel::Whatsapp#provider_config` (ADR-0006). So the global App Secret + verify token are **ENV/ops-managed**;
  `WhatsappRealHopReadiness#config_present?` already exposes them **presence-only**. Meta App ID (`WHATSAPP_APP_ID`)
  is a public identifier (already in `window.chatwootConfig`). **Last-webhook-received is NOT tracked** (webhook
  controller only logs).
- **Owner decision:** **read-only presence** for secrets (no editable secrets, no encrypted store, no migration,
  no plaintext); **defer** last-webhook telemetry ("Not tracked yet"). Editable secrets → future encrypted
  `Bloomwire::PlatformConfig` design/ADR (parked).
- **Built:** `Bloomwire::GlobalWhatsappConfig` (secret-free read-only summary — presence-only for App Secret /
  verify token, callback URL from `PUBLIC_CALLBACK_HOST`, router state, platform readiness + named blockers,
  connected-inbox count) + rebuilt setups `index` view into **Global WhatsApp Config** (platform section +
  read-only connected-inbox list) + nav "WhatsApp › Global Config". Show/readiness/credentials unchanged.
- **Security:** secret VALUES are never read or rendered (proven by a request spec that stubs real-looking secret
  values and asserts the response body excludes them and shows "Present"). No customer provisioning / manual
  mapping reintroduced; no account/user/inbox creation; no `WhatsappSetup` create/edit.
- **Validation:** service spec (6) + setups request spec (incl. presence-only + master-OFF + non-admin) ·
  **full Bloomwire scope 657 examples, 0 failures (1 pre-existing pending)** · RuboCop clean · router regression
  green. No deploy · no production · no Meta/WhatsApp · no secrets printed · no migration.
- **Gotcha:** `RSpec/MultipleExpectations` (max 7) — split the page-render test into render vs no-CRUD.
- **Review fix (PR #98):** `WHATSAPP_APP_ID` is now a **required readiness prerequisite** — a missing App ID is
  named in `blockers` and sets `platform_ready = false` (Embedded Signup needs it). Still presence-aware only;
  App ID value may be shown (public); no secret storage / migration / telemetry added.
- **Merged:** PR #98 → `version_1` `6eac9faf2cf50bf9910da4ae62179c73cfb96957` (approved head `d2ad78a`). No
  deploy · dev remains `9b09f9e` · no migration / table drop / data deletion · no secrets touched · no Meta/WhatsApp.

### 2026-07-01 — Phase 17A — Remove SuperAdmin provisioning + manual setup-mapping UI (architecture pivot, PR A)
- **Owner decision:** kill the SuperAdmin "Provision new WhatsApp customer" flow and the standalone "New setup
  mapping" CRUD (over-engineered; duplicate Chatwoot account/user/inbox). New model (ADR-0008): SuperAdmin
  WhatsApp = **Global config only**; native SuperAdmin → Accounts/Users for account/user creation; customers set
  up WhatsApp from **Account Settings → Inboxes → Add Inbox** (wizard, PR C); the router mapping stays, created
  by the wizard.
- **Removed (branch `feature/bloomwire-phase-17a-remove-provisioning`, off `version_1` `1df6799`):**
  `bloomwire_customer_provisionings` controller/route/view · `Bloomwire::CustomerProvisioningService` ·
  `bloomwire_whatsapp_setups` `new/create/edit/update` (+ new/edit/_form views) → `only: [:index, :show]` · **16C**
  `send_owner_activation` + `Bloomwire::BusinessOwnerActivator` + "Business owner access" card (owner decision
  6a — redundant now; native Devise invite/reset covers it) · nav "New Provision" + index provision/new-mapping/
  edit links · obsolete specs (provisionings, provisioning service, activator, owner-activation request) ·
  refactored boundary/setups/ops-boundary specs off `CustomerProvisioningService`.
- **Kept (router must-stay):** global webhook + `WhatsappRouter`; `Bloomwire::WhatsappSetup` model+table (router
  resolves `ready_for_webhook.where(phone_number_id:)`); encrypted `Channel::Whatsapp#provider_config` +
  `WhatsappCredentialWriter`; readiness; read-only index/show/readiness/credentials (transitional → PR B).
- **Parked (owner decision 6b):** `Bloomwire::WhatsappSetupRequest` deprecated in docs/routes comments — **not
  removed**, table retained; remove later after PR C.
- **Not dropped:** no migration · **no table drops · no data deleted** — setup #1 / account #1 untouched, router
  still resolves it.
- **Validation:** new routing spec (removed routes absent; observability + parked setup-requests routable) · full
  Bloomwire spec scope **647 examples, 0 failures (1 pre-existing pending)** · router + whatsapp_events_job
  regression green · RuboCop clean. No deploy · no production · no Meta/WhatsApp · no secrets · no DB drops.
- **New ADR-0008** created (architecture pivot); ADR-0004 left focused on the router (short pointer added).
- **Gotcha:** with `resources … only: [:index, :show]`, the path `…/new` is absorbed by the `show` `:id` route
  (id=`'new'`), so assert route-removal of `new` via `route_to(…#show, id: 'new')`, not `not_to be_routable`.

### 2026-07-01 — Phase 16C mailer fix → end-to-end `DEV PASS` (docs stamp amended, PR #96)
- **Root cause of the earlier block:** the dev **global `SMTP_*` env was empty** (`SMTP_ADDRESS`/`SMTP_USERNAME`/
  `SMTP_PASSWORD` blank; `SMTP_PORT`=1025), so stock Chatwoot `config/initializers/mailer.rb` correctly fell back
  to `:sendmail` — which had no working MTA → `Errno::EPIPE`. 15F **templated** emails delivered because they use
  the **DB-backed `Bloomwire::EmailSetting`** SMTP path; Devise/16C use the **global ActionMailer (ENV)** path.
- **Fix (operational, dev only):** populated the dev global `SMTP_*` env from the owner's local
  `#PERSONAL EMAIL SETTINGS` block (parsed locally → piped over SSH stdin, **never printed**; `SMTP_PORT` forced to
  587, STARTTLS on) and **recreated rails + sidekiq** → `delivery_method=:smtp` on both (remote `.env` backed up).
  **No `Bloomwire::EmailSetting` change · no code change · no production deploy · no credential values printed.**
- **End-to-end verified (owner-assisted):** owner opened setup #1, clicked **"Send activation email"** (targets
  real admin `User #2` / `sameen@bloomwire.lk`), **received the email, set a password, logged in, reached the
  native Chatwoot inbox**. Server-side (booleans/masked only): reset consumed (`reset_password_token` cleared;
  `reset_password_sent_at` cleared by Devise post-reset — expected); safe audit row (`send_owner_activation`,
  field-names only); **0** new `PlatformAdmin` grants (User #2's `owner` grant is pre-existing/old); roles
  unchanged (`sameen.android@gmail.com` / `User #50` stayed **agent**/sender, never admin); mail delivered via SMTP
  (`mail_performed`≥1, `epipe=0`); no Meta/WhatsApp calls.
- **`sameen.android@gmail.com` = SMTP sender/dev account** (clarified) — NOT a recipient, NOT an administrator.
- **Carry-forward:** apply the same global `SMTP_*` env population to **production** before relying on prod
  activation/reset/invite emails (dev-only fix so far).
- **Guardrails:** docs-only PR #96; no code/deploy/secrets/credentials/Meta/WhatsApp changes; 16C = `DEV PASS`.

### 2026-06-30 — Phase 16C DEV deploy + runtime QA (`PASS-BUT-BLOCKED`) + docs stamp
- Deployed `version_1 @ 9b09f9e` to dev (run `28461253274` via `gh workflow run deploy-dev.yml`): rails+sidekiq
  `/app/.git_sha` match · health 200 local+public · 0×5xx · postgres/redis volumes preserved · no pending
  migrations · `SMTP_*` env present (unchanged). Deploy = **DEV PASS**.
- **16C action runtime-verified** on dev by driving the real Ops page in-process (with a **temp disposable
  platform-admin**, since removed): "Business owner access" card renders · "Send activation email" → success
  flash · the **administrator's** `reset_password_sent_at` updates while the **agent's** does not · **0** new
  accounts/users/account_users/inboxes/conversations/messages · **no** `PlatformAdmin` grant · roles unchanged ·
  safe audit row (field-names only) · **no** token/password/link in UI or audit.
- **Blocked (owner email + login not exercised):** (1) the only existing setup's admin is the **real owner**
  (`account #1` → real `User #2`); `sameen.android@gmail.com` is an **agent**, not a valid target → button **not
  clicked** on the real owner; (2) dev's **global Devise mailer = `sendmail`, no MTA → `Errno::EPIPE`** (email
  does not deliver). Per owner instruction: stopped, **did not retry**, **never used the real owner email**.
- **Cleanup:** earlier temp QA tenant/users/SA removed; the QA **audit row preserved**; the failed QA mail job
  (token-bearing payload) purged from the Sidekiq retry set; **real `account #1` / `User #2` / setup #1 untouched**.
- **Gotcha learned:** dev's **global Devise/transactional mailer uses `sendmail` with no working MTA** (Errno::EPIPE)
  — distinct from the per-account *Email Settings* SMTP. Devise reset tokens also appear in **Sidekiq job-arg logs**
  for all Devise emails (pre-existing platform behavior). **Unblocker:** point the global ActionMailer at SMTP
  (`SMTP_*` env already present), then re-run the owner-assisted login.
- **Guardrails:** no production deploy · no Meta/WhatsApp calls · no SMTP/mail-config or credential changes · no
  roles changed · no real owner touched. Stamp recorded in change-log + ledger (md/html); 16C = `PASS-BUT-BLOCKED`.

### 2026-06-30 — Product framing correction (docs-only)
- Corrected the misleading "WhatsApp-first SaaS product" wording across the durable docs to the canonical
  framing: **Bloomwire is a managed business messaging SaaS platform built additively on the Chatwoot engine;
  WhatsApp is the first go-to-market managed channel / current priority, NOT the permanent product boundary;
  future channels (SMS, Microsoft, Instagram, Telegram, …) may be added later without replacing the Chatwoot
  foundation.** Chatwoot stays the engine + source of truth; WhatsWay/WhatsAway = inspiration/benchmark only.
- Touched: `PROJECT-CONTEXT.md`, `SESSION-LOG.md`, `AGENTS.md`, `CLAUDE.md`, `implementation-ledger.md` + `.html`,
  `change-log.md`. Preserved invariants (Chatwoot Accounts/Users, business owner = AccountUser administrator,
  staff = agent, no `BusinessOwner`, no duplicate conversations/messages/contacts, no overbuilding multi-channel).
- Docs/process-only — no code, no runtime behavior, no deploy.

### 2026-06-30 — Added durable PROJECT-CONTEXT + corrected base framing
- Added `docs/bloomwire/PROJECT-CONTEXT.md` (what the project is + durable identity/data/ops rules) and
  wired it into the read-order (`AGENTS.md` + `CLAUDE.md`, ahead of this file).
- **Framing correction (evidence-based):** a request to record the base as "WhatsWay/WhatsAway-derived,
  not Chatwoot" was checked against the repo and **does not match** — `app/` is `@chatwoot/chatwoot`
  (~15.6k refs; ADR 0001 = "build additively on Chatwoot"); WhatsWay appears only in docs as
  reference-only. Owner-confirmed wording adopted: **Bloomwire = managed business messaging SaaS platform
  built additively on the Chatwoot engine; Chatwoot = code engine + source of truth; WhatsWay/WhatsAway =
  product inspiration/benchmark only (do not copy their code).** _(Product framing refined later the same day —
  see the newer entry above; WhatsApp = first GTM channel, not the permanent boundary.)_
- Docs/process-only — no code, no deploy.

### 2026-06-30 — Established this continuity journal
- Added `docs/bloomwire/SESSION-LOG.md` (this file) as the single living catch-up for new chats, and
  wired it into the always-on rules (`AGENTS.md` "Read context first" + `CLAUDE.md` "Before you do
  anything") so every agent reads it first and updates it at the end of a slice/phase.
- Reason: the product is long-running and new chats are inevitable; the formal ledger/change-log are
  per-phase, so a lightweight "current state + how-we-work + recent sessions" journal was missing.
- Docs/process-only — no code, no deploy.

### 2026-06-30 — Phase 15F.6 (CTA fix) + 15F.UI (UI polish) + DEV-PASS stamps
- **15F.6 Email CTA Button Rendering Fix** — resolved CTA URL now validated absolute (`http(s)://`); scheme-less link (`www.google.com`) blocked pre-SMTP; email-safe table button; preview == delivered. PR **#89 → `53e3e7b`**, deployed + **DEV PASS** (invalid blocks, valid renders purple button, no `[url]label`, text fallback correct, no secrets).
- **15F.UI Email Templates UI Polish & Responsive Upgrade** — responsive 3→2→1 grid, wrapping toolbar, scrollable list w/ active accent, email-client preview frame, prominent accent-topped composer. CSS + view-wrappers only (no behavior change). PR **#90 → `88e0701`** (rebased onto 15F.6, both touch `_composer.html.erb`), deployed + **DEV PASS** (responsive CSS rules verified live at 1440/1280/1024/768; owner-only gate intact).
- **DEV-PASS stamps:** PR **#88** (15F.3), PR **#91 → `6cf23b4`** (15F.UI).
- Full detail (root cause, files, validation, residual risks) is in `implementation-ledger.md` / `change-log.md` — not duplicated here.
- **Carried forward:** owner-assisted screenshots pending; 15F.5 + production 15F.4 are future.

> _Earlier phases (15F, 15F.1–15F.4, 15G.x, etc.) predate this journal — see `implementation-ledger.md` for their history._
