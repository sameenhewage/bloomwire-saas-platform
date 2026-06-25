# Bloomwire / Unecast — Final Feature-Toggle Architecture Plan (Build-Ready)

> **Status:** **Architecture / documentation only.** No product code, branches, branch switches, migrations, PRs,
> in-code feature toggles, or Chatwoot behavior changes were produced. Nothing committed or pushed. No secrets / `.env`
> contents included. Pricing/billing **out of scope**.
> **Purpose:** The single build-ready architecture for **Bloomwire/Unecast managed WhatsApp onboarding** on top of
> Chatwoot, behind feature toggles, preserving original Chatwoot behavior when Bloomwire features are **OFF**.
> **Authoritative inputs (all runtime gates complete):** evidence-collection-report · evidence-review-and-decision-register ·
> runtime-analysis-and-rCA-report · s07-live-ui-runtime-smoke-report · feature-toggle-managed-whatsapp-onboarding-plan ·
> s01-multiple-whatsapp-inboxes · s02-multi-waba-webhook-routing · s03-global-webhook-frontdoor ·
> s04-outgoing-injection · s05-s06-privacy-security.

## Reading guide / proof labels
- **[RUNTIME-PROVEN]** — verified live in the running app (Rails runner / Chrome MCP against `chatwoot_dev`).
- **[CODE-PROVEN]** — verified by reading source.
- **[ASSUMPTION]** — design choice not directly proven; flagged for challenge.
- **[BLOCKER]** — requires real/sandbox Meta credentials before production; cannot be proven by a no-Meta spike.

This plan **consolidates proven facts only**. Anything not proven is labelled `[ASSUMPTION]` or `[BLOCKER]`.
WhatsWay is **reference-only** (concepts, never code — decision **D-09**).

---

## 1. Executive Summary

Bloomwire/Unecast is a **thin, additive control-plane layer** on top of **unmodified** Chatwoot, switched on by a
small set of **feature toggles**. With every toggle **OFF**, all **tenant-facing / runtime** behavior is byte-for-byte
stock Chatwoot — exactly today's `develop` baseline, which S-07 proved at runtime; the **only** OFF-state addition is the
**SuperAdmin-only** Bloomwire control page (the master-toggle bootstrap surface; zero tenant-facing impact). With toggles
**ON**, Bloomwire takes over only the *edges*
Chatwoot does not own per tenant:

1. It **onboards WhatsApp for the customer** (Ops-driven), so the customer never touches Meta App, webhook, Phone
   Number ID, Business Account ID, or API key.
2. It runs **one global Meta webhook + router** that verifies a single app-secret signature and resolves inbound
   payloads by `phone_number_id` into the correct tenant inbox — reusing Chatwoot's existing `WhatsappEventsJob`.
3. It keeps an **additive routing/control registry** (non-secret routing identifiers + onboarding/health status) —
   never duplicating conversations, messages, or contacts.
4. It applies **privacy hardening** (masked secrets, scrubbed DTOs/logs, non-mutating Sidekiq log/display redaction
   or encrypted payload handoff, restricted impersonation/self-add, and a Bloomwire-owned support-access audit) — required because Chatwoot's audit is enterprise-overlay and inert in
   the CE target.

The strategy is deliberately **wrap-not-replace**: Chatwoot remains the **source of truth** for accounts, inboxes,
contacts, conversations, and messages. A **central feature-check service** (`Bloomwire::Features`) — not scattered
`ENV` checks — decides ON/OFF at a small number of well-defined seams. **Rollback is "turn the toggles OFF."**

**All six runtime gates plus the live baseline are complete.** Routing, the global front-door, idempotency,
fail-closed behavior, and outgoing status reconciliation are **runtime-proven**. The only items that remain are
**live Meta-dependent steps** (real signature handshake, real outbound send, media/attachment path) that no no-Meta
spike can prove — they are explicit **[BLOCKER]s** for the final production phase.

---

## 2. Evidence Status (S-01 → S-07)

| Gate | Proved | Proof | Unblocks |
|---|---|---|---|
| **S-07** Live UI baseline | OFF = stock Chatwoot on `develop`; native WhatsApp UI fields; App Secret rendered **unmasked** (`type=text`); SuperAdmin ≠ auto account-admin | [RUNTIME-PROVEN] | baseline contract |
| **S-01** Multi-inbox / account | One `Account` holds 2+ `Channel::Whatsapp` + inboxes; both list; `phone_number` is **globally** unique; no collision | [RUNTIME-PROVEN] | **P-01 ✅** |
| **S-02** Multi-WABA routing | Inbound routes by `phone_number_id` to correct account/inbox; **no cross-tenant leak**; unknown/mismatch pnid **fails closed**; resolution is URL-independent | [RUNTIME-PROVEN] | **P-02 ✅** |
| **S-03** Global front-door | One app-secret HMAC verify (`sha256=`+`secure_compare`) → forward into unmodified `WhatsappEventsJob` → exactly 1 message; **duplicate → idempotent** (by `source_id`); invalid/malformed sig + unknown pnid **fail closed**; no per-number URL needed | [RUNTIME-PROVEN] | **P-03 ✅** |
| **S-04** Outgoing + status | Outbound injected without Meta; history preserved; `wamid` stored as `message.source_id`; status reconciles `sent→delivered→read→failed` by `source_id`; wrong `source_id` **fails closed** | [RUNTIME-PROVEN] (live **send** = [BLOCKER]) | **P-04 ✅** (send blocked) |
| **S-05/S-06** Privacy/security | SuperAdmin **self-add** + **impersonation** both reach tenant data; **CE audit inert** (`enterprise?` falsy, 0 audit rows, `audit_logs` premium off); `ParameterFilter` redacts tokens/keys **not** message bodies; `WhatsappEventsJob` job args carry message body; inbox DTO exposes raw `provider_config` | [RUNTIME-PROVEN] + [CODE-PROVEN] | **P-05 = real open risk** |

**Confirmed:** P-01, P-02, P-03, P-04 (all except the live Meta send), and P-05 (the risk is confirmed real, requiring
the privacy workstream). **Meta-live items still out of reach without real/sandbox credentials [BLOCKER]:** the live
Meta GET verify (`hub.challenge`) handshake, a real signed Meta callback, the actual outbound send
(`WhatsappCloudService#send_message` → `graph.facebook.com`), and media/attachment download.

