# Bloomwire — Parked Items (Parking Lot)

> **STATUS: living tracker.** Items here are intentionally **parked** (deferred) with an explicit *unpark
> condition*. Parking an item is a decision, not a gap — each entry records why it waits, the evidence we
> already have, what is missing, and the exact trigger to resume. All identifiers are **masked / presence-only**;
> no secrets, tokens, `provider_config`, full phone numbers, or payloads appear in this file.

**Scope note (read first):** Parking the items below **does not block normal WhatsApp session chat.**
Inbound → outbound → `sent`/`delivered`/`read` is already live-proven on the dev stack. The parked work only
affects **out-of-window / business-initiated template messaging** and later product/ops follow-ups.

Each parked item documents: **why parked · evidence we have · what is missing · exact unpark condition ·
next action when unparked · owner type · risk · blocks core 24h session chat?**
Owner types: **Bloomwire Ops** · **Meta admin** · **Product**.

---

## Status board

| ID | Item | Category | Status | Owner | Risk | Blocks core 24h chat? |
|---|---|---|---|---|---|---|
| **PARK-13E** | Out-of-window / business-initiated **template messaging** (live cert) | A. External Meta/WABA | **Parked** — blocked by WABA template availability | Meta admin → Bloomwire Ops | Low | **No** |
| **PARK-13E.4** | Business-owner **template request/approval** workflow | B. Product feature | **Parked** — later product feature | Product → Eng/Ops | Medium | **No** |
| **PARK-SEC-NONWA** | Non-WhatsApp channel secret-at-rest / scrub before managed enable | C. Security/privacy | **Parked** — pre-req before enabling those channels | Bloomwire Ops + Eng | Medium | **No** |
| **PARK-SEC-ADR6** | ADR-0006 production rollout (encryption keys + `provider_config` backfill) | C. Security/privacy | **Parked** — before first real customer token at rest | Bloomwire Ops | Medium | **No** |
| **PARK-OPS-ONBOARD** | Onboarding runbook: "≥1 approved template before go-live" + 13E.3 live runbook | D. Ops/onboarding | **Parked** — authored when PARK-13E unparks | Bloomwire Ops | Low | **No** |
| **PARK-WA-SETUP-REQUEST** | Remove the deprecated `Bloomwire::WhatsappSetupRequest` intake queue (model + SuperAdmin views + account API) — superseded by the customer Add-Inbox wizard (Phase 17A / ADR-0008) | D. Ops/onboarding | **Parked** — remove after PR C wizard ships (code + separate data-cleanup migration; no table drop yet) | Eng | Low | **No** |
| **PARK-INT-APIVER** | Template-management Graph version still pinned `v14.0` (`business_account_path`) | E. Internal upgrade/fallback | **Parked** — non-urgent version hardening | Eng | Low | **No** |
| **PARK-INT-ROLLBACK** | Toggle-OFF / rollback testing for the template path | E. Internal upgrade/fallback | **Parked** — deferred by request | Bloomwire Ops + Eng | Low | **No** |
| **PARK-ENG-ONBOARD-RESUMABLE** | Idempotent/resumable WhatsApp onboarding + Meta side-effect-after-timeout protection (async Sidekiq **or** endpoint-specific timeout; no duplicate Channel/Inbox/Setup) | F. Engineering reliability | **Parked** — post-demo hardening; do **not** change the working flow first | Eng → Bloomwire Ops | Medium | **No** |

---

## A. External Meta / WABA blockers

### PARK-13E — WhatsApp templates / out-of-window messaging (live certification)

**One-line:** the OSS template path is proven in-code under managed mode, but **no approved template exists on
the dev WABA**, so live out-of-window certification cannot run yet. The blocker is **external (Meta-side)**, not code.

**Sub-status**
- **13E.1 — managed-mode template-send proof:** **COMPLETED / MERGED** to `version_1` (`164968c`). Spec
  `app/spec/integration/bloomwire/whatsapp_template_out_of_window_e2e_spec.rb` (9 examples, 0 failures; RuboCop
  clean), all Bloomwire toggles ON, stubbed Graph, no Meta egress.
