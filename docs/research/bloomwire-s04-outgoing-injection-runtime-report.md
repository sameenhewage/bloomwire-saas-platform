# Bloomwire — S-04 Outgoing Injection + Status Reconciliation (Runtime Report)

> **Status:** Runtime spike / evidence report only (Sub-agent B of the parallel orchestration). **No** product code,
> branches, migrations, PRs, feature toggles; **no** Chatwoot behavior modified. **S-03 not touched.** Pricing/billing
> out of scope.
> **Spike:** S-04 — outgoing send-path safety + status reconciliation.
> **Isolation:** all temporary records used the `S04` prefix on **account 2**; this workstream did **not** touch any
> `S03` records (account 1).

## Proof labels
- **[RUNTIME-PROVEN]** — verified live (Rails runner against `chatwoot_dev`).
- **[CODE-PROVEN]** — verified by reading source.

---

## 1. Goal

Prove whether outbound messages injected through Chatwoot/Bloomwire-safe paths **preserve conversation history** and
**status reconciliation** (delivered/read/failed) keyed by the provider `wamid`, **without** real Meta credentials and
**without** any external Meta send.

## 2. Native outgoing path + Meta call site (verify #1, #2) [CODE-PROVEN]

| Stage | Owner | Meta call? |
|---|---|---|
| Agent reply created | `Messages::MessageBuilder` → `Message` (`message_type: outgoing`) | no |
| Send trigger | `Message` `after_create_commit` → `SendReplyJob` → `Whatsapp::SendOnWhatsappService` | no |
| **Actual send** | `send_on_whatsapp_service.rb:31-43` → `channel.send_message` / `send_template` → `Whatsapp::Providers::WhatsappCloudService#send_message` | **YES — `HTTParty.post` to `graph.facebook.com`** |
| wamid persisted | `send_on_whatsapp_service.rb:37,42` → `message.update!(source_id: message_id)` | no |

So the **only** outbound Meta call is inside `WhatsappCloudService#send_message`; the returned `wamid` is stored as
`message.source_id`. Everything else (history, status) is local DB state.

## 3. Setup / environment + method

- `develop` @ `56c98c8`, Chatwoot 4.15.1, Ruby 3.4.4, `chatwoot_dev`, Redis up; Sidekiq worker not running.
- Method: `bundle exec rails runner` (script via stdin) — **no product code added.**
- **Safe injection (verify #3):** the outbound message was created with `Message.insert_all!` (bypasses
  `after_create_commit` → **no** `SendReplyJob` / `SendOnWhatsappService` → **no** Meta call), with
  `message_type: 1 (outgoing)`, `status: 0 (sent)`, `source_id: 'S04_WAMID_OUT_1'` (simulating a Meta-returned wamid).
- Status reconciliation exercised by routing sample `statuses` webhooks through the **unmodified**
  `Webhooks::WhatsappEventsJob` (text/metadata only — no Meta call).
