# Bloomwire — S-03 Global Webhook Front-Door (Runtime Report)

> **Status:** Runtime spike / evidence report only (Sub-agent A of the parallel orchestration). **No** product code,
> branches, migrations, PRs, feature toggles, routes, or controllers were created; **no** Chatwoot behavior modified.
> **S-04 not touched.** Pricing/billing out of scope.
> **Spike:** S-03 from the decision register — unblocks **P-03** (one Bloomwire Meta App → global ingress).
> **Isolation:** all temporary records used the `S03` prefix on **account 1**; this workstream did **not** touch any
> `S04` records (account 2).
> **Builds on:** S-02 (proven `phone_number_id` routing).

## Proof labels
- **[RUNTIME-PROVEN]** — verified live (Rails runner against `chatwoot_dev`).
- **[CODE-PROVEN]** — verified by reading source.

---

## 1. Goal

Prove whether a Bloomwire-style **global webhook front-door** can (a) receive one Meta callback, (b) verify **one**
Meta signature with **one** app secret, and (c) forward the payload into Chatwoot's existing `WhatsappEventsJob`
**without loss, duplication, or wrong-tenant routing** — using a fake app secret and a fake signed payload, with no
real Meta calls.

## 2. Setup / environment

- `develop` @ `56c98c8`, Chatwoot 4.15.1, Ruby 3.4.4, `chatwoot_dev`, Redis up; Sidekiq worker not running (job run
  synchronously via `.perform`).
- Method: `bundle exec rails runner` (script via stdin) — **no product code, routes, or controllers added.**

## 3. Method + safety

The front-door was modeled **without** creating any route/controller:
1. A throwaway lambda **replicates the production signature check verbatim** from
   `meta_token_verify_concern.rb:28-38`:
   `expected = "sha256=" + OpenSSL::HMAC.hexdigest('SHA256', secret, raw_body)`, compared with
   `ActiveSupport::SecurityUtils.secure_compare`.
2. The "one app secret" is a **fake** local value (`S03_FAKE_GLOBAL_APP_SECRET`). In production this single secret is
   sourced from `GlobalConfigService.load('WHATSAPP_APP_SECRET')` — see `whatsapp_controller.rb:25-30`
   (`meta_app_secrets` appends the global `WHATSAPP_APP_SECRET`). **No InstallationConfig was written.**
3. On a valid signature, the front-door forwards the **parsed** payload into the **unmodified**
   `Webhooks::WhatsappEventsJob.new.perform(...)` — and deliberately passes **no `:phone_number` URL param**, so
   routing is metadata-only.
4. Channel created via `Channel::Whatsapp.insert_all!` (no callbacks → no `validate_provider_config?` /
   `sync_templates` / `setup_webhooks` Meta calls). Text-only payloads → no `download_attachment_file`. **No Meta calls.**
5. `begin/ensure` cleanup incl. best-effort purge of the 1-day Redis dedup keys (`MessageDedupLock`).

