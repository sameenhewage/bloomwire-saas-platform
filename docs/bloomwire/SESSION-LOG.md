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

- **`version_1` tip:** `4525bea6baf8c17315436982f0d70106508b9c57`  (PR #116 merged — Phase 17E.4 contact ID hardening)
- **Dev deployed SHA:** `4525bea6baf8c17315436982f0d70106508b9c57` (`4525bea`)  (public: https://dev.unecast.com · health `/health`) — deployed in **Phase 17E.4D** (dev-only via `deploy-dev.yml`, run `28684004558`; `/app/.git_sha` verified; health 200; no pending migrations; postgres/redis volumes preserved). **`BLOOMWIRE_RESTRICT_AGENT_CONTACT_VISIBILITY=true` is now permanently enabled on dev** (runtime resolves true; never enabled in prod). Was `3c45720`. Production untouched.
- **Latest completed / merged:** **PR #116** — Phase **17E.4** contact ID hardening (product code; gated), merged at `4525bea6baf8c17315436982f0d70106508b9c57`, and **deployed + authenticated-runtime-smoke PASS on dev in Phase 17E.4D**. Before it: PR #115 (17E.3, `3c45720`); PR #114 (17E.2, `d98f7d8`); PR #113 (17E.1, `5df9f9d`); PR #112 (17E.0, `8349689`); PR #111 (17D.3, `ea30579`); PR #109 (17D.2, `4a57564`); PR #107 (17D.1, `ebdcba2`); PR #106 (17D.0, `f9aeac7`); PR #104 (17C.3, `bf81c7c`); PR #102 (17C.2, `84481ed`); PR #100 (17C.1, `ac79a88`); PR #98 (17B, `6eac9fa`); PR #97 (17A, `8719de2`).
- **In-flight / open (NOT merged):** none for product code — **Phase 17E.4 (PR #116) is merged + deployed to dev (17E.4D)**. The only open PR is the **17E.4D docs-only governance PR** (this change; **do not auto-merge**). Runtime 17E.2 + 17E.4 contact isolation is now **live on dev with the gate ON**, validated end-to-end by the authenticated smoke (agent out-of-scope merge/attach → 404, Shopify → 422 no-egress, contact/conversation isolation; admin unchanged).
- **17B secret-storage decision (owner-approved):** no encrypted global-secret store exists (InstallationConfig is plaintext; App Secret + verify token are **ENV/ops-managed**, read via `GlobalConfigService`). PR B is **read-only presence-only** — never displays/saves secret values; **no plaintext storage, no migration, no new store**. Editable secrets = parked (future encrypted `Bloomwire::PlatformConfig` design/ADR).
- **Architecture (ADR-0008):** SuperAdmin WhatsApp = **Global WhatsApp Platform Config only** (17B builds it); account/user creation stays **native**; customers set up WhatsApp via **Account Settings → Inboxes → Add Inbox** (PR C, Embedded Signup first); the internal mapping is created by the wizard, not Ops UI. `Bloomwire::WhatsappSetupRequest` **deprecated/parked** (removed after PR C).
- **Working tree:** clean.
- **Next up (not started — pick with owner):**
  1. **Multi-WhatsApp-inbox (17E):** **17E.0..17E.4 merged** (17E.4 = PR #116, `4525bea`, **deployed to dev in 17E.4D with the contact-visibility gate ON; authenticated runtime smoke PASS**). The deferred ID-based gaps (contact merge / conversation-create / Shopify orders) are now closed + validated live; CSAT stays admin-only. Next: **owner-operated real-Meta browser E2E on dev** + Coexistence go-live readiness (**17C.4**) before customer go-live.
  2. **Coexistence go-live:** **17C.4** verify / go-live UX (surface real-hop readiness + a "send a test message" / webhook-received confirmation), and remove the parked `WhatsappSetupRequest`. **Before real customer tokens are stored:** ensure the Meta app config (incl. `WHATSAPP_CONFIGURATION_ID`) + AR encryption keys are set in the target env (the service fails closed on encryption outside dev/test), and run owner-operated real-Meta E2E in a browser (no automated real-Meta calls).
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