- **13E.2 — sync path:** code **READY**; scheduled sync **HEALTHY** (channel auto-resyncs when templates are
  `>3h` stale; admin `sync_templates` endpoint + provider `sync_templates` intact).
- **Runtime blocker (deployed `b121b1f`, inspected 2026-06-28, read-only):** channel_id `1` / inbox_id `1`
  (`whatsapp_cloud`), **total_templates = 0, approved = 0**, `last_synced = 2026-06-28 10:25:23 UTC`.
- **13E.3 — live template send:** **PARKED** until an approved template exists on the WABA.
- **13E.4 — business-owner template request workflow:** **PARKED** as a later product feature (see PARK-13E.4).

**Why it is parked**
The OSS resolver `Whatsapp::TemplateProcessorService#find_template` only matches a template whose `name` (exact),
`language` (case-insensitive) and `status == approved` exist in `channel.message_templates`. With `approved = 0`
there is nothing to send, so a live out-of-window send would fail by design. This is an availability gap on the
**WABA in Meta**, not a defect in Bloomwire code.

**Evidence we already have**
- 13E.1 merged spec proves end-to-end under managed mode (toggles ON, no Meta): template path is used (not
  session), `template_params` stored, returned `wamid` stored in `source_id`, `sent → delivered → read`
  reconciliation on the template `wamid`, managed-mode restrictions do **not** block the send, and missing /
  unapproved templates **fail safely** with a clear `external_error`.
- 13E.2 read-only deployed inspection (above): sync is healthy; the WABA simply returns 0 templates.
- Sync mechanism verified in code: `POST inboxes/:id/sync_templates` (admin-only), `TemplatesSyncSchedulerJob`
  (≤3h staleness via the `*/5` cron), `TemplatesSyncJob → channel.sync_templates`.
- Log hygiene already enforced for the webhook/broadcast path (Phase 13D / 13D.2): no payload PII in logs.

**What is missing**
1. **≥1 APPROVED template on the WABA** (name + language + category + body/components), synced into
   `channel.message_templates`.
2. **Human-operated 13E.3 live certification:** out-of-window conversation → pick approved template → send →
   physical phone receives → `sent/delivered/read`; masked evidence; logs confirmed PII-clean.

**Exact unpark condition**
The read-only inspection on the deployed channel shows **`approved >= 1`** (i.e., a concrete approved template
`name` + `language` is available on channel `1`).

**Next action when unparked**
1. (With explicit approval) run a fresh sync if needed, then re-run the read-only inspection to confirm
   `approved >= 1` and capture the template `name`/`language`.
2. Prepare the 13E.3 live runbook + masked evidence template (currently **not** prepared, by instruction).
3. Human-operated 13E.3 live out-of-window send + evidence capture. **No agent-initiated Meta calls** without
   explicit approval.

**Owner type:** **Meta admin** (create/approve the template) → then **Bloomwire Ops** (sync + run live cert).
Product is **not** required for 13E.3.

**Risk level:** **Low.** The feature is already proven in-code; the only dependency is the existence of an
approved template. No code change is expected to unpark.

**Blocks core 24h session chat?** **No.** Normal session chat (inbound → outbound → sent/delivered/read) is
already live-proven; this item only affects out-of-window / business-initiated template messaging.

**Meta-side decision tree (for the operator, when checking WhatsApp Manager for this WABA)**
- **Meta shows 0 templates** → create one and wait for **APPROVED** (prefer the prebuilt `hello_world` if
  offered; otherwise a custom **UTILITY** template such as `bloomwire_test_utility` for fastest review).
- **Meta shows templates but Bloomwire sync = 0** → treat as a **credentials/config mismatch**, not
  availability: verify `provider_config['business_account_id']` matches the WABA and the access token has
  `whatsapp_business_management` / template-read scope — **presence/match only, never print the values** — then sync.