---

## 3. Core Architecture Principle

1. **Chatwoot is the source of truth** for accounts, inboxes, contacts, conversations, and messages. Bloomwire
   **never** duplicates that data. [CODE-PROVEN baseline; D-01..D-07]
2. **Bloomwire is an additive control-plane layer.** It adds provider/onboarding/ingress/privacy at the edges via
   additive routes, a super-admin page, `before_action` guard concerns, enterprise-style overlay modules
   (`prepend_mod_with`/`include_mod_with`), and one additive registry table — it does **not** fork the conversation
   engine. [ASSUMPTION grounded in D-08]
3. **WhatsWay is reference only — no code copy** (clean-room concepts only). [D-09]
4. **Feature OFF means original Chatwoot behavior is unchanged.** The S-07 `develop` baseline is the binding contract;
   every slice must preserve it. [RUNTIME-PROVEN, S-07]

---

## 4. Feature Toggle Architecture

### 4.1 Toggle hierarchy

A **master toggle** AND-gates all sub-toggles: if the master is OFF, every sub-feature is forced OFF regardless of its
stored value.

**Privacy-hardening prerequisite (data-handling dependency).** Beyond the master AND-gate, `Bloomwire::Features` enforces
one **dependency**: the **managed-data** toggles — `BLOOMWIRE_MANAGED_WHATSAPP_ONBOARDING` and
`BLOOMWIRE_GLOBAL_WEBHOOK_ROUTER` — are **inert unless `BLOOMWIRE_PRIVACY_HARDENING` is also ON**. The moment a managed
tenant carries real customer data, the §11 gaps (raw `provider_config` DTOs, message bodies in logs/Sidekiq job args,
token logs, unaudited impersonation/self-add) are live, so managed traffic must **not** run unprotected. Enforcement is
**fail-closed**: `enabled?(:managed_whatsapp_onboarding)` and `enabled?(:global_webhook_router)` return **false** when
privacy hardening is OFF, and the SuperAdmin control page **refuses to enable** either managed-data toggle while privacy
hardening is OFF (offering to enable the bundle). Privacy hardening may be enabled **on its own** — it is a pure no-op
safety layer when no managed traffic exists. (Phase order already reflects this: Phase 2 privacy foundation lands before
the Phase 6 router / Phase 7 onboarding slices.)

| Toggle | Suggested key | Default | Controls |
|---|---|---|---|
| **Master** — Bloomwire mode | `BLOOMWIRE_MODE_ENABLED` | OFF | Global on/off for the entire Bloomwire layer |
| Managed WhatsApp onboarding | `BLOOMWIRE_MANAGED_WHATSAPP_ONBOARDING` | OFF | Ops onboarding flow + statuses + registry writes — **requires Privacy hardening ON** (§4.1, §11) |
| Global Meta webhook router | `BLOOMWIRE_GLOBAL_WEBHOOK_ROUTER` | OFF | Global ingress + `phone_number_id` routing + callback-URL indirection — **requires Privacy hardening ON** (§4.1, §11) |
| Restrict native WhatsApp setup | `BLOOMWIRE_RESTRICT_NATIVE_WHATSAPP_SETUP` | OFF | Hide tenant WhatsApp UI **and** guard the create APIs |
| Privacy hardening | `BLOOMWIRE_PRIVACY_HARDENING` | OFF | Secret masking, DTO/log/job scrubbing, impersonation/self-add controls, support audit — **prerequisite for managed onboarding/router** |
| Outgoing gateway *(later)* | `BLOOMWIRE_OUTGOING_GATEWAY` | OFF | Tenant outbound API/webhooks (deferred) |
| Custom branding *(later)* | `BLOOMWIRE_CUSTOM_BRANDING` | OFF | White-label naming/branding (deferred) |

### 4.2 Central feature-check service

- **Concept:** a single `Bloomwire::Features` service is the **only** place toggles are read. It exposes
  `Bloomwire::Features.enabled?(:managed_whatsapp_onboarding)` etc., internally AND-ing the master toggle. No scattered
  `ENV['...']` reads in controllers/components/jobs. One place to reason about ON/OFF and to flip for rollback.
- **Storage:** installation-level `InstallationConfig` rows, read via `GlobalConfigService.load(...)`
  (`global_config_service.rb:2-16`) — the same mechanism the proven `WHATSAPP_*` keys already use, so Bloomwire
  toggles live in the existing admin surface + cache. [CODE-PROVEN mechanism]
- **Per-account "managed" scoping:** "restrict native setup" must know whether *this account* is Bloomwire-managed.
  The source of truth for that flag is the **routing/control registry** (§8, `managed` marker), so restriction is
  scoped to managed tenants, not blanket-applied. Exact scope (installation-wide vs per-account) is **Open Q** (§17).

### 4.3 OFF / ON behavior matrix

| Surface | OFF (master OFF or sub-feature OFF) | ON |
|---|---|---|
| Super Admin pages | Stock pages **+ the SuperAdmin-only Bloomwire control page** (hosts the master toggle — always reachable as the **bootstrap surface**; sub-feature controls inert) | Bloomwire control page fully active (§5) |
| Account WhatsApp UI | Native chooser + manual/embedded forms fully visible (S-07 baseline) | Hidden/disabled for managed tenants (§6) |
| Create APIs (`/inboxes`, `/whatsapp/authorization`) | Native, unguarded | Guarded: tenant-initiated WhatsApp creation blocked; Ops path allowed (§6) |
| Inbound webhook | Per-number callback → `Webhooks::WhatsappController` (stock) | Meta → Bloomwire global webhook → router → `WhatsappEventsJob` (§9) |
| Routing registry | Not written/read | Written at onboarding; read by router (§8) |
| Secrets / logs / impersonation | Stock Chatwoot | Hardened (§11) |

**Invariant:** all toggles OFF ⇒ **tenant-facing / runtime** behavior equals `develop` (S-07-proven); toggles are
**purely additive**. The **only** OFF-state addition is the **SuperAdmin-only** Bloomwire control page (the master-toggle
bootstrap surface) — it has **zero tenant-facing or conversation-engine impact**, so it cannot, by itself, be gated
behind the toggle it sets.

---

## 5. Super Admin / Ops Architecture

