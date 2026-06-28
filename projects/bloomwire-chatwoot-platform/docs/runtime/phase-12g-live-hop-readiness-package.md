# Phase 12G — WhatsApp Live-Hop Readiness Package (human-operated)

> The real Meta WhatsApp live hop **cannot be performed by the agent** — it needs real Meta credentials, a real
> WABA + number, a physical phone, and a public HTTPS callback. This package makes that hop **thin, explicit,
> and safe** for a human operator. **No agent runs Meta here.** All automated, no-Meta proof already exists
> (Phase 12B harness); this is the human checklist that turns "code is built + unit-proven" into "validated on a
> real number."

## 0. Pre-live proof already in place (no real Meta)
- **Automated E2E harness (Phase 12B)** — `app/spec/integration/bloomwire/`:
  - `whatsapp_inbound_e2e_spec.rb` — signed router POST → routed inbox Message/Conversation/Contact; duplicate
    `wamid` idempotent; bad signature 401; unknown `phone_number_id` safe-200/no-create.
  - `whatsapp_outbound_e2e_spec.rb` — outgoing message → stubbed Graph → `source_id` captured; failure →
    `failed` + `external_error`.
  - `whatsapp_status_reconciliation_spec.rb` — status webhook reconciles the same Message `sent→delivered→read`.
  - `whatsapp_real_hop_readiness_gate_spec.rb` — readiness ready/blocked matrix, no secret leak.
- **Ops readiness console (Phase 12E/12F)** — `/super_admin/bloomwire_whatsapp_setups/:id/readiness`: per-setup
  Ready/Blocked, masked identifiers, and the **Global webhook registration readiness** panel (callback URL +
  GET-verify prerequisites).
- **Ops runbook** — `docs/ops/whatsapp-webhook-deployment-runbook.md` (deploy, Meta dashboard callback, verify
  token rotation, nginx query-param log filtering, readiness gate).

Treat the above as the **gate**: do **not** start the live hop until the readiness console shows **Ready** and
the 12B specs are green.

## 1. External prerequisites (human/Ops gathers — none stored in git)
| # | Prerequisite | Where it goes (never committed) |
|---|---|---|
| 1 | Real Meta **WABA** | Meta Business / dashboard |
| 2 | Real **`phone_number_id`** | `Channel::Whatsapp#provider_config` + the `Bloomwire::WhatsappSetup` mapping (non-secret routing id) |
| 3 | Real **access token** (`api_key`) | `Channel::Whatsapp#provider_config` **only** |
| 4 | Real **Meta app secret** (`WHATSAPP_APP_SECRET`) | server `.env` / `InstallationConfig` **only** |
| 5 | **Global verify token** (`BLOOMWIRE_WHATSAPP_GLOBAL_VERIFY_TOKEN`) | server `.env` / `InstallationConfig` **only** |
| 6 | **Public HTTPS callback URL** host (`BLOOMWIRE_WHATSAPP_PUBLIC_CALLBACK_HOST`) | non-secret hostname (e.g. `chat.example.com`) |
| 7 | **Physical test phone** (the business WABA number) | hardware |
| 8 | **Meta dashboard access** | to set callback URL + run GET verification |
| 9 | **Test customer phone** (a second phone, NOT a production customer) | hardware |
| 10 | **Rollback plan** (see §5) | this doc |

Callback URL to register in Meta: `https://<BLOOMWIRE_WHATSAPP_PUBLIC_CALLBACK_HOST>/bloomwire/webhooks/whatsapp`
(subscribe field: **messages**). Verify token = the configured `BLOOMWIRE_WHATSAPP_GLOBAL_VERIFY_TOKEN` (read it
locally from `.env`; never paste it anywhere).

## 2. Pre-flight (must all be true before touching Meta)
- [ ] Toggles ON: `BLOOMWIRE_MODE_ENABLED`, `BLOOMWIRE_PRIVACY_HARDENING`, `BLOOMWIRE_GLOBAL_WEBHOOK_ROUTER`,
      `BLOOMWIRE_RESTRICT_NATIVE_WHATSAPP_SETUP`.
