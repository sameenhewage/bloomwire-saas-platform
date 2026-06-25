# Bloomwire — S-02 Multi-WABA Webhook Routing (Runtime Report)

> **Status:** Runtime spike / evidence report only (Sub-agent A of the parallel orchestration). **No** product code,
> branches, migrations, PRs, feature toggles; **no** Chatwoot behavior modified. **S-03 not started.** Pricing/billing
> out of scope.
> **Spike:** S-02 from the decision register (`bloomwire-evidence-review-and-decision-register.md` §3) — unblocks **P-02**.
> **Isolation:** all temporary records used the `S02` prefix; this workstream did **not** touch any `S05S06` records.
> **Sources:** evidence-collection-report · evidence-review-and-decision-register · runtime-analysis-and-rCA-report ·
> s07-live-ui-runtime-smoke-report · feature-toggle-managed-whatsapp-onboarding-plan · s01-multiple-whatsapp-inboxes-runtime-report.

## Proof labels
- **[RUNTIME-PROVEN]** — verified live in the running app (Rails runner against `chatwoot_dev`).
- **[CODE-PROVEN]** — verified by reading source.

---

## 1. Goal

Prove whether two different WhatsApp `phone_number_id` values route inbound webhook payloads to the **correct**
Chatwoot Account / Inbox / Channel, with **no cross-tenant leakage**, and that an unknown/mismatched `phone_number_id`
**fails closed** — without real Meta/WABA credentials and without external Meta calls.

## 2. Setup / environment

| Component | Detail |
|---|---|
| Code baseline | branch `develop` @ `56c98c8` (pure Chatwoot / Feature-OFF baseline) |
| App | Chatwoot 4.15.1, Rails 7.1.5.2, Ruby 3.4.4 (rbenv) |
| DB / Redis | `chatwoot_dev` @ :5432 / Redis :6379 (both up) |
| Sidekiq worker | not started (job executed **synchronously** via `.perform`; no async side-effects) |
| Method | `bundle exec rails runner` (script via stdin) — **no product code added** |

## 3. Method + safety

- **Channels** created via `Channel::Whatsapp.insert_all!` (bypasses all callbacks → no `validate_provider_config?`,
  `sync_templates`, or `setup_webhooks` Meta calls), tagged `provider_config.source = 's02_runtime_test'`, fake `api_key`.