**Recommendation — separate page (Option B).** Create a Bloomwire-owned **"Bloomwire / Unecast Features"** super-admin
page (new route + controller, additive). **The page itself is always reachable to SuperAdmins** — it hosts the master
toggle, so it is the **bootstrap control surface** and must **not** be gated behind the very toggle it sets. The master
toggle gates all **managed behavior + sub-feature controls**, not the page's existence; the page is **SuperAdmin-auth-only**
(`/super_admin`) with **no tenant-facing impact**, so *OFF = stock* still holds for tenants. Keep the stock WhatsApp-Embedded page
**unmodified** except the single privacy fix (App Secret masking) applied under the privacy toggle (§11), so OFF stays
stock. This best satisfies *OFF = unchanged Chatwoot* and *wrap-not-replace*, minimizes upgrade conflicts, and makes
rollback trivial (gate/remove one page). The Super Admin Console is a **separate** `/super_admin` auth boundary — a
tenant workspace session does **not** grant it. [RUNTIME-PROVEN, S-07]

| Setting / action | Type | Notes |
|---|---|---|
| Enable Bloomwire mode | toggle | Master (`BLOOMWIRE_MODE_ENABLED`); **reachable even when OFF** — this is the bootstrap control, so the page renders it regardless of master state |
| Enable managed onboarding / global router / restrict native setup / privacy hardening | toggles | Sub-features. **Managed onboarding + global router require Privacy hardening ON** — the page refuses to enable them otherwise (offers the bundle); see §4.1 |
| Global webhook callback URL | read-only | The single Bloomwire ingress URL (from configured host) |
| Webhook verify token | **masked** field | Meta GET-verify handshake; mask + reveal-on-demand; rotate action |
| Webhook status | read-only | `not_configured / verified / receiving / error` (driven by registry control state) |
| Last webhook received | read-only | Driven by `last_webhook_at` (§8) |
| Copy webhook URL / Regenerate verify token / Test webhook | actions | Test sends a synthetic ping only (no tenant data) |
| App Secret handling | behavior | Rendered `type="password"`; never echoed back in cleartext (§11) |
| Managed onboarding controls | section | Ops view of onboarding records + status transitions (§7) |

*Live correctness of webhook URL/verify/test against Meta is a production **[BLOCKER]** (needs real Meta) — the page
design itself is build-ready.*

---

## 6. Customer Account Workspace Behavior

### 6.1 By mode
- **OFF:** native account-level WhatsApp setup remains **visible and unchanged** — provider chooser + `CloudWhatsapp.vue`
  manual form + `WhatsappEmbeddedSignup.vue` → native endpoints (S-07 baseline; must not regress).
- **ON (managed tenant):** customer-facing **technical WhatsApp setup is hidden/disabled**. Customers never see or
  submit Meta App / webhook / Phone Number ID / Business Account ID / API key.

### 6.2 UI hiding is necessary but **not sufficient** — guard the APIs too

| Layer | Insertion point | ON behavior |
|---|---|---|
| UI | `dashboard/settings/inbox/channels/Whatsapp.vue`, `CloudWhatsapp.vue`, `WhatsappEmbeddedSignup.vue`, `360DialogWhatsapp.vue`, route `settings/inboxes/new/whatsapp` | Hide/disable WhatsApp tiles + forms for managed tenants (driven by a **read-only, non-secret DTO flag**) |
| API — manual create | `Api::V1::Accounts::InboxesController#create` / `create_channel` (`inboxes_controller.rb:33-46,93-101`) | Reject `channel.type == 'whatsapp'` for tenant (non-Ops) callers |
| API — embedded signup | `Api::V1::Accounts::Whatsapp::AuthorizationsController#create` (`authorizations_controller.rb:7-24`) | Reject tenant-initiated embedded signup |

**Mechanism:** a small `before_action` guard concern (e.g. `Bloomwire::GuardNativeWhatsappSetup`) included into those
two controllers, consulting `Bloomwire::Features` + the account's `managed` flag, returning `403` for tenant callers
when restriction is ON. Additive and removable.

### 6.3 Ops exemption path
When restriction is ON, **Bloomwire Ops** must still create/link `Channel::Whatsapp` + `Inbox` for the customer.
Provide an **Ops-only path** (super-admin/ops-scoped endpoint or service) that reuses the existing
`Whatsapp::ChannelCreationService` / inbox creation internally and is **exempt** from the tenant guard. The guard
distinguishes **Ops context** vs **tenant context**, not merely "is WhatsApp". [ASSUMPTION on exact Ops auth surface
— §17]

---

## 7. Managed WhatsApp Onboarding Flow

### 7.1 Responsibilities

| Customer (business owner) | Bloomwire Ops |
|---|---|
| Registers in Bloomwire | Verifies business details |
| Provides business details | Creates/links Chatwoot `Account` |
| Provides WhatsApp Business number | Creates owner `User` + `AccountUser` (administrator) |
| Provides OTP / approval **only if Meta requires it** | Performs WhatsApp onboarding (Ops-side embedded signup or manual) |
| | Creates `Channel::Whatsapp` + `Inbox` (reusing native services) |
| | Writes routing metadata to the registry (§8) |
| | Activates dashboard access for the owner |

The customer **never** configures Meta App, webhook, Phone Number ID, Business Account ID, or API key.

**Activation invariant.** Ops may flip an account to `active` (owner dashboard enabled, §7.1) **only when native-setup
restriction is in force for that account** (`BLOOMWIRE_RESTRICT_NATIVE_WHATSAPP_SETUP` ON — §4.1, Phase 5). Otherwise the
just-onboarded owner could open **Settings → Inboxes** and self-add an **unmanaged** WhatsApp channel with their own Meta
credentials — exactly what this managed model forbids. The restriction guard therefore lands **before** (or with) the
first activation, never after.

### 7.2 Status state machine (`onboarding_status` on the registry, §8)

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
| `waiting_for_customer_otp_or_approval` | Blocked on customer OTP / Meta approval | Ops (awaiting customer) |
| `active` | Channel + Inbox live, routing registered, dashboard enabled — **only when native-setup restriction is in force for the account** (activation invariant above) | Ops / system on success |
| `failed` | Onboarding failed; needs retry | System / Ops |

*OTP / Meta-approval capture mechanics in an Ops-run flow are an Open Q (§17) and partly a production **[BLOCKER]**
(real Meta).* 