- [ ] `WHATSAPP_APP_SECRET`, `BLOOMWIRE_WHATSAPP_GLOBAL_VERIFY_TOKEN`, `BLOOMWIRE_WHATSAPP_PUBLIC_CALLBACK_HOST`
      configured (presence only — never print values).
- [ ] Ops created the `Channel::Whatsapp` (provider `whatsapp_cloud`, real `provider_config`) + linked
      `Bloomwire::WhatsappSetup` mapping set to `ready_for_webhook`.
- [ ] Readiness console shows **Ready** for the setup **and** the registration panel shows **Ready to register**
      (all GET-verify prerequisites PASS, `router_handoff_safe` PASS).
- [ ] 12B integration specs green on the deployed SHA.

## 3. Live-hop steps (human operator)
1. **Register callback** in the Meta dashboard: callback URL (§1), verify token (§1), subscribe **messages**.
2. **GET verification**: confirm Meta's handshake returns **200 + challenge** (wrong token ⇒ 401; router/toggle
   OFF ⇒ 404).
3. **Inbound**: from the **test customer phone**, send one message to the business WABA number.
4. Confirm the message is **received** by the global router and handed off (router logs show only a masked
   `****` phone_number_id tail; no secret).
5. Confirm a **Chatwoot Contact + Conversation + Message** appear in the mapped inbox (source of truth = Chatwoot).
6. **Outbound**: reply from the Chatwoot inbox; confirm the customer phone receives it; confirm `source_id` set.
7. **Status**: confirm delivery/read status webhooks reconcile the same Message (`sent → delivered → read`).
8. **Idempotency**: confirm a re-delivered inbound (same `wamid`) does **not** create a duplicate message.

## 4. Evidence to capture (masked only)
| Evidence | How | Capture (masked) |
|---|---|---|
| GET verification success | Meta dashboard / server log | 200 + challenge echoed; token match (do not print token) |
| Inbound received | router log | masked `****<tail>` phone_number_id; no body in PR |
| Chatwoot records created | Chatwoot UI | contact/conversation/message ids (internal, fine); screenshot with phone masked |
| Outbound reply sent | Chatwoot UI + customer phone | message `source_id` present (wamid) |
| Status reconciled | message status | `sent → delivered → read` on the same message |
| No duplicate | message count | one message per `wamid` |
| No secret exposed | grep logs/PR | 0 occurrences of app secret / access token / verify token / full phone / full `phone_number_id` |

Record the masked evidence in `docs/runtime/phase-3a-whatsapp-cloud-e2e-baseline.md` §9 (the existing evidence
table) once the hop is done. **Do not** open/merge a "live hop PASS" claim until §9 is filled with real masked
evidence.

## 5. Rollback
1. In the Meta dashboard, **unsubscribe** / re-point the callback away from the global router (back to per-number
   ingress or off).
2. Flip `BLOOMWIRE_GLOBAL_WEBHOOK_ROUTER` OFF (router endpoint returns 404; stock per-number `webhooks/whatsapp`
   path unaffected).
3. If a test channel/mapping was created only for the hop, mark the setup `blocked` (do not delete customer data).
4. Confirm no customer-facing impact (OFF == stock).

## 6. Safety warnings (non-negotiable)
- **Do not paste secrets** (app secret, access token, verify token, DB password) or **full phone numbers /
  `phone_number_id`** into PRs, comments, screenshots, or logs — masked/presence only.
- **Do not use a production customer phone** for the first live test — use a controlled test customer phone.
- **Do not claim PASS without evidence** — the §4 evidence (masked) must be captured first.
- Secrets live **only** in `Channel::Whatsapp#provider_config` and server `.env`/`InstallationConfig`. The
  Bloomwire setup registry stays non-secret. No message/conversation/contact data is duplicated into Bloomwire
  tables — Chatwoot remains source of truth.

## 7. Status
This package is **ready for a human operator**. The agent has NOT performed and does NOT claim a real Meta live
hop. The remaining blocker is entirely external/human: real Meta assets + a physical phone + a public HTTPS
callback + Meta dashboard access.
