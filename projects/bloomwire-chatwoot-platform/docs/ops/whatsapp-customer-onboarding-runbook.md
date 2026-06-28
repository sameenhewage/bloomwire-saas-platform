# Runbook — Bloomwire WhatsApp Customer Onboarding (Ops)

> **STATUS: ready for a MANUAL, Ops-driven first-customer pilot (Phase 14 S1).** Every record + guardrail this
> runbook depends on already exists and is spec-proven (isolation, fail-closed routing, secret hiding,
> encryption at rest, PII-clean logs). Onboarding today is a **manual multi-step Ops process** — one-click
> provisioning (S3) and a secure Ops credential-capture surface (S2) are **not built yet** (see §9).
>
> **Secret hygiene (non-negotiable):** never paste or print access tokens, app secret, verify token, DB
> password, `provider_config`, or a **full** phone number / `phone_number_id` into this file, chat, logs, PRs,
> or commits. Report **presence/masked only** (`present` / `missing` / `****1234`).

Related: deployment + webhook how-to [`whatsapp-webhook-deployment-runbook.md`](./whatsapp-webhook-deployment-runbook.md);
router design [`../adr/0005-global-whatsapp-webhook-router-foundation.md`](../adr/0005-global-whatsapp-webhook-router-foundation.md);
setup-mapping design [`../adr/0004-whatsapp-setup-mapping-foundation.md`](../adr/0004-whatsapp-setup-mapping-foundation.md);
secret-at-rest [`../adr/0006-whatsapp-provider-secret-at-rest.md`](../adr/0006-whatsapp-provider-secret-at-rest.md);
deferred work [`../parked-items.md`](../parked-items.md).

This runbook uses **Aroma Flora** as the example new customer. All identifiers below are masked placeholders.

---

## 0. Roles & ownership (who does what)

| Step area | Owner |
|---|---|
| Account/team creation, channel + `provider_config` secrets, setup mapping, readiness, Meta webhook | **Bloomwire Ops / SuperAdmin** |
| Provide WABA details + access token (out-of-band), approve/own the Meta assets | **Customer's Meta admin** |
| Day-to-day inbox use (reply, view assigned conversations) | **Business Owner (account admin) + Staff/Agents** |

Business Owners and Agents **never** configure the provider and **never** see provider secrets (enforced in code — see §8).

---

## 1. Customer / account setup

1. **Create a clean Account** for the customer (SuperAdmin → Accounts → new). Use a fresh account — **do not reuse a
   test account**. Record the new `account_id` (masked/short is fine in evidence).
2. **Invite the Business Owner** as an account **administrator**.
3. **Add Staff/Agents** as account **agents** (they will be added to the WhatsApp inbox in §3.5).

> One Account = one customer (tenant boundary). All of the customer's inboxes/conversations/contacts live under
> this account and are isolated from every other account.

---

## 2. WhatsApp / WABA prerequisites (customer's Meta admin → Ops, out-of-band)

Confirm the customer has, on **their** Meta assets:

- A **WABA** (WhatsApp Business Account) with a verified **business phone number**.
- The **`phone_number_id`** (Meta numeric id for the phone) — **routing key**.
- The **`business_account_id` / WABA id**.
- The **`display_phone_number`** (the business number Meta echoes in webhooks).
- A **system-user access token** with the needed WhatsApp scopes.

> **Access token is a secret** — it is transferred to Ops **out-of-band** (secure channel), never via this runbook,
> chat, the setup form, or a ticket body. Capture token **presence only** in evidence.

---

## 3. Bloomwire setup (Ops)

### 3.1 Create the WhatsApp channel + inbox
Create a `Channel::Whatsapp` (provider `whatsapp_cloud`) **in the customer's account**, with `provider_config`
containing the **non-secret** routing ids (`phone_number_id`, `business_account_id`) and the **secret** access token
(`api_key`). Its inbox is created with it. The channel's `phone_number` must be **`+<display_phone_number>`**.