## 8. Routing Registry Architecture

An **additive** Bloomwire routing/control table. Suggested name: **`bloomwire_channel_integrations`** (consistent with
prior art). It is a **routing + control-plane index** (fast `phone_number_id` lookup + onboarding/health state),
**not** a content store. **No migration is created in this plan** (constraint) — this is the target schema for a later,
gated implementation.

### 8.1 Fields

| Field | Purpose |
|---|---|
| `id`, `created_at`, `updated_at` | Standard |
| `account_id` | Owning Chatwoot account (FK, indexed) |
| `inbox_id` | Linked Chatwoot inbox (FK) |
| `channel_id` | Linked `Channel::Whatsapp` id |
| `channel_type` | Channel class — **future-proof** for IG/Messenger/SMS (D-06) |
| `provider` | e.g. `whatsapp_cloud` |
| `waba_id` / `business_account_id` | WhatsApp Business Account id (non-secret) |
| `phone_number_id` | **Router key** — **unique index** for `phone_number_id → account/inbox` resolution |
| `display_phone_number` | Human-readable number (non-secret) |
| `onboarding_status` | §7 state machine |
| `connection_status` | Live health (`connected / degraded / disconnected`) |
| `last_webhook_at` | Drives "Last webhook received" (§5) |
| `managed` | Marks the account/integration Bloomwire-managed (drives §6 restriction) |

### 8.2 Uniqueness + hard rules
- **`phone_number_id` unique index** is the registry's routing key. Native ingress resolves by `phone_number` (display)
  and then **validates** `provider_config['phone_number_id']` (`whatsapp_events_job.rb:155-161`, S-02 [RUNTIME-PROVEN]);
  `phone_number` is already globally unique (`channel/whatsapp.rb:17`, S-01). The registry's unique `phone_number_id`
  index is therefore an **additive** key for registry-first resolution **with native fallback** — it does not change
  native ingress, which keeps working with the registry absent or the router toggle OFF.
- **Non-secret policy:** secrets (`api_key`, verify token) **stay** in `Channel::Whatsapp#provider_config`; the
  registry stores **non-secret routing identifiers + status only**. (S-05/S-06 reinforce: never duplicate secrets.)
- **No duplication** of conversations, messages, or contacts — Chatwoot remains source of truth (D-07). The registry
  never holds message bodies.
- **Future channel-generic:** `channel_type` lets the same registry serve IG/Messenger/SMS later without a redesign;
  WhatsApp is the first and only populated type now (D-05).

---

## 9. Global Webhook Front-Door Architecture

### 9.1 Target flow (all steps S-03 [RUNTIME-PROVEN] except the live Meta handshake)
```
Meta → Bloomwire ONE global webhook endpoint
     → GET hub.challenge: validated by a Bloomwire-owned GLOBAL verify token (see §9.2 code gap)
     → POST: verify signature "sha256=" + HMAC-SHA256(WHATSAPP_APP_SECRET, raw_body) via ActiveSupport::SecurityUtils.secure_compare
     → forward the UNMODIFIED payload into Webhooks::WhatsappEventsJob  (existing pipeline)
     → the job natively resolves the channel from payload metadata
       (display_phone_number + validates phone_number_id, whatsapp_events_job.rb:155-161) — proven S-02/S-03
     → message persisted in the correct inbox
```

### 9.2 Behavior contract
- **One global endpoint, one app secret.** The verify expression is exactly the production concern
  `meta_token_verify_concern.rb:28-38`; the single secret is the existing global `WHATSAPP_APP_SECRET`
  (`whatsapp_controller.rb:25-30`). [RUNTIME-PROVEN via faithful replica, S-03]
- **Metadata-based routing, URL-independent.** `whatsapp_events_job.rb:146-161` resolves by payload metadata; no
  per-phone-number URL path is required. [RUNTIME-PROVEN, S-02/S-03]
- **Idempotency built-in.** Duplicate/re-delivered callbacks (same `wamid`) do **not** create duplicates —
  `incoming_message_base_service.rb:36` (`find_message_by_source_id`) + Redis `MessageDedupLock` (SET NX). [RUNTIME-PROVEN, S-03]
- **Fail-closed on both axes.** Invalid/malformed signature → rejected before forwarding; verified payload with unknown
  `phone_number_id` → forwarded but produces **no** message. [RUNTIME-PROVEN, S-03]
- **Callback indirection insertion point:** `Whatsapp::WebhookSetupService#setup_webhook` (`webhook_setup_service.rb:58-62`)
  registers **both** the callback URL (`build_callback_url`, `:75-80`) **and** the `verify_token` with Meta. When the
  router toggle is ON the overlay must rewrite **both together** — the global URL **and** the global verify token (next
  bullet) — not just the URL.
- **Registry is control-plane, not the hot-path router (Phases 1–6).** The front-door only **verifies + forwards the
  unmodified payload**; the unmodified `WhatsappEventsJob` resolves the channel from payload metadata
  (`whatsapp_events_job.rb:155-161`) — exactly what S-02/S-03 proved **without** any registry. The routing registry (§8)
  is populated for **ownership / status / onboarding**, and is **not** consulted on the ingress hot path in these phases.
- **[CODE GAP] Registry-FIRST routing is NOT free with an unmodified job.** If a later phase wants the front-door to
  resolve `phone_number_id → channel` via the registry and have the pipeline honor it (e.g. a managed number whose
  `display_phone_number` normalization diverges, or to override native lookup), the resolved channel must be **explicitly
  carried into processing** — the stock `perform` re-runs `find_channel_from_whatsapp_business_payload` and **discards**
  anything resolved in the controller. Carry it via a **job overlay** (`prepend_mod_with`, already used at
  `whatsapp_events_job.rb:164`), an explicit channel-handoff arg, or safe payload normalization — never by assuming the
  stock job reads the front-door's resolution. (Tracked as Phase 7.)