---

## B. Product feature follow-ups

### PARK-13E.4 — Business-owner template request / approval workflow

**Why it is parked**
This is a larger product feature and is **not** required for basic out-of-window sending (which works with any
already-approved template). It is deferred until Product decides Bloomwire should own the template lifecycle.

**Evidence we already have**
- 13E investigation: there is **no** general business-facing template request/create surface in OSS (only CSAT
  has a programmatic create path). ADR-0004 provides the precedent for a Bloomwire-owned, references-only,
  no-secrets table.

**What is missing**
- A `Bloomwire::WhatsappTemplateRequest` model (ADR-0004 style: FKs only, no secrets, no Chatwoot duplication).
- A business request endpoint + an **Ops-only** review/approve/create-on-Meta surface (CREATE gated to Ops,
  since it uses the WABA access token / Meta infra).
- Request→Meta status tracking.

**Exact unpark condition**
A Product decision to build Bloomwire-managed template lifecycle, captured as a PRD/issue (+ ADR for the model).

**Next action when unparked**
Author PRD + ADR; then implement in vertical slices (mirroring the 12C/12D Ops-surface pattern) with toggle-gated,
Ops-only CREATE and OFF == stock behavior.

**Owner type:** **Product** (decision) → **Eng + Bloomwire Ops** (build).
**Risk level:** **Medium** (new table + create-on-behalf-of on Meta; must gate CREATE to Ops and follow ADR-0004).
**Blocks core 24h session chat?** **No.**

---

## C. Security / privacy follow-ups

### PARK-SEC-NONWA — Non-WhatsApp channel secret-at-rest / scrub before managed enable
- **Why parked:** documented out-of-scope in Phase 13B.5; the encryption (ADR-0006) + scrub work so far targets
  the WhatsApp channel. Other provider channels are not enabled in managed mode yet.
- **What is missing:** decide + apply secret-at-rest + response scrubbing for non-WA channels **before** enabling
  them in managed mode.
- **Unpark condition:** a decision to offer a non-WA channel in managed mode.
- **Owner:** Bloomwire Ops + Eng · **Risk:** Medium · **Blocks core chat?** No.

### PARK-SEC-ADR6 — ADR-0006 production rollout (encryption keys + provider_config backfill)
- **Why parked:** before the first **real** customer token is stored at rest, AR encryption keys must be
  provisioned and existing plaintext `provider_config` rows backfilled to encrypted form.
- **Evidence:** ADR-0006 accepted (Option A implemented); 13B.1 verified encryption + backfill transition with
  ephemeral keys.
- **What is missing:** production key provisioning + a one-time backfill on the target environment (Ops runbook step).
- **Unpark condition:** first real-customer onboarding is scheduled.
- **Owner:** Bloomwire Ops · **Risk:** Medium · **Blocks core chat?** No.

---

## D. Ops / onboarding runbook follow-ups

### PARK-OPS-ONBOARD — Onboarding pre-req + 13E.3 live runbook
- **Why parked:** the 13E.3 live runbook is intentionally **not** authored yet (parked with PARK-13E), and the
  onboarding runbook does not yet call out the approved-template prerequisite.
- **What is missing:** (1) add an explicit onboarding step — "confirm `approved >= 1` template on the WABA before
  enabling out-of-window/business-initiated messaging"; (2) author the 13E.3 human-operated live runbook +
  masked evidence template when PARK-13E unparks.
- **Unpark condition:** PARK-13E reaches `approved >= 1`.
- **Owner:** Bloomwire Ops · **Risk:** Low · **Blocks core chat?** No.

### PARK-WA-SETUP-REQUEST — Remove the deprecated `Bloomwire::WhatsappSetupRequest` intake queue
- **Why parked:** Phase 17A (ADR-0008) retired the Ops-driven onboarding; the "request managed setup" intake
  queue is superseded by the customer-side **Add Inbox wizard** (PR C). Deprecated now but **kept** (routes,
  SuperAdmin views, account API, model, table) so nothing breaks before the wizard ships.