> **Provider_config secret handling note:** the SuperAdmin setup-mapping form (§3.3) **deliberately stores no
> secrets**. Until the secure Ops credential-capture surface (**S2**) exists, the access token is placed into
> `provider_config['api_key']` via an Ops-only path (server console / embedded-signup run by Ops) — **never** a
> business-user flow and **never** pasted into docs/chat. `provider_config` is **encrypted at rest** (ADR-0006)
> when encryption is configured (§5), and is **scrubbed + admin-gated** out of all API responses (§8).

### 3.2 Confirm channel field alignment
- `channel.provider == 'whatsapp_cloud'`
- `channel.phone_number == "+<display_phone_number>"`
- `channel.provider_config['phone_number_id'] == <phone_number_id>` (exact)

### 3.3 Create the `Bloomwire::WhatsappSetup` mapping (SuperAdmin, non-secret only)
SuperAdmin → **Bloomwire WhatsApp Setups → New**. Enter **non-secret** fields:
`account_id`, `inbox_id`, `channel_whatsapp_id`, `waba_id`, `phone_number_id`, `display_phone_number`,
`setup_status = configured`.

### 3.4 Validate account / inbox / channel alignment (model-enforced)
The mapping will refuse to save unless:
- the **inbox belongs to the account**, and the **channel belongs to the account**;
- the **inbox is the channel's own inbox**;
- `phone_number_id` is **globally unique** (one customer ⇒ one mapping ⇒ one inbox).

### 3.5 Add agents to the inbox
Add the customer's agents to the WhatsApp inbox so they can handle conversations.

---

## 4. Global webhook setup (Ops + customer's Meta admin)

- **Use the global router callback only:** `https://<public-host>/bloomwire/webhooks/whatsapp`.
- **Subscribe field:** `messages`.
- **GET verification:** Meta sends `hub.verify_token`; it is validated against the **global verify token**
  (`BLOOMWIRE_WHATSAPP_GLOBAL_VERIFY_TOKEN`) — handled as a **secret** (read from server `.env`, never pasted in
  chat). Valid token → 200 + challenge; wrong/missing → 401; router OFF → 404.
- **POST signature:** verified against `WHATSAPP_APP_SECRET` (global embedded-signup app secret). Bad/missing
  signature → 401, fail-closed.
- **Do NOT use the native per-channel webhook** (`/webhooks/whatsapp/<phone_number>`) for managed customers. In
  managed mode the **global router owns inbound**; pointing a customer WABA at the native URL bypasses the router.

> Meta webhook subscription is **manual** today (no automation — see §9).

---

## 5. Readiness gate (must be GREEN before go-live)

Go-live readiness has **two** parts: (5.1) the checks the readiness console **actually verifies**, and (5.2) the
**manual Ops prerequisites** the console does **not** verify and that Ops must confirm **separately**. Both must
pass before flipping the mapping to routeable (5.3).

### 5.1 Console-verified readiness checks
Open the **SuperAdmin readiness console**: `/super_admin/bloomwire_whatsapp_setups/:id/readiness`
(`Bloomwire::WhatsappRealHopReadiness` — read-only, secret-free, masked). These are the checks it actually
covers; all must PASS:

- **Feature toggles:** `BLOOMWIRE_MODE_ENABLED`, `BLOOMWIRE_PRIVACY_HARDENING`,
  `BLOOMWIRE_GLOBAL_WEBHOOK_ROUTER` (router is privacy-dependent).
- **Secrets present (presence only):** `WHATSAPP_APP_SECRET`, `BLOOMWIRE_WHATSAPP_GLOBAL_VERIFY_TOKEN`,
  `BLOOMWIRE_WHATSAPP_PUBLIC_CALLBACK_HOST` / callback URL.
- **Setup presence + status:** mapping present and `ready_for_webhook`, `phone_number_id` present, and
  account / inbox / channel all present.
- **Mapping consistency:** `inbox_belongs_to_account`, `channel_belongs_to_account`, `inbox_matches_channel`.
- **Channel alignment:** `channel_provider_whatsapp_cloud`, `channel_phone_number_present`, and
  `channel_provider_config_phone_number_id_matches` (provider_config `phone_number_id` matches).
- **`router_handoff_safe`** (the global router would resolve to this exact channel/inbox).