- **[CODE GAP] Global verify token — the inbound check AND the outbound registration must match.** Two halves, both required:
  - *Inbound check:* the stock GET verifier cannot validate a global URL — native `Webhooks::WhatsappController#valid_token?`
    (`whatsapp_controller.rb:19-23`) looks up `Channel::Whatsapp` by `params[:phone_number]` and compares that channel's
    per-channel `provider_config['webhook_verify_token']` (`channel/whatsapp.rb:124-126`). A global callback has **no**
    `:phone_number` param → `channel` is nil → `valid_token?` falsy → Meta's `hub.challenge` **401s**. Add a
    **Bloomwire-owned global verify-token store + check** (single `BLOOMWIRE_WHATSAPP_GLOBAL_VERIFY_TOKEN` in
    `InstallationConfig`/ENV, compared in the global GET action).
  - *Outbound registration:* `setup_webhook` (`webhook_setup_service.rb:58-62`) currently registers the **per-channel**
    `provider_config['webhook_verify_token']` as Meta's `verify_token`. With the router ON, Meta would then call the global
    URL with the **per-channel** token while the global action expects the **global** one → every registration/re-point
    **fails the handshake**. The setup/override overlay must register the **same global token** it validates.
  Both halves are a **design requirement**, independent of live Meta.
- **[BLOCKER — needs real Meta]:** the live Meta GET `hub.challenge` handshake and a real signed Meta callback can only be
  proven in production/staging (the global verify-token + signature logic itself is S-03-proven via a faithful
  always-verify replica).

---

## 10. Outgoing / Status Reconciliation Architecture

| Concern | Design | Proof |
|---|---|---|
| Native outgoing path | `MessageBuilder` → outgoing `Message` → `SendReplyJob` → `Whatsapp::SendOnWhatsappService` (`send_on_whatsapp_service.rb:31-43`) | [CODE-PROVEN] |
| **Meta send seam** | `Whatsapp::Providers::WhatsappCloudService#send_message` (`HTTParty.post` → `graph.facebook.com`) — the **only** outbound Meta call; the natural seam for a Bloomwire managed-send wrapper (outgoing-gateway toggle) | [CODE-PROVEN] |
| `source_id`/`wamid` storage | `message.update!(source_id: message_id)` after send (`:37,42`); reconciliation keys off `message.source_id` | [RUNTIME-PROVEN, S-04] |
| Status reconciliation | status webhook → `WhatsappEventsJob` → `process_statuses` finds message by `source_id` → `sent→delivered→read→failed` (+ `external_error`) (`incoming_message_base_service.rb:49-66`) | [RUNTIME-PROVEN, S-04] |
| Wrong `source_id` | `find_message_by_source_id` returns nil → `return` → **fails closed** (no update) | [RUNTIME-PROVEN, S-04] |
| **Still blocked** | The actual outbound **send** (real `WhatsappCloudService#send_message` HTTP POST) | **[BLOCKER]** real Meta creds |

**Key implication:** Bloomwire does **not** need to change Chatwoot's outbound pipeline or status reconciliation. The
managed-send wrapper attaches at the single Meta seam, behind the (later) `BLOOMWIRE_OUTGOING_GATEWAY` toggle, without
touching reconciliation logic. Feature-OFF = native send.

---

## 11. Privacy / Security Architecture

Activated by `BLOOMWIRE_PRIVACY_HARDENING` (OFF preserves stock unless a control is deemed a universal safe fix — Open
Q §17). Every gap below is **proven**.

| Gap (proven) | Hardening | Mandatory before prod? |
|---|---|---|
| App Secret rendered cleartext (`type=text`) — [RUNTIME-PROVEN, S-07] | Render secret inputs `type=password`; never echo stored secret in cleartext | **Yes** |
| Inbox DTO exposes raw `provider_config` (`api_key`, ids) to admins — `_inbox.json.jbuilder:130-138` [CODE/RUNTIME-PROVEN, S-06] | Scrub `provider_config` from tenant-facing inbox serialization (managed tenants get a non-secret DTO) | **Yes** |
| **Tenant Meta secrets at rest in plaintext jsonb** — `Channel::Whatsapp#provider_config` holds `api_key` (`whatsapp_cloud_service.rb:62`) + `webhook_verify_token` (`channel/whatsapp.rb:124-126`) unencrypted, exposed via DB reads/replicas/backups **even after** UI masking + DTO/log scrubbing [CODE-PROVEN] | **Decide before real managed data:** encrypt `provider_config` secrets at rest (`encrypts` / external custody) **or** formally accept + document the risk | **Yes — decision gate** |
| **CE audit inert**: `ChatwootApp.enterprise?` falsy → `Enterprise::Audit::*` not mixed in → **0** audit rows even for an audited write; `audit_logs` premium off — [RUNTIME-PROVEN, S-05] | Build a **Bloomwire-owned support-access audit** (CE-safe, independent of enterprise `audit_logs`) | **Yes** |
| SuperAdmin **self-add** as `AccountUser` (`super_admin/account_users_controller.rb:12-18`) [RUNTIME-PROVEN, S-05] | Restrict and/or audit self-add into accounts | **Yes** |
| SuperAdmin **impersonation** unaudited (`sso_authenticatable.rb:27-31`; only FE `sessionStorage` flag) [RUNTIME-PROVEN, S-05] | Gate/restrict impersonation; **audit every impersonation start/stop + cross-tenant access** | **Yes** |
| Tokens in explicit logs (`callbacks_controller.rb:25-30`; `base_service.rb:44-45`) [CODE-PROVEN] | Scrub tokens + provider error bodies from those log statements | **Yes** |
| **Message bodies not scrubbed** by `ParameterFilter` (`content`/`body`/`text.body` cleartext) [RUNTIME-PROVEN, S-06] | Add message-body scrubbing for logs | **Yes** |
| **Whole inbound payload in Sidekiq job args** → message body in plaintext (`whatsapp_controller.rb:13`) [RUNTIME-PROVEN, S-06] | **Non-mutating redaction only** — the stock `WhatsappEventsJob` reads the body from the payload via `IncomingMessageServiceHelpers#message_content` to set `Message#content`, so **deleting `text.body` from the enqueued args would break message creation**. Redact at the **log/display layer** (custom Sidekiq log redactor → worker still receives the full payload), **encrypt** job args at rest (decrypted in-worker), or hand off an **out-of-band encrypted payload + minimal reference** — never drop the body the worker consumes | **Yes** |

**Note:** `ParameterFilter` already redacts token/secret/`*_key` params for Rails request-param logging — but **not**
explicit logger calls, Sidekiq job args, or API DTOs; those are the gaps above. Every control above is **mandatory**
before a managed tenant carries real customer data in production; the **secret-at-rest** row is specifically a **blocking
decision gate** — encrypt, or formally accept and document the risk.

