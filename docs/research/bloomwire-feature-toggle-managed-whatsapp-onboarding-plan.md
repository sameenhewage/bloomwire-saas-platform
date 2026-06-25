# Bloomwire / Unecast — Feature-Toggle Managed WhatsApp Onboarding Plan

> **Status:** **Planning document only.** No product code, no branches, no branch switching, no migrations, no PRs,
> no Chatwoot behavior changes. **S-01…S-06 are NOT started.** Pricing/billing out of scope.
> **Purpose:** Plan how Bloomwire/Unecast **managed WhatsApp onboarding** is added **behind feature toggles** while
> preserving original Chatwoot behavior.
> **Sources:** [`bloomwire-evidence-collection-report.md`](./bloomwire-evidence-collection-report.md) ·
> [`bloomwire-evidence-review-and-decision-register.md`](./bloomwire-evidence-review-and-decision-register.md) ·
> [`bloomwire-runtime-analysis-and-rCA-report.md`](./bloomwire-runtime-analysis-and-rCA-report.md) ·
> [`bloomwire-s07-live-ui-runtime-smoke-report.md`](./bloomwire-s07-live-ui-runtime-smoke-report.md).

## Core protected rule

- **Bloomwire/Unecast features OFF → original Chatwoot behavior unchanged.**
- **Bloomwire/Unecast features ON → Bloomwire managed onboarding + global webhook/router + routing registry + privacy controls active.**

## Proven baseline this plan builds on (from S-07 + RCA)

- Super Admin → WhatsApp Embedded page has only `WhatsApp App ID`, `WhatsApp App Secret`, `WhatsApp Configuration ID`,
  `WhatsApp API Version`; **shows no webhook URL**, makes **no webhook call** on load, and the **App Secret input is
  not masked** (`type="text"`, cleartext). **[RUNTIME-PROVEN, S-07 §6.1]**
- Account → Settings → Inboxes → WhatsApp is the **native, customer-facing** channel/inbox creation UI exposing 5
  technical fields (`Inbox Name`, `Phone number`, `Phone number ID`, `Business Account ID`, `API key`) → submits
  `POST /api/v1/accounts/:id/inboxes`. No tenant-side hiding on `develop`. **[RUNTIME-PROVEN, S-07 §6.2]**
- A SuperAdmin is **not** automatically an Account Administrator; account access is via explicit `AccountUser`
  membership; the Super Admin Console is a **separate** `/super_admin/sign_in` boundary. **[RUNTIME-PROVEN, S-07 §6.3]**