- **What is missing:** after PR C is proven, remove `Bloomwire::WhatsappSetupRequest` (model + `super_admin`
  controller/views + `api/v1/accounts/bloomwire/whatsapp_setup_requests` + specs), then a **separate data-cleanup
  migration** to drop `bloomwire_whatsapp_setup_requests` (no table drop in 17A; preserve any existing rows until
  then).
- **Unpark condition:** PR C (customer Add-Inbox wizard) merged + DEV-proven.
- **Owner:** Eng · **Risk:** Low · **Blocks core chat?** No.

---

## E. Internal upgrade / fallback testing

### PARK-INT-APIVER — Template-management Graph version pinned `v14.0`
- **Why parked:** Phase 13B.3 made the outbound message + media Graph version configurable
  (`WHATSAPP_CLOUD_API_VERSION`, default `v24.0`), but the **template-management** path
  (`business_account_path`, mirrored by the CSAT template service) still uses `v14.0`. It works; bumping it is
  non-urgent hardening.
- **What is missing:** make the template-management version configurable/aligned + regression test.
- **Unpark condition:** a version-hardening pass (or Meta deprecation of `v14.0`).
- **Owner:** Eng · **Risk:** Low · **Blocks core chat?** No.

### PARK-INT-ROLLBACK — Toggle-OFF / rollback testing for the template path
- **Why parked:** deferred by instruction; no rollback/toggle-off testing during the current template phase.
- **What is missing:** verify OFF == stock Chatwoot for the template send/sync surfaces, and a clean rollback drill.
- **Unpark condition:** scheduled hardening/rollback-drill window.
- **Owner:** Bloomwire Ops + Eng · **Risk:** Low · **Blocks core chat?** No.

---

## F. Engineering reliability / onboarding robustness

### PARK-ENG-ONBOARD-RESUMABLE — Idempotent/resumable onboarding + Meta side-effect-after-timeout protection

**Implementation status (2026-07-09):** the **immediate synchronous hardening** is now IMPLEMENTED on branch
`fix/bloomwire-whatsapp-onboarding-resilience` (per-call Graph HTTP timeouts + sanitized timeout error;
endpoint-specific 75s timeout with the global Rack::Timeout untouched; subscribe-skip-if-already-subscribed; the
existing skip-register-if-CONNECTED + reconnect-reuse; DB uniqueness already guarantees no duplicates) — see
[`adr/0010-whatsapp-onboarding-resilience.md`](adr/0010-whatsapp-onboarding-resilience.md). Tests green, RuboCop
clean, **not merged, not deployed**. **What remains parked here is Section B of ADR-0010: the asynchronous Sidekiq
onboarding workflow (202 + poll).**

**One-line:** the Standard Embedded Signup runs **all** Meta steps (`/register`, subscribe app→WABA, capability check) **and** the DB writes **synchronously inside one web request** bounded by the **15s `Rack::Timeout`**. If Meta completes a side effect (e.g. `/register`) but the request is killed before persistence, Meta state and Bloomwire DB **diverge** (number CONNECTED on Meta, **0** records in Bloomwire). This is a **reliability/architecture** follow-up, not a defect blocking the demo.

**Why it is parked**
The current flow is **demo-proven** (the token-debug-OFF retry finished in ~10.8s → 201 → exactly one Channel/Inbox/Setup). Reworking it to idempotent/async is a non-trivial change to the working onboarding path and must **not** risk the demo. Deferred to a controlled post-demo hardening window with explicit owner approval. **Per owner instruction: do not change the currently working onboarding flow before the demo.**