---

## 12. Implementation Phases

Each phase is a thin, independently-reviewable slice. **Default state of every new toggle is OFF**, so each phase ships
**dark** and is provable against the feature-OFF baseline before activation.

### Phase 0 — Final approval + cleanup
- **Objective:** Lock scope; confirm `develop` == stock baseline; clean git; `.env` untracked/uncommitted.
- **Areas:** docs only.
- **Tests:** none (verification gate).
- **Runtime validation:** confirm OFF baseline snapshot (S-07); `git status` clean; `.env` not staged.
- **Rollback:** n/a.
- **Feature-OFF regression:** capture the OFF baseline as the binding contract.

### Phase 1 — Feature-toggle foundation
- **Objective:** `Bloomwire::Features` central service + `InstallationConfig` keys + master AND-gate. No behavior change (all OFF).
- **Areas:** `app/lib/bloomwire/features.rb` (new); new **SuperAdmin-only** Bloomwire page (route/controller/view) — **reachable regardless of master state** (it hosts the master toggle = bootstrap surface); reuse `GlobalConfigService`.
- **Tests:** unit specs (master AND-gate forces sub-OFF; defaults OFF); request specs (page **reachable to SuperAdmin with master OFF** = bootstrap; **forbidden to non-SuperAdmin**; sub-feature controls inert until master ON; **tenant-facing** OFF parity with `develop`).
- **Runtime validation:** toggles OFF → zero **tenant-facing** behavior change; control page reachable to a SuperAdmin with master OFF (sub-controls inert); not shown to non-SuperAdmin.
- **Rollback:** remove service/page (additive).
- **Feature-OFF regression:** **tenant-facing / runtime** behavior is byte-for-byte `develop` (S-07 baseline); the **only** additive surface is the **SuperAdmin-only** Bloomwire bootstrap page (zero tenant-facing impact), which is **excluded** from the parity contract.

### Phase 2 — Privacy / security foundation
- **Objective:** App-Secret masking, `provider_config` DTO scrub, log scrubbing, **non-mutating Sidekiq/job hardening**, Bloomwire support-access audit, self-add/impersonation controls — behind `BLOOMWIRE_PRIVACY_HARDENING`.
- **Areas:** super-admin app-config view (mask); `_inbox.json.jbuilder` (scrub under flag); `callbacks_controller`/`base_service` (log scrub); `Webhooks::WhatsappController` / Sidekiq handoff (**non-mutating Sidekiq log/display redaction or encrypted payload handoff**, not job-arg minimization); `sso_authenticatable` + `account_users_controller` (overlay); new Bloomwire audit model/service.
- **Sidekiq invariant:** match §11 exactly — do **not** remove, blank, or rewrite `text.body`, message body, or any fields consumed by `WhatsappEventsJob`. The stock worker needs the payload body via `IncomingMessageServiceHelpers#message_content` to create `Message#content`. Acceptable approaches are: (1) Sidekiq log/display redaction while the worker still receives the full payload; (2) encrypted job args at rest, decrypted in-worker; or (3) out-of-band encrypted payload + minimal reference handoff.
- **Tests:** security specs — DTO has no `provider_config` when ON; logs/job display redacted or payload encrypted without mutating worker input; inbound text webhook still creates `Message#content` from the payload body; audit row on impersonation/support access; self-add blocked/audited; **OFF leaves stock**.
- **Runtime validation:** ON → secret masked, DTO scrubbed, audit rows written, inbound text message creation still works; OFF → stock.
- **Rollback:** toggle OFF.
- **Feature-OFF regression:** OFF → DTO/logs/secret exactly as `develop`.

### Phase 3 — Managed onboarding data model
- **Objective:** `bloomwire_channel_integrations` table + model (non-secret routing + status).
- **Areas:** migration (created **in implementation**, not now); `app/models/bloomwire/channel_integration.rb`; factory.
- **Tests:** model specs — validations, **`phone_number_id` unique index**, **no secret columns**, `managed` flag, status enum.
- **Runtime validation:** create/read registry rows; confirm **no** duplication of core data.
- **Rollback:** table is read-only to the engine; ignored in OFF.
- **Feature-OFF regression:** conversation engine never reads the registry.

### Phase 4 — Ops UI
- **Objective:** Super-admin managed-onboarding controls + status transitions + **Ops-only** channel/inbox creation.
- **Prereq (two gates):** (1) **Privacy hardening** (`BLOOMWIRE_PRIVACY_HARDENING` ON, Phase 2) — managed onboarding is **fail-closed** without it (§4.1), since a managed channel carries real Meta secrets + customer data; (2) **native-setup restriction landed first** — Ops may flip an account to `active`/owner-dashboard only when `BLOOMWIRE_RESTRICT_NATIVE_WHATSAPP_SETUP` is in force for it (the §7 activation invariant), else the just-onboarded tenant could self-add **unmanaged** WhatsApp via the stock UI/API. **Order:** land **Phase 5 before any Phase 4 activation** (or ship the guard together with activation).
- **Areas:** super-admin Bloomwire controllers/views; Ops service reusing `Whatsapp::ChannelCreationService`.
- **Tests:** request specs — Ops can create + transition status; **tenant cannot** reach the Ops path.
- **Runtime validation:** Ops creates channel/inbox; registry written; status → `active` (reuses S-01 mechanics).
- **Rollback:** toggle OFF / remove page.
- **Feature-OFF regression:** no Ops page when OFF.

### Phase 5 — Restrict native customer WhatsApp setup
- **Objective:** Hide UI + guard APIs for managed tenants (DTO flag + `Bloomwire::GuardNativeWhatsappSetup`). **Activation prerequisite:** this guard must be in force for an account **before** Phase 4 flips it to `active` (§7 activation invariant) — so although numbered Phase 5, it lands **before/with** the first managed activation.
- **Areas:** Vue channel components + route; `inboxes_controller`; `authorizations_controller`; guard concern; read-only DTO flag.
- **Tests:** request specs — tenant create WhatsApp → **403** when ON+managed; allowed when OFF; **Ops exempt**; vitest UI hiding.
- **Runtime validation:** managed tenant sees no WhatsApp tiles + API 403; non-managed unaffected.
- **Rollback:** toggle OFF.
- **Feature-OFF regression:** OFF → native UI + APIs unguarded (S-07 baseline).