**Test channel (S03):** account 1, `+15550103001`, `phone_number_id = S03_PNID_A`, inbox `S03 Inbox A` (#14).

## 4. Raw runner evidence [RUNTIME-PROVEN]

```
SETUP channel#8 inbox#14 acct#1 phone=+15550103001 pnid=S03_PNID_A
VERIFY1-3 valid_sig+valid_payload result=forwarded messages_in_inbox=1 (expect forwarded/1)
VERIFY4 duplicate_forward result=forwarded messages_in_inbox=1 (expect 1 => idempotent by source_id)
VERIFY5 invalid_sig result=rejected malformed_sig result=rejected messages_in_inbox=1 (expect rejected/rejected, count=1)
VERIFY6 valid_sig+unknown_pnid result=forwarded messages_in_inbox=1 global_unknown_msgs=0 (expect forwarded but 0 created)
VERIFY7 url_independence: forwarded payload had NO :phone_number key; channel resolved purely via payload metadata
CONTENTS inbox#14=["S03 FRONTDOOR MSG"]
CLEANUP msgs=1 convs=1 contact_inboxes=1 contacts=1 inboxes=1 channels=1 redis_dedup_cleared=3
RESIDUE msgs=0 convs=0 channels=0
BASELINE acct1_inbox=1 wa_global=0
```

## 5. Verification matrix

| # | Verification | Result | Evidence |
|---|---|---|---|
| 1 | Global payload signature-verified using one app secret | **PASS** | valid sig → `result=forwarded`; replicates `meta_token_verify_concern.rb:35-36` |
| 2 | Verified payload forwarded into `WhatsappEventsJob` | **PASS** | `forwarded` → job ran on parsed payload |
| 3 | Forward creates exactly one message in correct inbox | **PASS** | `messages_in_inbox=1`, `CONTENTS=["S03 FRONTDOOR MSG"]` |
| 4 | Duplicate forwarding → idempotent (no duplicate) | **PASS** | second forward `messages_in_inbox=1` ([CODE-PROVEN] `incoming_message_base_service.rb:36` + `MessageDedupLock` Redis SET NX) |
| 5 | Invalid signature fails closed | **PASS** | wrong-secret **and** malformed header both `rejected`, count stays `1` (not forwarded) |
| 6 | Unknown `phone_number_id` fails closed | **PASS** | valid sig but unknown pnid → `forwarded` yet `0` created, `global_unknown_msgs=0` (job `get_channel_from_wb_payload` returns nil) |
| 7 | No dependency on per-phone-number URL | **PASS** | forwarded payload had **no** `:phone_number` key; channel resolved via `entry[].changes[].value.metadata` |
| 8 | Cleanup complete | **PASS** | `RESIDUE=0`; baseline restored (`acct1_inbox=1 wa_global=0`); 3 Redis dedup keys cleared |

## 6. What is proven [RUNTIME-PROVEN]

1. A single global app secret can HMAC-verify a Meta callback (`sha256=` + HMAC-SHA256 over the raw body), using the
   exact production expression.
2. A verified payload, forwarded into the **unmodified** `WhatsappEventsJob`, lands as **exactly one** message in the
   correct tenant inbox — confirming the front-door + S-02 routing compose cleanly.
3. **Idempotency already exists** in Chatwoot: a re-delivered/duplicated callback (same `wamid`) does **not** create a
   duplicate message (`find_message_by_source_id` short-circuit + Redis dedup lock).
4. **Fail-closed** on both axes: an invalid/malformed signature is rejected before forwarding, and a verified payload
   with an unknown `phone_number_id` produces no message.
5. The ingress is **URL-independent** — a single global endpoint (no per-number path) is sufficient.

## 7. What is NOT proven (out of S-03 scope)

- A **persisted** Bloomwire route/controller (this spike intentionally created none) — implementation work, not a spike.
- Live Meta delivery, real signature from Meta, and the `hub.challenge` GET verification handshake (uses
  `valid_token?` / per-channel `webhook_verify_token`) — not exercised here.
- Attachment/media payloads (media path makes a Meta call) — text-only here.
- Outgoing send + status reconciliation — **S-04** (separate workstream).

## 8. External-call safety check

- `insert_all!` channel creation → no callbacks → **no** Meta calls. [RUNTIME + CODE-PROVEN]
- Signature check is pure local OpenSSL HMAC; forwarding runs the job in-process on text payloads → **no** Meta call.
- `delete_all` cleanup → no `before_destroy :teardown_webhooks`. **No Meta call.**
- A Sidekiq **client** connected to Redis (no worker ran); not an external/Meta call.

## 9. Cleanup result [RUNTIME-PROVEN]

`CLEANUP msgs=1 convs=1 contact_inboxes=1 contacts=1 inboxes=1 channels=1 redis_dedup_cleared=3` → `RESIDUE=0`;
baseline restored (`acct1_inbox=1 wa_global=0`). No product code/routes/controllers changed. No `S04` records touched.

## 10. Decision impact on P-03

**P-03 — "One Bloomwire Meta App → global ingress that fans out to many tenants" → CONFIRMED.** The two halves now
both hold: S-02 proved metadata routing/isolation; S-03 proves a single-secret signature gate + forward into the
existing job with built-in idempotency and fail-closed behavior. A Bloomwire global front-door is viable as a thin,
**additive** controller that (1) verifies with the global `WHATSAPP_APP_SECRET`, (2) enqueues `WhatsappEventsJob` —
no change to Chatwoot's resolution or dedup logic required.

## 11. Recommended next step

Proceed to **S-04 — Outgoing injection** (the remaining runtime gate), then consolidate S-01…S-06 into the final
feature-toggle architecture plan. **S-04 run separately as Sub-agent B.** (No implementation started.)