### 5.2 Manual Ops prerequisites before go-live (NOT verified by the readiness console)
These are **required**, but are **not** checked by `Bloomwire::WhatsappRealHopReadiness` / the SuperAdmin readiness
page. **Do not assume the console covers them** — Ops must verify each one **separately** before go-live:

- **Managed restriction toggles ON:** `BLOOMWIRE_RESTRICT_NATIVE_WHATSAPP_SETUP`,
  `BLOOMWIRE_RESTRICT_PROVIDER_SETUP`, `BLOOMWIRE_RESTRICT_ACCOUNT_ADMIN`, `BLOOMWIRE_RESTRICT_BOT_MANAGEMENT`
  (so business users cannot configure the provider or see secrets — see §8).
- **Encryption configured:** `Chatwoot.encryption_configured? == true`.
- **`provider_config` encrypted at rest / backfilled** before storing a **real** customer token (ADR-0006). Do not
  store a real token until this is confirmed.
- **OSS-only confirmation** (if applicable to the env): `DISABLE_ENTERPRISE=true`.

> The readiness console does **not** verify the managed restriction toggles or encryption-at-rest. Treat §5.2 as a
> separate manual gate that Ops checks by hand before go-live.

### 5.3 Flip to routeable
Only when **both** §5.1 (console-verified) and §5.2 (manual Ops prerequisites) pass, set
`setup_status = ready_for_webhook`. Only then will the router resolve this customer's inbound.

---

## 6. Live verification checklist (human-operated)

> Real Meta calls happen here — perform only with explicit go-ahead. Capture **masked** evidence only.

1. **Inbound isolation:** send a WhatsApp from the **customer's** phone → it appears **only** in **Aroma Flora's**
   inbox (correct account/inbox).
2. **Cross-tenant control:** confirm the **Bloomwire Dev** inbox (and any other customer inbox) shows **no** new
   message from this event.
3. **Outbound:** an agent replies from the Aroma Flora inbox UI → the **physical phone** receives it.
4. **Status:** the reply reconciles `sent → delivered → read`.
5. **Log hygiene:** webhook logs show **no** payload PII (customer phone/profile/`wa_id`) and **no** secrets
   (Phase 13D/13D.2 hardening; `entry => [FILTERED]`, jobs log no args).
6. **Unknown id fail-closed (optional, safe):** a webhook for an unmapped `phone_number_id` creates **nothing**.

---

## 7. Isolation rules (must hold)

- **Aroma Flora ↛ Bloomwire Dev:** Aroma Flora's `phone_number_id` resolves only to Aroma Flora's mapping/inbox.
- **PEPPER ST ↛ Aroma Flora:** a different `phone_number_id` ⇒ a different mapping/account ⇒ a different inbox.
- **Unknown `phone_number_id` ⇒ fail closed:** the router returns no setup, enqueues no job, creates no message
  (returns 200 only so Meta does not retry).

**Why it holds (enforced in code):** `phone_number_id` is globally unique on the mapping; the mapping validates
account/inbox/channel consistency; the router resolves exactly one `ready_for_webhook` mapping and verifies the
channel is aligned (`provider_config['phone_number_id']` + `phone_number == "+<display>"`) before handing off to
the existing job, which **re-resolves to the same channel/inbox**. Cross-tenant leakage is not possible.

---

## 8. Permission rules (enforced in code)

- **Bloomwire Ops/SuperAdmin** owns provider setup + secrets (separate `/super_admin` auth; unaffected by the
  managed-mode restrictions).
- **Business Owner (account admin)** can manage their **team/agents** and inbox settings and reply to messages, but
  is **blocked** from WhatsApp/provider setup, account control-plane (account settings + webhooks), and bots — and
  **cannot see provider secrets** (`provider_config` is admin-gated **and** secret-scrubbed in API responses **and**
  encrypted at rest).
- **Staff/Agent** is **inbox-only**: view assigned conversations + reply; cannot configure channels, manage the
  team, or see `provider_config`.

---

## 9. Known parked / deferred items (do not block the core pilot)

- **Phase 13E — template / out-of-window messaging:** **parked** until an **approved** template exists on the
  customer WABA (current dev WABA: 0 approved). Core 24h session chat is unaffected. See `../parked-items.md` (PARK-13E).