**Evidence we already have (DEV, 2026-07-09 — masked)**
- **Split-state incident:** the **first** real Standard attempt exceeded the **15s `Rack::Timeout`** *during* Meta `/register` (`facebook_api_client.rb` `post_phone_messaging_product` → `register_phone_number`); the browser got **HTTP 500** and Bloomwire persisted **0** records (fail-closed). **But Meta had already received `/register`** → the number became **CONNECTED**. Result: Meta = CONNECTED, Bloomwire = empty (no Inbox/Channel/Setup).
- **Mitigation, not a fix:** DEV token-debug (`BLOOMWIRE_WHATSAPP_TOKEN_DEBUG`) added ~9s of extra Graph calls; turning it **OFF** let the retry finish in **~10.8s** (`Completed 201`). A slower Meta `/register` on a genuinely **cold** path (register actually runs) could still exceed 15s.
- **The retry converged cleanly:** it took the **warm path** (number already CONNECTED → Phase-4 skip of `/register`) and the existing Phase-6 `Bloomwire::WhatsappSignupPersistence` reconnect logic produced **exactly one** Channel/Inbox/Setup (no duplicate) for the same-account, same-number re-onboard.

**What is missing**
1. **Idempotent/resumable onboarding** — persist an onboarding attempt/intent (keyed by `phone_number_id`) **before** the Meta side effects, or make each step resumable, so a timed-out request can be safely **resumed** without re-triggering side effects or creating duplicates.
2. **Side-effect-after-timeout protection** — move the Meta calls off the synchronous request path (preferred: an **async Sidekiq workflow** with status polling), **or** apply an **endpoint-specific timeout** large enough to bound the whole flow, so the request can't be killed mid-side-effect.
3. **Safe retries when already CONNECTED / already subscribed** — the flow already skips `/register` when CONNECTED (Phase 4) and verifies subscription; formalize these as **explicit idempotent guards** with tests so a retry after a partial/timed-out attempt always **converges** without error or duplicate.
4. **No duplicate Channel/Inbox/Setup** — covered today by `WhatsappSignupPersistence` reconnect; add explicit **regression tests for the timeout-then-retry path** (Meta CONNECTED + 0 records → retry → exactly one of each).

**Exact unpark condition**
After the company demo, when the owner approves onboarding-reliability hardening — **or** when a real cold-path onboarding is observed to time out (register actually runs and the request exceeds the request budget).

**Next action when unparked**
1. Design doc / **ADR**: choose **async Sidekiq workflow** (preferred — decouples from `Rack::Timeout`) vs **endpoint-specific timeout**; define the onboarding-attempt **state machine** (`pending → meta_registered → subscribed → capable → ready`) with idempotent, resumable transitions keyed by `phone_number_id`.
2. **TDD**: specs for timeout-then-retry convergence, already-subscribed retry, already-CONNECTED retry, and the no-duplicate guarantee.
3. Implement behind the existing managed toggles; **OFF == stock**; no schema unless the attempt state needs a table (add an **ADR** if so).

**Owner type:** **Eng** (design + build) → **Bloomwire Ops** (deploy + validate).
**Risk level:** **Medium** (touches the working, demo-proven onboarding path; async introduces polling/state — must not regress).
**Blocks core 24h session chat?** **No.** Session chat (inbound → outbound → sent/delivered/read) is live-proven; this is onboarding-robustness only.

---

## Change log
- 2026-06-28 — Created parking lot; parked Phase 13E (13E.1 merged; 13E.2 code-ready/sync-healthy; runtime
  blocker WABA templates total=0/approved=0; 13E.3 + 13E.4 parked) and recorded the standing
  security/ops/internal follow-ups.
- 2026-07-09 — Added **PARK-ENG-ONBOARD-RESUMABLE** (F. Engineering reliability) after the DEV Standard-onboarding
  **split-state** incident: first attempt hit the 15s `Rack::Timeout` during Meta `/register` → Meta CONNECTED but
  **0** Bloomwire records; the token-debug-OFF retry (warm path) finished in ~10.8s and produced exactly one
  Channel/Inbox/Setup. Parked as **post-demo** hardening (idempotent/resumable onboarding, side-effect-after-timeout
  protection, safe already-CONNECTED/subscribed retries, no duplicate records). The working flow is unchanged.