- **Inboxes** via `Inbox.create!` (no Meta-calling callbacks).
- **Inbound routing** exercised by calling `Webhooks::WhatsappEventsJob.new.perform(payload)` **directly** with a
  `whatsapp_business_account` sample payload built as a `HashWithIndifferentAccess` (matches production
  `params.to_unsafe_hash`). The HTTP controller + `verify_meta_signature!` were intentionally bypassed (that is
  S-03's scope), so **no signature/secret and no network** were involved.
- **Text-only** payloads → the incoming pipeline never calls `download_attachment_file`
  (`incoming_message_whatsapp_cloud_service.rb:11-15`), the only Meta call in the inbound path. **No external calls.** [CODE-PROVEN]
- **Cleanup** in a `begin/ensure` block so it runs even on error; uses `delete_all` (no `before_destroy`/teardown).

**Test topology (S02):**

| Channel | Account | phone_number | provider_config.phone_number_id | Inbox |
|---|---|---|---|---|
| S02 A | 1 (Acme Inc) | `+15550100001` | `S02_PNID_A` | `S02 Inbox A` (#11) |
| S02 B | 1 (Acme Inc) | `+15550100002` | `S02_PNID_B` | `S02 Inbox B` (#12) |
| S02 C | 2 (Acme Org) | `+15550100003` | `S02_PNID_C` | `S02 Inbox C` (#13) |

(A & B = same-account multi-inbox; C = cross-account.)

## 4. Records created

`channels=[5,6,7]`, `inboxes=[11,12,13]` (+ 3 contacts, 3 contact_inboxes, 3 conversations, 3 messages produced by
routing) — **all temporary, all removed in §9.**

## 5. Runtime evidence (raw runner output) [RUNTIME-PROVEN]

```
SETUP channels=[5, 6, 7] inboxes=[11, 12, 13]
  A=inbox#11(acct1) phone=+15550100001 pnid=S02_PNID_A
  B=inbox#12(acct1) phone=+15550100002 pnid=S02_PNID_B
  C=inbox#13(acct2) phone=+15550100003 pnid=S02_PNID_C
ROUTE_A inbox#11 convs=1 msgs=["S02 MSG A"]
ROUTE_B inbox#12 convs=1 msgs=["S02 MSG B"]
ROUTE_C inbox#13 convs=1 msgs=["S02 MSG C"]
ASSERT routing A=true B=true C=true
ASSERT no_cross_leak=true same_account_multi(A,B@acct1)=true cross_account(C@acct2)=true
FAILCLOSED total_before=3 total_after=3 unchanged=true global_failclosed_msgs=0
CLEANUP msgs=3 convs=3 contact_inboxes=3 contacts=3 inboxes=3 channels=3
RESIDUE convs=0 msgs=0 contacts=0 channels=0
BASELINE acct1_inbox=1 acct2_inbox=1 wa_global=0
```

## 6. Verification matrix

| # | Verification | Result | Evidence |
|---|---|---|---|
| 1 | Payload `phone_number_id A` resolves to Channel A | **PASS** | `ROUTE_A → inbox#11`, msg `"S02 MSG A"` |
| 2 | Payload `phone_number_id B` resolves to Channel B | **PASS** | `ROUTE_B → inbox#12`, msg `"S02 MSG B"` |
| 3 | Same-account multi-inbox routing | **PASS** | A & B both acct 1, each got its own message, no mixing |
| 4 | Cross-account routing, no leakage | **PASS** | C acct 2; `no_cross_leak=true` |
| 5 | `WhatsappEventsJob` resolves by payload metadata, independent of URL phone number | **PASS** | Job called with **no** `:phone_number` URL param; resolution came purely from `entry[].changes[].value.metadata` ([CODE-PROVEN] `whatsapp_events_job.rb:146-161`) |
| 6 | Message lands in correct Inbox / Conversation / Message | **PASS** | each inbox: `convs=1`, exactly its own message body |
| 7 | Wrong `phone_number_id` fails closed | **PASS** | unknown pnid **and** display-matches-A-but-pnid-is-B → `total 3→3 unchanged`, `global_failclosed_msgs=0` |
| 8 | Cleanup complete | **PASS** | `RESIDUE=0`; baseline restored (acct1=1, acct2=1, wa_global=0) |

## 7. What is proven [RUNTIME-PROVEN]

1. Inbound `whatsapp_business_account` payloads route to the correct **Account/Inbox/Channel** strictly by
   `phone_number_id` (validated against `provider_config['phone_number_id']`), **independent of the URL**.
2. **No cross-tenant leakage** across two accounts and across two inboxes within one account.
3. The resolver **fails closed**: an unknown `phone_number_id`, and a payload whose `display_phone_number` matches a
   real channel but whose `phone_number_id` does **not**, both produce **zero** messages (the
   `channel && provider_config['phone_number_id'] == phone_number_id` guard rejects mismatches).
4. The existing `WhatsappEventsJob` → `IncomingMessageWhatsappCloudService` pipeline persists the inbound text into the
   right Conversation/Message with **no external Meta call** for text.

## 8. What is NOT proven (out of S-02 scope)

- A **Bloomwire-owned global ingress** that receives one Meta callback, verifies the signature with one app secret,
  and forwards into `WhatsappEventsJob` — that is **S-03** (the HTTP controller + `verify_meta_signature!` were
  bypassed here). **[NOT PROVEN — S-03]**
- Live signature verification, real Meta delivery, and attachment/media routing (media path makes a Meta call). **[NOT PROVEN]**
- Status-webhook reconciliation / outgoing — **S-04**. **[NOT PROVEN]**

## 9. External-call safety check

- Channel creation via `insert_all!` → no callbacks → **no** `validate_provider_config?` / `sync_templates` /
  `setup_webhooks` Meta calls. **[RUNTIME-PROVEN + CODE-PROVEN]**
- Inbound routing used **text** payloads → `download_attachment_file` never invoked → **no** Meta call. **[CODE-PROVEN]**
- Cleanup via `delete_all` → no `before_destroy :teardown_webhooks` (and `source != 'embedded_signup'` would no-op it anyway). **No Meta call.**
- A Sidekiq **client** connected to Redis to (potentially) enqueue internal events; no worker ran, and routing was
  executed synchronously. Not an external/Meta call.

## 10. Cleanup result [RUNTIME-PROVEN]

`CLEANUP msgs=3 convs=3 contact_inboxes=3 contacts=3 inboxes=3 channels=3` → `RESIDUE convs=0 msgs=0 contacts=0
channels=0`; baseline restored (`acct1_inbox=1 acct2_inbox=1 wa_global=0`). **No product code changed** (only this
report + a throwaway runner piped via stdin). **No `S05S06` records touched.**

## 11. Decision impact on P-02 (and P-03)

**P-02 — "One Bloomwire Meta App → many WABAs safely" → CONFIRMED** at the routing/resolution layer: Chatwoot's
existing event job already routes by `phone_number_id` with strict per-tenant isolation and fail-closed behavior. This
is the core enabler for the routing registry (plan §6) and the global router (plan §7).

**P-03 is NOT yet confirmed:** S-02 proves the *resolution + forwarding-into-the-job* half. The remaining half — a
Bloomwire-owned **global front door** (single endpoint, single app-secret signature verification, no loss/dup) — is
**S-03** and remains gated.

## 12. Recommended next step

**S-03 — Global webhook front-door** (stand up a throwaway global endpoint that verifies one Meta signature and
forwards into `WhatsappEventsJob`), building directly on this proven resolution. **Not started** (per instructions).