### Phase 6 — Global webhook router
- **Objective:** Bloomwire global ingress (verify one app secret → forward `WhatsappEventsJob`) + callback indirection (URL **and** verify token).
- **Prereq:** Phase 2 privacy hardening (`BLOOMWIRE_PRIVACY_HARDENING` ON) — the router is **fail-closed** without it (§4.1), since inbound payloads carry customer message bodies through logs/job args.
- **Areas:** new `Webhooks::Bloomwire*` controller + route; global GET verify-token action; overlay on `webhook_setup_service#setup_webhook` that rewrites **both** `build_callback_url` **and** the registered `verify_token`; re-registration task for existing managed WABAs.
- **Tests:** request specs with **fake secret + signed body** — valid→forward; invalid/malformed→401; unknown pnid→no message; duplicate→idempotent; GET `hub.challenge` with the global token→200, wrong token→403. **No real Meta.**
- **Runtime validation:** replicate S-03 (signed sample → 1 message; dup → 1; bad sig → reject).
- **Enablement [BLOCKER — needs real Meta]:** flipping `BLOOMWIRE_GLOBAL_WEBHOOK_ROUTER` ON does **not** re-point WABAs already registered in earlier phases — Meta keeps the prior per-number `override_callback_uri` and keeps posting to `/webhooks/whatsapp/:phone_number`, bypassing the front-door until each managed channel is **re-registered** (`register_callback`/`setup_webhook` with the global URL + global token). Ship an explicit re-registration runbook, not just a toggle.
- **Rollback:** toggle OFF → per-number registration. **CAVEAT [BLOCKER]:** if Meta callbacks were re-pointed to the global URL, full rollback needs a **Meta-side re-point** (documented runbook step).
- **Feature-OFF regression:** OFF → stock per-number `Webhooks::WhatsappController`.

### Phase 7 — Routing registry integration
- **Objective:** Router resolves via registry first, fallback to `Channel::Whatsapp` payload lookup; registry written at onboarding.
- **Areas:** router resolution; registry read/write.
- **Tests:** specs — pnid → registry → account/inbox; fallback path; **no cross-leak** (reuses S-02 assertions).
- **Runtime validation:** route two pnids through the registry to the correct inboxes.
- **Rollback:** toggle OFF → fallback to payload resolution (engine unaffected).
- **Feature-OFF regression:** registry ignored.

### Phase 8 — Outgoing gateway / status support
- **Objective:** Bloomwire managed-send wrapper at the Meta seam (status reconciliation is already native); tenant outbound client API deferred.
- **Areas:** send-seam overlay; gateway service (later); reuse native status path.
- **Tests:** job specs — status reconcile by `source_id`; wrong id fail-closed (reuses S-04). **Send stubbed; no real Meta.**
- **Runtime validation:** inject outbound + status `sent→delivered→read`; wrong id unchanged.
- **Rollback:** toggle OFF → native send.
- **Feature-OFF regression:** native outgoing unchanged.
- **[BLOCKER]:** real outbound send needs Meta creds (validated in Phase 9).

### Phase 9 — Production readiness + Meta live validation
- **Objective:** Validate all live Meta-dependent steps with real/sandbox creds; enable audit; confirm scrubbing; run backup/rollback drills.
- **Areas:** config, ops runbooks (no new product logic).
- **Tests:** live smoke in **staging only** (not CI) — real verify handshake; real send; media/attachment path.
- **Runtime validation:** real Meta callback verified; real send delivered + reconciled; media downloaded.
- **Rollback:** documented Meta re-point + toggles OFF.
- **Feature-OFF regression:** final OFF snapshot == `develop`.
- **[BLOCKER]:** this phase **requires real credentials**.

**What must NOT be built yet:** tenant outbound **client API** (keys/rate-limits/idempotency/outbound webhooks);
**future channels** (IG/Messenger/SMS/email); **billing/pricing**; visual **flow-builder** automation; **bulk-campaign**
per-recipient queue; **calling** (enterprise-licensed). All deferred behind later toggles or out of scope.

## 13. TDD / Validation Strategy

Tests protect the **business contract**, not the current implementation, and **fail-first** where practical. **No real
Meta calls in automated tests** — WebMock blocks `graph.facebook.com`; webhook specs use a **fake app secret + locally
signed body**; the `:channel_whatsapp` factory must pass `validate_provider_config: false` **and**
`sync_templates: false` to avoid a real Graph call on create.

| Layer | What it asserts | Example |
|---|---|---|
| **Unit specs** | `Bloomwire::Features` master AND-gate; defaults OFF; **privacy-hardening prerequisite** | master OFF ⇒ every sub-feature `enabled?` false; **managed onboarding/router `enabled?` false unless privacy hardening ON** |
| **Model specs** | registry validations; **`phone_number_id` unique index**; **no secret columns**; `managed` flag | duplicate pnid rejected |
| **Request specs** | super-admin page **reachable to SuperAdmin (master-OFF bootstrap) + forbidden to non-SuperAdmin**; native-setup guard (`403` tenant / allow Ops / allow OFF); global webhook verify→forward & fail-closed | invalid signature ⇒ `401`, no message |
| **Job specs** | `WhatsappEventsJob` routing + idempotency + status reconcile by `source_id` | duplicate `wamid` ⇒ no second message |
| **Security specs** | DTO has no `provider_config` when ON; logs/job display redacted or payload encrypted without mutating `WhatsappEventsJob` input; inbound text still creates `Message#content`; audit row on impersonation/support access; self-add restricted | managed inbox DTO omits `api_key` |
| **Feature-OFF regression specs** | each toggle OFF ⇒ stock behavior (the binding S-07 contract) | OFF ⇒ native WhatsApp UI + unguarded APIs + raw DTO |
| **Runtime smoke** | Chrome MCP for UI hiding; Rails runner for routing/status (the S-01…S-04 method) | managed tenant sees no WhatsApp tiles |

**Red-green-refactor:** write the failing spec first for net-new Bloomwire behavior. For behavior that is **already
native** (routing, idempotency, status reconcile), the spike runtime proofs (S-01…S-04) are the evidence and the specs
**lock** it against regression.

---

## 14. Rollback Strategy

- **Primary rollback = toggles OFF.** The master toggle forces every sub-feature off; the app reverts to the S-07 stock
  baseline.