- `develop` @ `56c98c8` is the **pure Chatwoot / Feature-OFF baseline** (zero `bloomwire` references; Bloomwire
  slices live on `version_1`, PRs #19–#29). **[RUNTIME-PROVEN, S-07 §6.4]**

---

## 1. Executive summary

Bloomwire/Unecast becomes a **thin, additive control-plane layer** on top of unmodified Chatwoot, switched on by
feature toggles. With every toggle **OFF**, the app is byte-for-byte stock Chatwoot — exactly today's `develop`
baseline (S-07 proved this). With toggles **ON**, Bloomwire takes over the *edges* Chatwoot does not own per-tenant:
it **onboards WhatsApp for the customer** (the customer never touches Meta App, webhook, Phone Number ID, Business
Account ID, or API key), runs a **single global Meta webhook + router** that resolves inbound messages by
`phone_number_id` into the correct tenant inbox, keeps an **additive routing/control registry**, and applies
**privacy hardening** (masked secrets, no token/body leakage, audited support access).

The strategy is deliberately **wrap-not-replace**: Chatwoot remains the **source of truth** for accounts, inboxes,
contacts, conversations, and messages; Bloomwire reuses the existing WhatsApp pipeline
(`Webhooks::WhatsappEventsJob` → incoming-message services) rather than forking it. A **central feature-check
service** (not scattered `ENV` checks) decides ON/OFF at a small number of well-defined seams identified in the RCA.
**Rollback is "turn the toggles OFF."** Because the design is additive, the only spikes still required before
implementation confidence are the runtime gates **S-01…S-06** (S-07 is already complete).

---

## 2. Feature toggle strategy

### 2.1 Toggle hierarchy

A **master toggle** with **feature-level sub-toggles**. The master is an AND-gate: if the master is OFF, **every**
sub-feature is forced OFF regardless of its stored value.

| Toggle | Suggested key | Default | Controls |
|---|---|---|---|
| **Master** — Bloomwire/Unecast mode | `BLOOMWIRE_MODE_ENABLED` | OFF | Global on/off for the entire Bloomwire layer |
| Managed WhatsApp onboarding | `BLOOMWIRE_MANAGED_WHATSAPP_ONBOARDING` | OFF | Ops-driven onboarding flow + statuses + routing-registry writes |
| Global Meta webhook router | `BLOOMWIRE_GLOBAL_WEBHOOK_ROUTER` | OFF | Bloomwire global ingress + `phone_number_id` routing + callback-URL indirection |
| Restrict native customer WhatsApp setup | `BLOOMWIRE_RESTRICT_NATIVE_WHATSAPP_SETUP` | OFF | Hide tenant WhatsApp UI **and** guard the create APIs |
| Privacy hardening | `BLOOMWIRE_PRIVACY_HARDENING` | OFF | Secret masking, DTO scrubbing, impersonation/self-add controls, log/job scrubbing, support audit |
| Outgoing gateway *(later)* | `BLOOMWIRE_OUTGOING_GATEWAY` | OFF | Tenant outbound API/webhooks (deferred; gated on S-04) |
| Custom branding *(later)* | `BLOOMWIRE_CUSTOM_BRANDING` | OFF | White-label naming/branding (deferred) |

### 2.2 Where toggles live + how they're read

- **Storage:** installation-level `InstallationConfig` rows — the same mechanism the proven `WHATSAPP_*` keys use,
  read via `GlobalConfigService.load(...)` (`app/lib/global_config_service.rb:2-16`). This keeps Bloomwire toggles in
  the same admin surface and cache as existing config.
- **Read path:** a single **central feature-check service** (recommended: `Bloomwire::Features`) exposes
  `Bloomwire::Features.enabled?(:managed_whatsapp_onboarding)` etc., internally AND-ing the master toggle. **No
  scattered `ENV['...']` reads** in controllers/components — they call the service only.
- **"Managed account" scoping:** "restrict native setup" must know whether *this account* is Bloomwire-managed. The
  recommended source of truth for that per-account flag is the **routing/control registry** (§6, a `managed`/owner
  marker), so restriction is scoped to managed tenants rather than blanket-applied. *(Exact scope — installation-wide
  vs per-account — is an open question, §11.)*

### 2.3 OFF vs ON behavior

| Surface | OFF (master OFF or sub-feature OFF) | ON |
|---|---|---|
| Super Admin pages | Stock Chatwoot WhatsApp-Embedded page only | + Bloomwire/Unecast settings page (§3) |
| Account WhatsApp UI | Native provider chooser + manual/embedded forms fully visible (S-07 baseline) | Hidden/disabled for managed tenants (§4) |
| Create APIs (`/inboxes`, `/whatsapp/authorization`) | Native behavior, unguarded | Guarded: tenant-initiated WhatsApp creation blocked; Ops path allowed (§4) |
| Inbound webhook | Per-phone-number callback → `Webhooks::WhatsappController` (stock) | Meta → Bloomwire global webhook → router → `WhatsappEventsJob` (§7) |
| Routing registry | Not written/read | Written at onboarding; read by router (§6) |
| Secrets/logs/impersonation | Stock Chatwoot (unmasked secret, current logging) | Hardened (§8) |

**Invariant:** With all toggles OFF the app equals `develop` (S-07-proven). Toggles are **purely additive**.

---

## 3. Super Admin Console plan

### 3.1 Option comparison

| | **Option A — extend the existing WhatsApp Embedded page** | **Option B — separate "Bloomwire / Unecast Features" page** |
|---|---|---|
| OFF preservation | Risk: edits a **stock** administrate page → OFF baseline can drift | Clean: stock page untouched → OFF = stock guaranteed |
| Upgrade safety | Higher merge/upgrade conflict risk on a Chatwoot-owned view | Low: a net-new Bloomwire-owned page/route |
| Separation of concerns | Mixes Meta-app credentials with Bloomwire control-plane | Clear split: credentials vs Bloomwire mode/router/onboarding |
| Rollback | Harder to isolate | Trivial: gate/remove one page |
| Discoverability | Familiar location | New, clearly-labeled location |

### 3.2 Recommendation — **Option B (separate page)**

Create a Bloomwire-owned **"Bloomwire / Unecast Features"** super-admin page (new route + controller, additive,
gated by the master toggle). Keep the stock WhatsApp Embedded page **unmodified** except for the one **privacy fix**
(secret masking) which is applied under the privacy-hardening toggle (§8) so OFF stays stock. This best satisfies
*OFF = unchanged Chatwoot* and *wrap-not-replace*. Reuse the same `InstallationConfig` + `GlobalConfigService`
storage so values live in the existing admin/config plumbing.

### 3.3 Suggested settings on the Bloomwire page

| Setting / action | Type | Notes |
|---|---|---|
| Enable Bloomwire/Unecast mode | toggle | Master (`BLOOMWIRE_MODE_ENABLED`) |
| Enable managed WhatsApp onboarding | toggle | Sub-feature |
| Enable global Meta webhook router | toggle | Sub-feature |
| Restrict native customer WhatsApp setup | toggle | Sub-feature |
| Global webhook callback URL | read-only field | The single Bloomwire ingress URL (built from `FRONTEND_URL`/configured host) |
| Webhook verify token | masked field | Used by Meta GET-verify handshake; mask + reveal-on-demand |
| Webhook status | read-only indicator | e.g. `not_configured / verified / receiving / error` |
| Last webhook received timestamp | read-only | Driven by `last_webhook_at` (registry / control state) |
| Copy webhook URL | action | Clipboard copy of the callback URL |
| Regenerate verify token | action | Rotates the verify token (with confirmation) |
| Test webhook | action | Sends a synthetic verify/ping to confirm reachability (no tenant data) |
| Masked/secure App Secret handling | behavior | App Secret rendered `type="password"`, never echoed back in cleartext (§8) |

*(Webhook-URL/verify/test behaviors are designed here; their live correctness is gated by S-02/S-03, §10.)*

---

## 4. Account Workspace behavior

### 4.1 Behavior by mode

- **OFF:** the native account-level WhatsApp setup remains **visible and unchanged** — provider chooser +
  `CloudWhatsapp.vue` manual form + `WhatsappEmbeddedSignup.vue`, submitting to the native endpoints. This is the
  S-07-proven baseline and must not regress.
- **ON (managed tenant):** the **customer-facing technical WhatsApp setup is hidden/disabled**. Customers must never
  see or submit Meta App / webhook / Phone Number ID / Business Account ID / API key.

### 4.2 UI hiding is necessary but **not sufficient** — guard the APIs

Hiding components only removes the button; the REST endpoints are still reachable directly. Both layers are required.

| Layer | Insertion point | ON behavior |
|---|---|---|
| UI — provider chooser + forms | `app/app/javascript/dashboard/routes/dashboard/settings/inbox/channels/Whatsapp.vue`, `CloudWhatsapp.vue`, `WhatsappEmbeddedSignup.vue`, `360DialogWhatsapp.vue`, and the SPA route `settings/inboxes/new/whatsapp` | Hide/disable WhatsApp tiles + forms for managed tenants (driven by a read-only DTO flag, mirroring prior art **WA.2D** on `version_1`) |
| API — manual create | `Api::V1::Accounts::InboxesController#create` / `create_channel` (`app/app/controllers/api/v1/accounts/inboxes_controller.rb:33-46,93-101`) | Reject `channel.type == 'whatsapp'` for tenant (non-Ops) callers |
| API — embedded signup | `Api::V1::Accounts::Whatsapp::AuthorizationsController#create` (`app/app/controllers/api/v1/accounts/whatsapp/authorizations_controller.rb:7-24`) | Reject tenant-initiated embedded signup |

Recommended mechanism: a small **before_action guard concern** (e.g. `Bloomwire::GuardNativeWhatsappSetup`) included
into those two controllers that consults `Bloomwire::Features` + the account's managed flag, returning `403` for
tenant callers when restriction is ON. This is additive and removable.

### 4.3 Ops/Admin must still create channels internally

When restriction is ON, **Bloomwire Ops** must still create/link `Channel::Whatsapp` + `Inbox` on behalf of the
customer. Recommended: an **Ops-only path** (super-admin/ops-scoped endpoint or service) that reuses the existing
`Whatsapp::ChannelCreationService` / inbox-creation internally and is exempt from the tenant guard (analogous to how
embedded signup marks `provider_config['source'] = 'embedded_signup'`). The guard distinguishes **Ops context** from
**tenant context**, not merely "is WhatsApp".

---

## 5. Managed onboarding flow

### 5.1 Responsibilities

| Customer (business owner) | Bloomwire Ops |
|---|---|
| Registers in Bloomwire | Verifies business details |
| Provides business details | Creates/links Chatwoot `Account` |
| Provides WhatsApp Business number | Creates owner `User` + `AccountUser` (admin) |
| Provides OTP / approval **if Meta requires it** | Performs WhatsApp onboarding (embedded signup or manual, Ops-side) |
| | Creates `Channel::Whatsapp` + `Inbox` (reusing native services) |
| | Writes routing metadata to the registry (§6) |
| | Activates dashboard access for the owner |

The customer **never** configures Meta App, webhook, Phone Number ID, Business Account ID, or API key.

### 5.2 Onboarding statuses

State machine on the routing/control registry (`onboarding_status`):

```
registered
   → number_submitted
       → setup_in_progress
           → waiting_for_customer_otp_or_approval   (only if Meta requires it)
               → active
           ↘ failed   (any step can fail; recoverable back to setup_in_progress)
```

| Status | Meaning | Set by |
|---|---|---|
| `registered` | Owner registered + business details captured | Customer registration |
| `number_submitted` | WhatsApp Business number provided | Customer |
| `setup_in_progress` | Ops performing WhatsApp onboarding | Ops |
| `waiting_for_customer_otp_or_approval` | Blocked on customer OTP/Meta approval | Ops (awaiting customer) |
| `active` | Channel + Inbox live, routing registered, dashboard enabled | Ops / system on success |
| `failed` | Onboarding failed; needs retry | System/Ops |

*(Exact OTP/approval capture mechanics in a managed flow are an open question — §11.)*

---

## 6. Routing registry plan

An **additive** Bloomwire routing/control table (recommended name `bloomwire_channel_integrations`, consistent with
the prior-art model referenced in S-07). **No migration is created in this plan** (constraint) — this is the target
schema for a later, gated implementation.

### 6.1 Suggested fields

| Field | Purpose |
|---|---|
| `id`, `created_at`, `updated_at` | Standard |
| `account_id` | Owning Chatwoot account (FK, indexed) |
| `inbox_id` | Linked Chatwoot inbox (FK) |
| `channel_id` | Linked `Channel::Whatsapp` id |
| `channel_type` | Channel class (future-proof for IG/Messenger/SMS) |
| `provider` | e.g. `whatsapp_cloud` |
| `waba_id` / `business_account_id` | WhatsApp Business Account id |
| `phone_number_id` | **Router key** — unique index for `phone_number_id → account/inbox` resolution |
| `display_phone_number` | Human-readable number |
| `onboarding_status` | §5 state machine |
| `connection_status` | Live health (`connected / degraded / disconnected`) |
| `last_webhook_at` | Drives "Last webhook received" (§3) |
| `managed` *(suggested)* | Marks the account/integration as Bloomwire-managed (drives §4 restriction) |

### 6.2 Hard rules

- **Do not duplicate** conversations, messages, or contacts — Chatwoot remains source of truth for inbox /
  conversation / message / contact.
- **Do not copy WhatsWay code** — concepts only (clean-room), per D-09.
- **Do not duplicate secrets unless required** — secrets (`api_key`, verify token) stay in
  `Channel::Whatsapp#provider_config`; the registry stores **non-secret routing identifiers + status** only.
- The registry is a **routing + control-plane index** (fast `phone_number_id` lookup + onboarding/health state),
  **not** a content store. It never holds message bodies.

---

## 7. Global webhook / router plan

### 7.1 Current vs target

| | **Current Chatwoot (OFF / stock)** | **Bloomwire target (ON)** |
|---|---|---|
| Registration | **Per-phone-number** callback `FRONTEND_URL/webhooks/whatsapp/<phone_number>`, registered per channel by `Whatsapp::WebhookSetupService` (`app/app/services/whatsapp/webhook_setup_service.rb:58-80`) | **One global** Bloomwire callback URL registered for all managed numbers |
| Ingress | `Webhooks::WhatsappController#process_payload` (`app/app/controllers/webhooks/whatsapp_controller.rb:6-15`) | Bloomwire global endpoint (thin) |
| Signature | Per-channel secret + global `WHATSAPP_APP_SECRET` fallback (`whatsapp_controller.rb:25-30`) | Verify with one app secret/verify strategy |
| Resolution | Payload metadata `phone_number_id`/`display_phone_number` → `Channel::Whatsapp` → inbox (`app/app/jobs/webhooks/whatsapp_events_job.rb:146-161`) | Same resolution, via routing registry first, fallback to payload resolution |
| Processing | `WhatsappEventsJob` → `IncomingMessageWhatsappCloudService` → inbox | **Identical** — reuse the existing pipeline |

### 7.2 Target flow

```
Meta → Bloomwire global webhook
     → verify signature (one app secret / verify token)
     → extract phone_number_id from entry[].changes[].value.metadata
     → resolve phone_number_id → account/inbox/channel  (routing registry; fallback = Channel::Whatsapp lookup)
     → forward into Webhooks::WhatsappEventsJob (existing pipeline)
     → message persisted in the correct inbox
```

### 7.3 Design notes

- **Reuse, don't fork:** the router's only new responsibility is *verify + resolve + enqueue*; message processing
  stays in `WhatsappEventsJob` (which already resolves by payload metadata independent of the URL — RCA §6.E).
- **Callback indirection insertion point:** `Whatsapp::WebhookSetupService#build_callback_url`
  (`webhook_setup_service.rb:75-80`) returns the Bloomwire global URL when the router toggle is ON.
- **Feasibility:** the resolution chain and the forward target are **[CODE-PROVEN]**, but a Bloomwire-owned global
  ingress with one app secret and **no loss/duplication** across multiple WABAs is **runtime-gated by S-02 + S-03**
  (§10). This plan does not assert it works at runtime.

---

## 8. Privacy / security hardening plan

Activated by the **privacy hardening** toggle (so OFF preserves stock unless explicitly configured otherwise).

| Gap (evidence) | Hardening |
|---|---|
| App Secret rendered in cleartext (`type="text"`) — **[RUNTIME-PROVEN, S-07 §6.1]** | Render secret inputs as `type="password"`; never echo a stored secret back in cleartext (the controller returns raw values — RCA §6.A) |
| API keys/tokens exposed in tenant DTO | Scrub `provider_config` from tenant-facing inbox serialization (`app/app/views/api/v1/models/_inbox.json.jbuilder`) so managed-tenant admins never receive `api_key`/tokens |
| SuperAdmin **self-add** as `AccountUser` (`app/app/controllers/super_admin/account_users_controller.rb:12-18`) | Restrict and/or audit self-add into accounts |
| SuperAdmin **impersonation** unaudited (`app/app/models/concerns/sso_authenticatable.rb:27-31`; only a FE `sessionStorage` flag) | Restrict/gate impersonation and **audit every impersonation + cross-tenant access** |
| Audit is enterprise-overlay + premium-gated; impersonation/message-reads never audited (RCA §6.F) | Add a **Bloomwire-owned support-access audit** (independent of the enterprise `audit_logs` feature) |
| Token leakage in explicit logs (`app/app/controllers/api/v1/accounts/callbacks_controller.rb:25-30`; `app/app/services/whatsapp/providers/base_service.rb:44-45`) | Scrub tokens from those log statements |
| Whole inbound payload enqueued to Sidekiq (`whatsapp_controller.rb:13`); message bodies unscrubbed | Scrub message bodies/tokens from logs **and** Sidekiq job args |

- **ON → privacy hardening active.**
- **OFF → original Chatwoot preserved** (no masking/scrubbing changes) unless explicitly configured.
- **Exact requirements gated by S-05 (impersonation/audit) + S-06 (token/log/Sidekiq scrubbing)** — this plan sets
  direction, the spikes produce the precise inventory.

---

## 9. Upgrade safety / rollback plan

- **No Chatwoot core deletion.** Nothing native is removed.
- **Wrap/adapt, do not replace.** Use additive routes, a new super-admin page (Option B), `before_action` guard
  concerns, enterprise-style overlay modules (`prepend_mod_with`/`include_mod_with`), and an additive registry table.
  Avoid editing stock files wherever a wrapper suffices.
- **Central feature-check service** (`Bloomwire::Features`), **not** scattered `ENV` checks — one place to reason
  about ON/OFF and to flip for rollback.
- **OFF mode keeps original Chatwoot route/UI/API behavior** (S-07-proven baseline is the contract).
- **ON mode activates the Bloomwire layer** at the defined seams only.
- **Rollback = turn Bloomwire features OFF.** Because the layer is additive:
  - Created `Channel::Whatsapp` + `Inbox` records are **native Chatwoot records** and keep working.
  - The routing registry is read-only to the conversation engine; ignoring it changes nothing in core.
  - **Caveat (honest):** if the **global webhook router** was ON and Meta callbacks were re-pointed to the Bloomwire
    URL, rolling the router back to per-number requires **re-pointing callbacks at Meta** (a Meta-side action, not a
    code toggle). Plan a documented re-point step for router rollback specifically.

---

## 10. Runtime gates before implementation

These remain **required before final implementation confidence**. **S-01…S-06 are NOT started in this plan.**

| Gate | Goal | Unblocks | Plan section it de-risks | Status |
|---|---|---|---|---|
| **S-01** | Multiple WhatsApp inboxes under one account (no collision, correct routing/listing) | P-01 | §4, §6 | **Required** |
| **S-02** | Multi-WABA webhook routing — two `phone_number_id`s → correct account/inbox, no cross-tenant leak | P-02 | §6, §7 | **Required** |
| **S-03** | Global webhook front-door — one ingress, one app secret, forward to `WhatsappEventsJob`, no loss/dup | P-03 | §3, §7 | **Required** |
| **S-04** | Outgoing injection preserves history + reconciles status | P-04 | outgoing gateway (later) | **Required** |
| **S-05** | SuperAdmin impersonation / privacy capability + audit-gap inventory | P-05 | §8 | **Required** |
| **S-06** | Token / log / Sidekiq job-arg leakage inventory + scrubbing requirements | P-05 | §8 | **Required** |
| **S-07** | Live UI/runtime baseline (OFF baseline + secret-masking gap) | C / Areas A,B | §1, §4, §8 | **Complete** |

---

## 11. Open questions (unresolved — not answered here)

- **Restriction scope:** installation-wide vs per-account `managed` flag for "restrict native customer WhatsApp
  setup" — where does the managed designation live, and does it ever coexist with self-serve accounts? *(§2.2, §4)*
- **Privacy-in-OFF:** should secret masking / DTO scrubbing apply universally (as a safe fix) or strictly only when
  privacy hardening is ON? *(§8)* — relates to register **Q-04**.
- **Global webhook ownership (Q-01):** Bloomwire registers its own Meta callback and forwards, vs keeping Chatwoot's
  per-number registration — gated on **S-03**.
- **Single Meta App strategy (Q-02):** one app secret + verify token spanning all tenant WABAs vs per-channel
  secrets — gated on **S-02/S-03**.
- **Impersonation policy (Q-03):** disable entirely, gate behind explicit tenant consent, or audit-only — gated on **S-05**.
- **Secret handling (Q-04):** encrypt `provider_config` secrets at rest **and** the exact log/Sidekiq scrubbing set — gated on **S-06**.
- **OTP / Meta approval mechanics:** in a managed (Ops-run) flow, how is a customer OTP / Meta approval captured and
  relayed, and what UX does the customer see in `waiting_for_customer_otp_or_approval`? *(§5)*
- **Outgoing gateway shape (Q-05):** reuse `Channel::Api`/Platform API vs a dedicated Bloomwire client API
  (keys/rate-limits/idempotency/outbound webhooks) — deferred toggle.
- **Provider strategy (Q-06):** `whatsapp_cloud` only vs also `default` (360dialog); routing keys as indexed columns
  vs `provider_config` jsonb.
- **Owner role nuance (Q-10) / tenant hierarchy (Q-09):** is `administrator`/`agent` enough; is an
  org/reseller-above-account ever needed?

---

## 12. Recommended next step after this plan

**Run S-01 first**, immediately followed by **S-02**.

- **Why S-01 first:** it is the **cheapest** spike with **zero external dependencies** (no real Meta app needed —
  seed two `Channel::Whatsapp` + inboxes under one account), and it validates the **foundational premise** the entire
  managed model rests on: one account holding multiple WhatsApp inboxes with correct creation, listing, and routing
  (P-01). It is also a hard **prerequisite** for S-02 (which needs ≥2 WABAs/inboxes to exist).
- **Then S-02 (the pivotal routing proof):** it directly validates the **routing-registry + global-router** core of
  §6/§7 — that two `phone_number_id`s resolve to the correct account/inbox with **no cross-tenant leakage** — using
  the existing controller/job, still without a real Meta app. Passing S-01→S-02 de-risks the highest-architecture
  pieces before the more involved **S-03** (global front-door) and the privacy spikes **S-05/S-06**.

**Stop here.** This is a planning document only; no spikes are started and no code is implemented.