- `S04` channel: account 2, `+15550104001`, `phone_number_id = S04_PNID_A`, inbox `S04 Inbox A` (#15).

## 4. Raw runner evidence [RUNTIME-PROVEN]

```
SETUP channel#9 inbox#15 acct#2 conv#6 contact#6
INJECT msg#17 type=outgoing status=sent source_id="S04_WAMID_OUT_1"
VERIFY4 conv_outgoing_msgs=["S04 OUTBOUND HELLO"] stored_in_conv#6_inbox#15
VERIFY5 source_id_column="S04_WAMID_OUT_1" (set on real send via send_on_whatsapp_service.rb:37,42)
VERIFY6 after_delivered=delivered after_read=read (expect delivered then read)
VERIFY7 wrong_source_id_status=read unchanged=true (expect read, unchanged)
VERIFY8 failed_status=failed external_error="131026: Message undeliverable"
CLEANUP msgs=1 convs=1 contact_inboxes=1 contacts=1 inboxes=1 channels=1
RESIDUE msgs=0 convs=0 channels=0
BASELINE acct2_inbox=1 wa_global=0
```

## 5. Verification matrix

| # | Verification | Result | Evidence |
|---|---|---|---|
| 1 | Native outgoing WhatsApp send path | **Documented** | [CODE-PROVEN] §2 (`send_on_whatsapp_service.rb:31-43`) |
| 2 | Where the Meta API call happens | **Documented** | [CODE-PROVEN] `WhatsappCloudService#send_message` (`HTTParty.post` graph.facebook.com) |
| 3 | Inject a message safely without sending to Meta | **PASS** | `insert_all!` outbound `msg#17`, no callback/send |
| 4 | Injected outbound history in correct records | **PASS** | `conv_outgoing_msgs=["S04 OUTBOUND HELLO"]` in conv#6/inbox#15 |
| 5 | How `source_id`/`wamid` is stored for reconciliation | **PASS** | `message.source_id` column = `"S04_WAMID_OUT_1"` (set via `:37,42`) |
| 6 | Status webhook updates correct message by `source_id` | **PASS** | `sent → delivered → read` (`incoming_message_base_service.rb:51,59-66`) |
| 7 | Wrong `source_id` fails closed | **PASS** | unknown wamid → status stays `read` (`unchanged=true`) — `find_message_by_source_id` returns nil → `return` |
| 8 | `failed` status reconciliation | **PASS (bonus)** | status `failed`, `external_error="131026: Message undeliverable"` (`:61-64`) |
| 9 | Cleanup complete | **PASS** | `RESIDUE=0`; baseline restored (`acct2_inbox=1 wa_global=0`) |

## 6. Runtime-proven vs still blocked (verify #8)

**Runtime-proven:** outbound history persistence, `source_id`/`wamid` storage shape, and full status reconciliation
(`sent → delivered → read → failed` with `external_error`) keyed strictly by `source_id`, with wrong-id fail-closed.

**Still blocked by "no real Meta credentials":** the actual outbound **send** (`WhatsappCloudService#send_message`
HTTP POST to `graph.facebook.com`) cannot be exercised without real creds — this is the **only** step that needs Meta
and was deliberately not run. (Earlier S-07 confirmed fake creds make the live send hang/reject on the Graph call.)
A future "send" proof would require WebMock/stub in a spec **or** sandbox credentials — out of scope for a no-Meta
runtime spike.

## 7. External-call safety check

- `insert_all!` channel + message creation → no callbacks → **no** Meta calls. [RUNTIME + CODE-PROVEN]
- Status reconciliation routes text/metadata payloads through the existing job → **no** Meta call (status path never
  calls `download_attachment_file` or the send service). [CODE-PROVEN]
- `delete_all` cleanup → no `before_destroy :teardown_webhooks`. **No** Meta call.

## 8. Cleanup result [RUNTIME-PROVEN]

`CLEANUP msgs=1 convs=1 contact_inboxes=1 contacts=1 inboxes=1 channels=1` → `RESIDUE=0`; baseline restored
(`acct2_inbox=1 wa_global=0`). No product code changed. No `S03` records touched.

## 9. Decision impact

**Outgoing injection + status reconciliation are safe and additive.** Bloomwire does **not** need to change Chatwoot's
outbound pipeline: history is plain `Message` rows, and status reconciliation already keys off `source_id` (`wamid`)
with fail-closed semantics. The single Meta dependency (`WhatsappCloudService#send_message`) is the natural seam for a
Bloomwire **managed-send** wrapper behind a feature toggle, without touching reconciliation. This keeps the protected
Chatwoot baseline intact (feature-OFF = native behavior).

## 10. Recommended next step

All runtime gates (S-01, S-02, S-03, S-04, S-05/S-06, S-07) are now complete. **Recommended:** consolidate every spike
into the final **feature-toggle architecture plan** (and the privacy-hardening design from S-05/S-06). No
implementation has started — awaiting explicit go-ahead.
