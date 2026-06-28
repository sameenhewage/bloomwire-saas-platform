# Phase 13C — Human-Operated Live Meta Certification

> **STATUS: PASS-BUT-BLOCKED (prepare-for-later).** The repo/code side is **READY**; live execution is
> **BLOCKED** pending real human-operated Meta assets + a deployed target environment + a physical test phone.
> **No live Meta call has been made and no live PASS is claimed.** This document is the operator's certification
> pack: it records what is verified now (code/repo), and provides the runbook + evidence templates + checklists
> for the human operator to fill **on a real environment**. The agent does not call Meta and does not read or
> print `.env` secrets. All identifiers in this doc are masked placeholders.

- Base: `version_1` (PR #62 merged — Phase 13B internal hardening complete).
- Verified commit: `decf62a` (Merge PR #62). Phase 13B commits `9bd0ce8`, `64a52a0`, `1dc5ce5`, `7706824` all present.
- Companion docs: live-hop runbook [`phase-12g-live-hop-readiness-package.md`](./phase-12g-live-hop-readiness-package.md);
  baseline + §9 evidence target [`phase-3a-whatsapp-cloud-e2e-baseline.md`](./phase-3a-whatsapp-cloud-e2e-baseline.md);
  inbound real proof [`phase-10b-dev-deployment-stabilization.md`](./phase-10b-dev-deployment-stabilization.md);
  secret-at-rest [`../adr/0006-whatsapp-provider-secret-at-rest.md`](../adr/0006-whatsapp-provider-secret-at-rest.md).

---

## 1. Executive verdict

- **Verdict: PASS-BUT-BLOCKED.** Code/repo certification is complete and green; live Meta certification
  (13C.1–13C.4) requires the human operator and is not performed here.
- **Ready for PEPPER ST. / first-customer onboarding?** **Not yet.** Onboarding is gated on the live evidence
  below being captured on a real environment, **and** on the ADR-0006 production rollout (encryption keys
  provisioned + provider_config backfill) before any real customer token is stored at rest.
- **What remains blocked:** real inbound re-confirm on current SHA, real outbound session reply, real status
  webhook (sent/delivered/read/failed), template/out-of-window send, and the privacy/rollback proofs **on the
  live environment** — all human-operated. See §3 evidence table (all live rows = PENDING).

---

## 2. Environment summary (operator fills the live values, masked)

| Field | Value |
|---|---|
| Environment name | `<masked, e.g. dev.****>` |
| Commit SHA deployed | `<fill: should be decf62a or later version_1>` |
| Public callback host (masked) | `https://****.<host>/bloomwire/webhooks/whatsapp` |
| Chatwoot edition | **Community/OSS only** — `DISABLE_ENTERPRISE=true` (see §4) |
| AR encryption configured | `<yes/no — Chatwoot.encryption_configured? == true>` |
| provider_config encrypted-at-rest (fake token first) | `<yes/no — see §5 step E2>` |
| WABA id (masked) | `<masked ****>` |
| phone_number_id (masked) | `<masked ****>` |
| Business WhatsApp number (masked) | `+****<last4>` |
| Test phone (masked) | `+****<last4>` |

> Do **not** paste real tokens, app secret, verify token, full phone numbers, WABA id, or `phone_number_id`.
> Record last-4 / tails only.

---

## 3. Live evidence table (operator fills — all live rows PENDING)

| Test | Result | Evidence | Masked identifiers | Notes |
|---|---|---|---|---|
| 13C.0 Pre-live gate (repo/code) | **PASS** | §6 (verified by agent) | commit `decf62a` | code/repo side only |
| 13C.0 Pre-live gate (env/human) | **PENDING** | §6 operator checklist | — | needs target env |
| 13C.1 Real inbound re-confirm | PENDING | conversation/message id + log | pnid `****`, from `+****` | re-run Phase 10B on current SHA |
| 13C.2 Real outbound session reply | PENDING | wamid tail + phone photo + log | conv `****`, wamid `…<tail>` | within 24h window |
| 13C.3 Status: sent | PENDING | status + ts | wamid `…<tail>` | |
| 13C.3 Status: delivered | PENDING | status + ts | wamid `…<tail>` | |
| 13C.3 Status: read | PENDING | status + ts | wamid `…<tail>` | only if phone opens msg |
| 13C.3 Status: failed (if safe) | PENDING | status + redacted error | wamid `…<tail>` | only if safely testable |
| 13C.4 Template / out-of-window | PENDING **or BLOCKED** | template receipt + status | template `<masked>` | BLOCKED if no approved template |
| 13C.5 Failure/retry | **PASS (stubbed, 13B)** + live-safe check PENDING | §9 | — | do not abuse real Meta |
| 13C.6 Privacy/permission | PARTIAL (code PASS) + live PENDING | §10 | — | API/log capture on live env |
| 13C.7 Rollback drill | PARTIAL (code PASS) + live PENDING | §11 | — | toggle OFF on live env |

---

## 4. OSS-only / no-Enterprise verification (Q3)

**Requirement:** the target runs Chatwoot Community/OSS code paths only; the `enterprise/` overlay must not be
eager-loaded, and Bloomwire must not depend on / import / modify / call Enterprise code.

**Code-side (verified by agent — PASS):**
- Phase 13B changed files contain **zero** `enterprise`/`Enterprise::` references.
- The Bloomwire global router (`app/services/bloomwire/webhooks/whatsapp_router.rb`), the Bloomwire webhook
  controller, `Webhooks::WhatsappEventsJob`, and `Whatsapp::IncomingMessageBaseService` are **OSS-only**.
- The Bloomwire WhatsApp path uses only OSS classes: `Channel::Whatsapp`, `Webhooks::WhatsappController` /
  `Bloomwire::Webhooks::WhatsappController`, `SendReplyJob`, `Whatsapp::SendOnWhatsappService`,
  `Whatsapp::Providers::WhatsappCloudService` (+ `BaseService`). None of the enterprise **voice** methods
  (`pre_accept_call`, `initiate_call`, …) are invoked anywhere in the Bloomwire path.
- The only enterprise touchpoints are the **stock** conditional extension points
  `…WhatsappCloudService.prepend_mod_with(...)` and `…WhatsappEventsJob.prepend_mod_with(...)` — these are
  upstream Chatwoot, not Bloomwire-added, and only attach the enterprise overlay **if it is loaded**.

**Loading rule (important):** `ChatwootApp.enterprise?` returns true whenever `enterprise/` **exists in the repo
tree** (it does) **unless `DISABLE_ENTERPRISE` is set** (`app/lib/chatwoot_app.rb:14-17`). Therefore, to
guarantee OSS-only on the target:

**Operator action — set in the target env (do once):**
```
DISABLE_ENTERPRISE=true
```
**Operator verification — in the target rails console (record masked output):**
```ruby
ChatwootApp.enterprise?                                   # expect: false
Whatsapp::Providers::WhatsappCloudService.ancestors.map(&:to_s).grep(/Enterprise/)   # expect: []
Webhooks::WhatsappEventsJob.ancestors.map(&:to_s).grep(/Enterprise/)                 # expect: []
```
- Enterprise specs/failures (e.g. `spec/enterprise/**`) are **not** Bloomwire CE/OSS blockers and must not be
  treated as such (they require an enterprise env; pre-existing failures were confirmed on clean `version_1`).

---

## 5. Pre-live environment + encryption checklist (operator; do BEFORE any real token)

Run in order. Use a **fake/test token first**; never print real secrets.

- **E1 — AR encryption keys configured.** In the target env set `ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY`,
  `…_DETERMINISTIC_KEY`, `…_KEY_DERIVATION_SALT` (generate with `rails db:encryption:init`; store only in the
  server env / secret manager, never in the repo). Verify: `Chatwoot.encryption_configured?` → `true`.
- **E2 — provider_config encrypted-at-rest with a FAKE token.** Create a throwaway whatsapp_cloud channel with
  `provider_config['api_key'] = 'FAKE-TEST-TOKEN'`, then confirm at rest it is not plaintext:
  ```ruby
  c = Channel::Whatsapp.create!(account: <acct>, phone_number: '+0000000000', provider: 'whatsapp_cloud',
                               provider_config: { 'api_key' => 'FAKE-TEST-TOKEN', 'phone_number_id' => '0',
                                                  'source' => 'embedded_signup' })
  raw = c.reload.read_attribute_before_type_cast(:provider_config).to_s
  raw.include?('FAKE-TEST-TOKEN')   # expect: false   (encrypted at rest)
  c.provider_config['api_key']      # expect: 'FAKE-TEST-TOKEN'  (decrypts transparently)
  c.encrypted_attribute?(:provider_config)  # expect: true
  c.destroy!
  ```
  (The same assertions are covered automatically by
  `spec/models/channel/whatsapp_provider_config_encryption_spec.rb` when keys are present.)
- **E3 — Public HTTPS callback** reachable at `https://<host>/bloomwire/webhooks/whatsapp` (and/or native
  `/webhooks/whatsapp/<phone_number>`). Record the **masked** host only.
- **E4 — Meta app webhook** configured with that callback URL + the verify token; verify token + app secret live
  **only** in the server env (`BLOOMWIRE_WHATSAPP_GLOBAL_VERIFY_TOKEN`, `WHATSAPP_APP_SECRET`), never in repo.
- **E5 — Bloomwire toggles ON** for the live test: `BLOOMWIRE_MODE_ENABLED`, `BLOOMWIRE_PRIVACY_HARDENING`,
  `BLOOMWIRE_GLOBAL_WEBHOOK_ROUTER` (+ `BLOOMWIRE_WHATSAPP_PUBLIC_CALLBACK_HOST`).
- **E6 — Real WABA mapping** (`Bloomwire::WhatsappSetup`) seeded with the **exact** real `phone_number_id`
  (full value in env/DB only; report masked). Confirm `Bloomwire::WhatsappRealHopReadiness` reports Ready.

**Gate:** proceed to §6 live steps only when E1–E6 are all green. If any is missing → **BLOCKED** with the exact
missing item.

---

## 6. Human-operator live runbook (STOP for confirmation before each real Meta action)

> The agent will **not** execute these. Each step is a human action on the real environment. Capture **masked**
> evidence into §3 and the proof sections (§7–§11). Stop and re-confirm before each step that contacts Meta.

**13C.1 — Real inbound re-confirm (on current SHA).**
1. CONFIRM readiness (E1–E6). 2. From the test phone, send a WhatsApp message to the business number.
3. Verify: Meta `POST` → `/bloomwire/webhooks/whatsapp`; signature validates; router resolves the exact
   `phone_number_id`; `Webhooks::WhatsappEventsJob` runs; a Chatwoot conversation + incoming message are created
   in the correct inbox. 4. (If safely testable) replay with an unknown `phone_number_id` → expect fail-closed
   (no enqueue / no wrong-inbox write). 5. Capture: masked pnid, masked from-number, conversation/message id,
   timestamp, and a log excerpt showing **no** secret. → §7.

**13C.2 — Real outbound session reply (within 24h window).**
1. CONFIRM. 2. From the Chatwoot inbox, reply to the inbound conversation. 3. Verify: `SendReplyJob` runs →
   `Whatsapp::SendOnWhatsappService#send_session_message` → `WhatsappCloudService` POST to
   `…/<api_version>/<pnid>/messages` (default `v24.0`); provider returns a `wamid`; `message.source_id` is
   stored; the test phone receives the message; **no retry** on success. 4. Capture: masked conversation id,
   `wamid` **tail only**, a photo of the received message (private data masked), a redacted server-log excerpt,
   and the message record `status`/`source_id`. → §8.

**13C.3 — Real status webhook.**
1. After 13C.2, wait for Meta status callbacks. 2. Verify `Message.status` transitions: `sent` → `delivered` →
   `read` (open the message on the phone). 3. Confirm duplicate status callbacks don't error; (if safely
   testable) an unknown `source_id` is a safe no-op. 4. Capture: `wamid` tail, status + timestamps, message
   status proof, redacted log/API. → §9.

**13C.4 — Template / out-of-window.**
- **Precondition:** an **approved** WhatsApp template exists. If not → mark **BLOCKED** and record the exact
  missing Meta requirement (template name + category + approval status). 1. CONFIRM. 2. Trigger the template
  send via the supported path. 3. Verify: template path used; Meta accepts; phone receives; `wamid` stored;
  status reconciles. 4. Capture masked evidence. → §9 (template).

**13C.5 — Failure / retry (live-safe).** Prefer the **stubbed** 13B proof for transient 429/5xx (already PASS;
do not abuse real Meta). If approved and safe, trigger one controlled **permanent** failure (e.g. an invalid
template name) and confirm the message ends `failed` with a **redacted** `external_error` and **no** token in
logs. → §9 (failure).

**13C.6 — Privacy / permission (on live env).** Capture: a business-owner attempt to open native WhatsApp
provider setup → **403/blocked**; an inbox API response sample with `provider_config` **absent/scrubbed**; a
masked SuperAdmin/Ops view; a server-log excerpt with app secret/token/verify token **redacted**. → §10.

**13C.7 — Rollback drill (on live env).** Toggle `BLOOMWIRE_MODE_ENABLED` OFF → confirm stock/inert behavior;
toggle `BLOOMWIRE_GLOBAL_WEBHOOK_ROUTER` OFF → confirm Bloomwire routing is bypassed (native path only); confirm
no wrong-inbox writes and existing conversations/messages intact. Record toggle state before/after. → §11.

---

## 7. Inbound proof (operator fills)
GET verification: `<PENDING>` · POST inbound: `<PENDING>` · router mapping (masked pnid): `<PENDING>` ·
correct inbox/conversation/message: `<PENDING>` · negative checks: `<PENDING/N/A>`.
> Carry-forward: inbound was proven on dev `7ade9dc` in Phase 10B (masked). 13C.1 re-confirms on current SHA.

## 8. Outbound proof (operator fills)
Agent reply: `<PENDING>` · provider send (api_version): `<PENDING>` · `source_id`/wamid stored (tail): `<PENDING>` ·
phone received (masked photo): `<PENDING>` · no-secret log: `<PENDING>`.

## 9. Status + template + failure proof (operator fills)
sent: `<PENDING>` · delivered: `<PENDING>` · read: `<PENDING>` · failed (if tested): `<PENDING>` ·
duplicate/unknown behavior: `<PENDING>` · template availability: `<PENDING/BLOCKED>` · template receipt: `<PENDING>` ·
failure redacted error: `<PENDING>` (transient retry: stubbed PASS in Phase 13B).

## 10. Security / privacy proof
- **Code-side (PASS, verified in Phase 11B/12/13A–B):** business owners cannot configure provider/webhook
  infrastructure (managed-mode guards); `provider_config` scrubbed in the inbox API when privacy hardening ON;
  logs redact secrets at the two boundaries; no Enterprise dependency (§4).
- **Live (operator fills):** 403/blocked screenshot: `<PENDING>` · API sample (no secret): `<PENDING>` ·
  masked UI: `<PENDING>` · log redaction excerpt: `<PENDING>`.

## 11. Rollback proof
- **Code-side (PASS):** all Bloomwire behavior is AND-gated on `BLOOMWIRE_MODE_ENABLED`; OFF == stock/inert;
  router is fail-closed and optional.
- **Live (operator fills):** toggle before/after: `<PENDING>` · stock behavior on OFF: `<PENDING>` · no
  wrong-inbox write: `<PENDING>` · data intact: `<PENDING>`.

---

## 12. Secret-handling checklist (operator)
- [ ] No real token / app secret / verify token / full phone / WABA id / `phone_number_id` in this doc, the
      repo, logs pasted here, commits, or screenshots — **mask to last-4 / tails only**.
- [ ] Secrets live only in the server env (`.env` / secret manager / `InstallationConfig`); `.env` stays
      git-ignored and is never committed.
- [ ] AR encryption keys stored only in the server env; never in the repo.
- [ ] Verify privacy hardening ON → API `provider_config` scrubbed; logs show `[FILTERED]`.
- [ ] Screenshots/log excerpts scrubbed of private data before attaching.
- [ ] No secret printed to console output that is captured into the report.

## 13. Rollback checklist (operator)
- [ ] Know the toggles: `BLOOMWIRE_MODE_ENABLED` (master), `BLOOMWIRE_GLOBAL_WEBHOOK_ROUTER` (router),
      `BLOOMWIRE_PRIVACY_HARDENING`.
- [ ] Master OFF → stock Chatwoot (no Bloomwire restrictions/routing); confirm an inbox loads normally.
- [ ] Router OFF → Meta callbacks use the native `/webhooks/whatsapp/<phone_number>` path only.
- [ ] Confirm no wrong-inbox writes and existing conversations/messages remain intact after toggling.
- [ ] Document the exact toggle steps + who can perform them (Ops/SuperAdmin only).
- [ ] If encryption rollout is mid-flight: `support_unencrypted_data` keeps legacy rows readable; do not remove
      it until the backfill is complete (ADR-0006).

---

## 14. QA notes (agent, this pass)
- **Done (no Meta):** repo state verified (`decf62a`, PR #62, clean tree); no-Enterprise-dependency verified
  (code-side) + OSS-only loading rule documented; no-Meta pipeline harness `spec/integration/bloomwire/` →
  **26 examples, 0 failures** on the current SHA; encryption-at-rest provable locally
  (`whatsapp_provider_config_encryption_spec.rb`, 6/0 with ephemeral keys in Phase 13B).
- **Not done (by rule / capability):** no real Meta call; no real inbound/outbound/status/template; no secret
  read or printed; no deploy. These are the human-operated steps above.
- **Verdict: PASS-BUT-BLOCKED** until the live evidence rows in §3 / §7–§11 are filled on a real environment
  and independently QA-verified.