- **S2 — secure Ops credential-capture surface:** **not built.** Access token enters `provider_config` via an
  Ops-only console/embedded-signup path for now (§3.1).
- **S3 — one-click "provision customer" orchestration:** **not built.** Steps §1–§3 are manual.
- **Meta webhook registration for the global router:** **manual** in the Meta dashboard (§4); no automation.

---

## 10. Evidence template (fill per onboarding — masked only)

**Customer:** `Aroma Flora`  ·  **Account id:** `<masked/short>`  ·  **Date:** `<UTC>`  ·  **Deployed SHA:** `<sha>`

### A. Setup & mapping
| Item | Expected | Result (masked) | PASS/BLOCKED |
|---|---|---|---|
| Clean account created | new `account_id` | `acct ****` | |
| Business Owner invited (admin) | 1 admin | `present` | |
| Agents added to inbox | n agents | `<n>` | |
| Channel `provider == whatsapp_cloud` | yes | `yes/no` | |
| `channel.phone_number == +<display>` | match | `****<last4>` | |
| `provider_config.phone_number_id` matches | exact | `****<last4>` | |
| `provider_config` access token | present (secret) | `present` | |
| `Bloomwire::WhatsappSetup` created | configured | `configured` | |
| inbox/channel/account alignment | valid | `valid` | |

### B1. Console-verified readiness checks (§5.1)
| Check | Result | PASS/BLOCKED |
|---|---|---|
| Feature toggles ON (mode / privacy / global router) | `on` | |
| Secrets present (app secret / verify token / callback host) | `present` | |
| Setup present + `ready_for_webhook` + phone_number_id + account/inbox/channel | `pass` | |
| Mapping consistency + channel alignment + provider_config phone_number_id match | `pass` | |
| `router_handoff_safe` | `pass` | |

### B2. Manual Ops prerequisites — NOT console-verified (§5.2)
| Check | Result | PASS/BLOCKED |
|---|---|---|
| Restriction toggles ON (native_whatsapp / provider_setup / account_admin / bot_management) | `on` | |
| `Chatwoot.encryption_configured? == true` | `yes` | |
| `provider_config` encrypted at rest / backfilled before real token | `yes` | |
| OSS-only (`DISABLE_ENTERPRISE=true`) if applicable | `yes/n-a` | |

### B3. Go-live actions
| Action | Result | PASS/BLOCKED |
|---|---|---|
| `setup_status` → `ready_for_webhook` (only after B1 + B2) | `ready` | |
| Meta webhook → global router URL, `messages` subscribed | `set` | |

### C. Live verification
| Check | Result (masked) | PASS/BLOCKED |
|---|---|---|
| Inbound reaches ONLY Aroma Flora inbox | `msg id <n>` | |
| Bloomwire Dev inbox unchanged | `no new msg` | |
| Outbound reply reaches phone | `delivered` | |
| Status reconciles sent/delivered/read | `read` | |
| Logs: no payload PII / no secrets | `0 / 0` | |
| Unknown phone_number_id fails closed (optional) | `nothing created` | |

**Overall verdict:** `READY` / `BLOCKED (reason)` — no secrets or full phone numbers in this record.

---

## Appendix — read-only inspection (masked; run on the deployed server)

Use the deployment runbook's access pattern. These are **read-only** and print **masked** values only — never
secrets/full numbers. (Examples; adapt ids.)

- **List the mapping + readiness:** SuperAdmin readiness console (preferred), or a read-only
  `Bloomwire::WhatsappRealHopReadiness.for(setup_id: <id>).result` (returns masked identifiers + per-check status).
- **Confirm encryption configured:** check `Chatwoot.encryption_configured?` (true/false) — no values printed.
- **Confirm toggles:** `Bloomwire::Features.enabled?(:global_webhook_router)` etc. (true/false).
- **Topology sanity:** counts of accounts / whatsapp channels / `ready_for_webhook` setups (no names/secrets).

> Any command that would **write** (sync, status flips, channel edits) or **call Meta** is out of scope for
> read-only verification and requires explicit approval.