- **Native Chatwoot fallback:** records created under managed mode (`Channel::Whatsapp`, `Inbox`, `Message`,
  `Contact`) are **native Chatwoot records** and keep working with toggles OFF.
- **Routing registry ignored in OFF mode:** the conversation engine never reads it; OFF makes it inert (no drop
  required).
- **Data rollback expectations:** early phases add **only** an additive table (no destructive migration); rolling back
  code leaves native data intact. The registry can be dropped later if truly abandoned.
- **Global webhook re-point caveat [BLOCKER]:** Meta's callback URL + verify token are **registration state on Meta's
  side**, not a code toggle, so re-pointing is required in **both** directions — **enabling** the router means
  re-registering existing managed WABAs to the global URL + global token (§Phase 6 Enablement), and **rolling back** means
  re-pointing them back to per-number ingress. Ship a documented re-point/re-register runbook covering both.

---

## 15. Production Readiness Checklist

| Item | Status |
|---|---|
| Real Meta webhook verification (`hub.challenge` GET handshake) | **[BLOCKER]** — needs real Meta (Phase 9) |
| Real / sandbox outbound send (`WhatsappCloudService#send_message`) | **[BLOCKER]** — needs real Meta (Phase 9) |
| Media / attachment inbound path (Graph media download) | **[BLOCKER]** — needs real Meta (Phase 9) |
| Secret storage | App Secret masked + never echoed; `provider_config` scrubbed from DTOs; **`provider_config` secret-at-rest = blocking decision gate (encrypt or accept+document) before real managed data — §11, §17** |
| Bloomwire CE audit enabled | Required (enterprise audit is inert in CE — S-05) |
| Logs / job displays hardened | tokens, provider error bodies, **message bodies**, and Sidekiq job displays redacted **without mutating the payload consumed by `WhatsappEventsJob`**; encrypted job args / encrypted handoff acceptable (§11, S-06) |
| No `.env` commit risk | `.env` kept **untracked/uncommitted**; ensure it stays git-ignored; never echo secrets in any output |
| Backup / rollback drill | Validate toggles-OFF revert + documented Meta re-point |
| Support-access controls | impersonation gated/audited; self-add restricted (S-05) |

---

## 16. Explicit Non-Goals

- **Pricing / billing / plan limits** — out of scope this entire track.
- **Copying WhatsWay code** — concepts only, clean-room (D-09).
- **Duplicating messages / conversations / contacts** — Chatwoot stays source of truth.
- **Replacing Chatwoot** or forking the conversation engine.
- **Building future channels now** (IG / Messenger / SMS / email) — registry is future-proofed but not populated.
- **Tenant outbound client API, flow-builder automation, bulk-campaign queue, calling** — deferred / out of scope.
- **Implementing any code in this task** — this is architecture/documentation only.

---

## 17. Open Questions (unresolved only)

> P-01…P-05 and Q-01 (global-webhook ownership) are now **resolved** by the completed spikes and are no longer open.

- **Restriction scope** *(design)*: installation-wide vs per-account `managed` flag for "restrict native WhatsApp
  setup" — and can managed + self-serve accounts coexist on one install? (§4.2, §6)
- **Privacy-in-OFF** *(policy)*: should secret masking / DTO scrubbing be a **universal** safe fix, or strictly gated by
  the privacy toggle? (§11; register Q-04)
- **Secret-at-rest mechanics** *(security)*: the **decision** to encrypt `provider_config` secrets at rest (vs. formally
  accept the risk) is no longer optional — it is a **blocking gate** before real managed data (§11, §15). What remains
  open is the **mechanism**: `encrypts`-at-rest vs. external secret custody, plus key rotation and searchability
  trade-offs. (Q-04)
- **Impersonation policy** *(business)*: disable entirely, gate behind explicit tenant consent, or audit-only? (Q-03 —
  S-05 proved the gap; the *policy* is a business call)
- **Single Meta App operational strategy** *(ops)*: the router slice now **requires** a Bloomwire-owned global
  verify-token check (§9.2) plus the one global app secret (S-03); routing itself is proven (S-02/S-03). What remains a
  choice is **operational management** — token/secret custody, rotation, and whether one verify token spans all tenant
  WABAs. (Q-02)
- **OTP / Meta-approval mechanics** *(design + [BLOCKER])*: how a customer OTP / Meta approval is captured and relayed
  in an Ops-run managed flow, and the customer UX during `waiting_for_customer_otp_or_approval`. (§7)
- **Ops auth surface** *(design)*: exact shape of the Ops-only channel-creation path (super-admin endpoint vs internal
  service) and how the guard distinguishes Ops vs tenant context. (§6.3)
- **Outgoing gateway shape** *(business + design)*: reuse `Channel::Api`/Platform API vs a dedicated Bloomwire client
  API (keys/rate-limits/idempotency/outbound webhooks). (Q-05)
- **Provider strategy** *(design)*: `whatsapp_cloud` only vs also `default` (360dialog); routing keys as indexed
  columns vs `provider_config` jsonb. (Q-06)
- **Tenant hierarchy / owner role** *(business)*: is `administrator`/`agent` enough, or are a distinct **owner** role
  (Q-10) and/or an org/reseller-above-account (Q-09) needed later?

---

## 18. Recommended Next Step

**First implementation slice after approval: Phase 1 — feature-toggle foundation.** Build the `Bloomwire::Features`
central service (master AND-gate + `InstallationConfig`-backed keys, defaults OFF) and the **SuperAdmin-only** Bloomwire
control page (**reachable with master OFF** — the bootstrap surface that lets a SuperAdmin enable Bloomwire from the UI,
no out-of-band DB edits), shipped **dark** (every toggle OFF → zero **tenant-facing** behavior change), with unit specs for the AND-gate and **feature-OFF
regression specs** proving the app still equals the S-07 `develop` baseline.

It is the smallest, safest, zero-risk foundation every later phase depends on, needs **no** Meta credentials, and
establishes the single ON/OFF control surface before any behavior-changing slice. Immediately after, **Phase 2
(privacy/security foundation)** — those eight controls are **mandatory** before any managed tenant carries real data
and are likewise Meta-independent.

**Stop here — architecture/documentation only. No code, branches, migrations, PRs, toggles, commits, or pushes.**
