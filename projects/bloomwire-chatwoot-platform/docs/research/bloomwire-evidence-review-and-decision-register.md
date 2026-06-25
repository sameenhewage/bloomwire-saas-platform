# Bloomwire — Evidence Review + Decision Register

> **Status:** Review + decision register. **No** final architecture plan here.
> **Purpose:** Convert the Evidence Collection Report into clear **decisions**,
> **assumptions**, and **required runtime spikes** before the final architecture plan.
> **Source:** [`bloomwire-evidence-collection-report.md`](./bloomwire-evidence-collection-report.md)
> (sections A–H + cross-cutting). This document reviews that evidence; it adds **no** new code reading.
> **Scope note:** Pricing / billing / plan limits are **OUT OF SCOPE** for this pass (per request).
> **Constraints honored:** nothing implemented, branched, switched, migrated, or PR'd. No product code edited.
>
> **⚠️ Status update — spikes complete (this register is now pre-spike / superseded).** The runtime spikes
> **S-01 → S-07** in this folder are **DONE** (see the S-01…S-07 reports and the **final architecture plan §2 evidence
> table**). Consequently **P-01…P-05 below are resolved**: **P-01…P-04 confirmed** (P-04 live Meta *send* remains a
> production **[BLOCKER]**), and **P-05 confirmed as a real privacy risk** → addressed by the privacy-hardening
> workstream (plan §11). The §0 index, the §2 "needs proof" items, and the §3 spike list are retained **for history**;
> for current direction follow the architecture plan and **proceed to Phase 1** — do **not** re-run the spikes.

---

## How to read this document

- **§1 Confirmed decisions** — settled by the evidence; safe to build the plan on.
- **§2 Decisions that need more proof** — plausible from static code, but **not runtime-proven**; each is gated on a spike.
- **§3 Required runtime spikes** — the experiments that turn §2 items into confirmed decisions.
- **§4 Capability ownership table** — per area: *Chatwoot as-is / Light customization / Bloomwire custom module / Avoid for now*.
- **§5 Open questions** — what code **cannot** answer; needs a runtime spike or a business decision.
- **§6 Assumptions** and **§7 Out of scope / Next step**.

Evidence anchors use the report's section letters (§A–§H) and repo-relative paths (`app/...:line`).
Full citations live in the source report.

---

## 0. Decision register (index)

| ID | Item | Type | Status | Evidence | Next action |
|---|---|---|---|---|---|
| D-01 | Account = Bloomwire business tenant | Decision | **Confirmed** | §A | Build on it |
| D-02 | User + AccountUser = owner/staff | Decision | **Confirmed** | §A | Build on it; role nuance → Q-10 |
| D-03 | Channel is generic (not WhatsApp-only) | Decision | **Confirmed** | §B | Build on it |
| D-04 | One endpoint = one Channel = one Inbox | Decision | **Confirmed** | §B | Build on it |
| D-05 | WhatsApp is the first channel | Decision | **Confirmed** | §D | First vertical |
| D-06 | IG / Messenger / SMS / Email are future types | Decision | **Confirmed** | §B | Defer to later slices |
| D-07 | Owner owns inboxes/contacts/convos/campaigns/automations | Decision | **Confirmed** | §A, §C | Build on it |
| D-08 | Bloomwire owns provider / control-plane | Decision (boundary) | **Confirmed intent** | §D, §E, §F, §C | Mechanisms gated on S-02..S-06 |
| D-09 | WhatsWay = reference only, no code copy | Decision (hard rule) | **Confirmed** | §G | Concepts only |
| P-01 | Multiple WA inboxes per account at runtime | Needs proof | **Confirmed** (S-01 ✅) | §A, §D | Build per plan |
| P-02 | One Bloomwire Meta App → many WABAs safely | Needs proof | **Confirmed** (S-02 ✅) | §E | Build (router, plan §6) |
| P-03 | Bloomwire-owned global webhook → Chatwoot safely | Needs proof | **Confirmed** (S-03 ✅) | §D, §E | Build (router, plan §6) |
| P-04 | Outgoing injection via Bloomwire API preserves history | Needs proof | **Confirmed** (S-04 ✅; live *send* = [BLOCKER]) | §F | Deferred gateway |
| P-05 | Platform admins prevented from reading tenant content | Needs proof | **Confirmed risk** (S-05/S-06) | §C | Privacy workstream (plan §11) |

---

## 1. Confirmed decisions

Each is **proven by static code evidence** and safe to carry into the architecture plan.

### D-01 — A Chatwoot `Account` can represent a Bloomwire business tenant
- **Basis (§A):** `Account` owns the whole tenant graph — `has_many :inboxes` (`app/app/models/account.rb:83`), `:contacts` (`:71`), `:conversations` (`:72`), `:campaigns` (`:68`), `:automation_rules` (`:66`), plus per-channel collections incl. `whatsapp_channels` (`:100`). Membership + role isolation via `AccountUser` (`app/app/models/account_user.rb:27-58`) and a request-time membership check (`app/app/controllers/concerns/ensure_current_account_helper.rb:21-25`).
- **Constraint / note:** No "organization-above-account" / reseller parent exists in core (§A.4). The Bloomwire platform sits at the **super-admin / installation** layer, not as a parent tenant entity. `usage_limits` is only a hook (out of scope). → see **Q-09**.

### D-02 — `User` + `AccountUser` can represent owner / staff
- **Basis (§A):** `User` is STI (`app/app/models/user.rb:31`) with `has_many :accounts, through: :account_users` (`:88`). `AccountUser` carries `enum role: { agent: 0, administrator: 1 }` (`app/app/models/account_user.rb:34`) and `permissions` (`:56-58`); `(account_id,user_id)` is unique.
- **Constraint / note:** "Owner vs staff" maps onto `administrator` / `agent` today. A finer **owner** role is a later product decision → **Q-10**.

### D-03 — Channel must be generic, not WhatsApp-only
- **Basis (§B):** The `Channelable` concern is the native generic "connected endpoint" — every channel `belongs_to :account` and `has_one :inbox, as: :channel` (`app/app/models/concerns/channelable.rb:1-11`); `Inbox belongs_to :channel, polymorphic: true` (`app/app/models/inbox.rb:60`).
- **Constraint / note:** There is **no** separate provider/credential registry table above the per-type channel models (§B.4). A Bloomwire-level registry, if wanted, is **additive** (light), not required.

### D-04 — One connected endpoint = one Channel record = one Chatwoot Inbox
- **Basis (§B.3):** `Channelable.has_one :inbox` + per-type channel models give an exact 1:1 endpoint↔inbox mapping. This is precisely the product's intended abstraction.

### D-05 — WhatsApp is the first channel
- **Basis (§D):** The full WhatsApp Cloud lifecycle already exists end-to-end — embedded signup → `Channel::Whatsapp` + `Inbox` creation → token storage → inbound webhook → event→inbox mapping → outgoing send → delivered/read/failed status. First vertical because support is already deep.

### D-06 — Instagram / Messenger / SMS / Email are future channel types
- **Basis (§B):** Channel types already exist: `channel/instagram.rb`, `channel/facebook_page.rb` (Messenger), `channel/sms.rb`, `channel/twilio_sms.rb`, `channel/email.rb`. Adding a channel = add a `Channel::X` that includes `Channelable`.
- **Constraint / note:** Low-friction future expansion; **not** in the first slices.

### D-07 — Business owner owns inboxes, contacts, conversations, campaigns, automations
- **Basis (§A, §C):** Ownership is account-scoped (`account.rb:66,68,71,72,83`); access policies restrict reads to account members (`app/app/policies/conversation_policy.rb:1-44`; account base controllers in §C). Data stays inside the tenant.

### D-08 — Bloomwire owns provider / control-plane responsibilities
- **Basis (§D/§E/§F/§C):** The net-new work sits at the **edges** Chatwoot does not own per-tenant today: a Bloomwire-owned **global Meta webhook + router**, a **single Meta App → many WABAs** onboarding layer, a **tenant outgoing message gateway/API**, and **privacy hardening** (impersonation policy + secret/log scrubbing).
- **Constraint / note:** This is a **boundary decision**, not a built mechanism. The control-plane pieces are **not runtime-proven** → gated on **S-02..S-06**. Boundary: Bloomwire owns provider app config, global ingress, secret custody, onboarding; the tenant owns inbox content + support workflow (D-07).

### D-09 — WhatsWay is reference only; no code copy
- **Basis (§G):** WhatsWay is CodeCanyon/Envato **proprietary**; "WhatsWay code must **NOT** be copied — concepts only." Borrowable **concepts** (clean-room): global webhook routing by `phone_number_id`, single Meta-app config fronting many WABAs, client API keys + outbound webhooks, per-recipient campaign queue.
- **Constraint / note:** Hard rule. Concepts may validate edge design; any implementation must be original.

---

## 2. Decisions that need more proof

Each is **plausible from static code** but **not runtime-proven**. Each is gated on the named spike before it can move to "confirmed".

### P-01 — Can one account create multiple WhatsApp inboxes cleanly at runtime?
- **Already proven (static):** Model allows it — `channel_whatsapp` is unique only on `phone_number` (no `account_id` uniqueness), and `account.inboxes` is unbounded (§A.2, `app/app/models/channel/whatsapp.rb:16-17,32`).
- **Not proven:** End-to-end runtime — two embedded-signup runs under one account, no collision, both inboxes listed, inbound routed to the right inbox.
- **Resolved by:** **S-01**.  **Risk if wrong:** the core multi-number tenant promise breaks.

### P-02 — Can one Bloomwire Meta App support many customer WABAs safely?
- **Already proven (static):** Resolution chain `phone_number_id → Channel::Whatsapp → Inbox → Account` exists and is exercised by the events job (§E, `app/app/jobs/webhooks/whatsapp_events_job.rb:146-161`); signature path supports per-channel **and** a global app secret (`app/app/controllers/webhooks/whatsapp_controller.rb:25-42`).
- **Not proven:** A single Bloomwire app fronting **all** client WABAs with one app-secret/verify strategy, with strict tenant isolation.
- **Resolved by:** **S-02**.  **Risk if wrong:** cross-tenant misrouting / signature failures.

### P-03 — Can Bloomwire own one global webhook and forward to Chatwoot safely?
- **Already proven (static):** The events job already resolves the channel from **payload metadata**, independent of the URL `:phone_number` (§D.4, `whatsapp_events_job.rb:140-161`).
- **Not proven:** A Bloomwire-owned **global ingress** that receives one Meta callback, verifies signature with one app secret, and forwards into `WhatsappEventsJob` with **no** event loss/duplication. Today registration is **per-phone-number** (`app/app/services/whatsapp/webhook_setup_service.rb:58-80`).
- **Resolved by:** **S-03**.  **Risk if wrong:** dropped/duplicated events; signature bypass.

### P-04 — Can outgoing messages be injected via a Bloomwire API while preserving Chatwoot inbox history?
- **Already proven (static):** Injection via `messages_controller` / `Messages::MessageBuilder`; `SendReplyJob → Whatsapp::SendOnWhatsappService` stores `message.source_id = wamid`; a double-send guard skips messages that already have a `source_id`; status webhooks reconcile by `source_id` (§F).
- **Not proven:** A dedicated Bloomwire **gateway** path end-to-end (own auth, idempotency, rate limits, client webhooks) that preserves history and reconciles status at runtime.
- **Resolved by:** **S-04**.  **Risk if wrong:** lost history, duplicate sends, unreconciled status.

### P-05 — Can platform admins be prevented from freely reading tenant message content?
- **Already proven (static):** Default account-scoping; the super-admin UI has **no** conversation/message browser (§C.1–3).
- **Not proven / known gaps (§C.4):** super-admin **impersonation** bypasses the boundary (`app/app/models/concerns/sso_authenticatable.rb:27-31`, `app/app/views/super_admin/users/_impersonate.erb:5`); a super-admin can **self-add** as an `AccountUser`; tokens/message bodies can **leak to logs** (`app/app/controllers/api/v1/accounts/callbacks_controller.rb:25-29`, `app/app/services/whatsapp/providers/base_service.rb:44-45`, `app/config/initializers/filter_parameter_logging.rb:4-13`).
- **Resolved by:** **S-05** (impersonation/privacy audit) + **S-06** (token/log scrubbing).  **Risk if wrong:** privacy/compliance breach; loss of core SaaS trust.

---

## 3. Required runtime spikes

Spikes are **measurement experiments**, not features. They are throwaway and produce a documented result that flips a §2 item. (Embedded-signup token-storage verification from the source report is folded into **S-01** and **S-03**.)

### S-01 — Multiple WhatsApp inboxes under one account
- **Goal:** Prove one account can hold 2+ WhatsApp inboxes with correct creation, listing, and routing.
- **Method:** In dev, create two `Channel::Whatsapp` + inboxes under one account (embedded signup or seeded `provider_config`); send inbound to each `phone_number_id`.
- **Pass criteria:** Both inboxes created (no `phone_number` collision), both inbound messages land in the correct inbox, UI lists both.
- **Unblocks:** P-01.  **Anchor:** §A.2, §D.

### S-02 — Multi-WABA webhook routing
- **Goal:** Prove inbound events for two different `phone_number_id`s route to the correct account/inbox.
- **Method:** POST a sample `whatsapp_business_account` webhook for two distinct `phone_number_id`s.
- **Pass criteria:** Each lands in the correct account/inbox via `WhatsappEventsJob`; **no** cross-tenant leakage.
- **Unblocks:** P-02.  **Anchor:** §E, `whatsapp_events_job.rb:140-161`.

### S-03 — Global webhook front-door
- **Goal:** Prove a Bloomwire endpoint can receive **one** Meta callback and forward to Chatwoot's job using **one** app secret.
- **Method:** Stand up a throwaway global endpoint; verify signature handling across multiple channels; forward into `WhatsappEventsJob`.
- **Pass criteria:** Signature verified, event forwarded, message persisted, **no** loss/duplication.
- **Unblocks:** P-03.  **Anchor:** §D.4, §E.4, `whatsapp_controller.rb:25-42`.

### S-04 — Outgoing message injection
- **Goal:** Prove an API-injected outgoing message preserves inbox history and reconciles delivery status.
- **Method:** Create an outgoing message via API for a WhatsApp inbox; confirm `source_id` (`wamid`) is stored; simulate a delivered/read status webhook.
- **Pass criteria:** Message lives on the conversation/inbox, `source_id` stored, status reconciles, **no** duplicate send.
- **Unblocks:** P-04.  **Anchor:** §F.

### S-05 — SuperAdmin impersonation / privacy audit
- **Goal:** Measure exactly what a super-admin can see/do after impersonation, and what audit trail (if any) is produced.
- **Method:** Impersonate a tenant user; enumerate accessible conversations/messages; inspect audit logging.
- **Pass criteria (decision-grade):** A precise **capability + audit-gap inventory** (this spike informs policy; it does **not** implement a fix).
- **Unblocks:** P-05 + privacy policy **Q-03**.  **Anchor:** §C.4, `sso_authenticatable.rb:27-31`.

### S-06 — Token / log scrubbing check
- **Goal:** Confirm where secrets / message bodies leak into logs or Sidekiq job args, and whether current filtering covers them.
- **Method:** Trigger the Facebook callback debug log + the WhatsApp send error path; inspect logs + job args; review `filter_parameter_logging` coverage and how inbound payloads are enqueued.
- **Pass criteria (decision-grade):** A documented **leakage inventory + scrubbing requirements** (informs the fix; does **not** implement it).
- **Unblocks:** P-05 + secret-handling **Q-04**.  **Anchor:** §C.4, `callbacks_controller.rb:25-29`, `whatsapp/providers/base_service.rb:44-45`, `filter_parameter_logging.rb:4-13`.

---

## 4. Capability ownership table

Classification: **Chatwoot as-is** · **Light customization** · **Bloomwire custom module** · **Avoid for now**.

| # | Area | Classification | Basis (evidence) | Gated on |
|---|---|---|---|---|
| 1 | tenant / account | **Chatwoot as-is** | `Account`/`AccountUser` already multi-tenant (§A). | — |
| 2 | users / staff | **Chatwoot as-is** | Role + membership isolation (§A); minor role nuance later. | Q-10 |
| 3 | channel / inbox | **Chatwoot as-is** | Polymorphic inbox↔channel via `Channelable` is native (§B). Optional Bloomwire registry would be *light, additive*. | — |
| 4 | contacts | **Chatwoot as-is** | Account-scoped contacts (§A). | — |
| 5 | conversations / messages | **Chatwoot as-is** | Account/inbox scoped, `source_id` provider IDs, status reconcile (§F). | — |
| 6 | WhatsApp embedded signup | **Light customization** | Full flow exists (§D); needs Bloomwire Meta App config + callback indirection. | S-01, S-03 |
| 7 | global webhook | **Bloomwire custom module** | Per-number callback today; Bloomwire-owned global front door + router needed (§D/§E; WhatsWay concept §G). | S-03 |
| 8 | multiple WABAs | **Bloomwire custom module** | Resolution chain exists (§E, *reuse, light*); single app fronting all WABAs is custom. | S-02 |
| 9 | outgoing API | **Bloomwire custom module** | Internal send reusable (§F) but no tenant client API / webhooks / rate-limits. | S-04 |
| 10 | privacy | **Bloomwire custom module** | Impersonation + token/log leakage must be closed/audited (§C). | S-05, S-06 |
| 11 | campaigns | **Light customization** | `Campaign` exists per inbox (§B); per-recipient bulk-queue concept from WhatsWay (§G). | Q-08 |
| 12 | automation | **Light customization** | `automation_rules` exist; rules vs flow-builder is a product decision (§G). | Q-07 |
| 13 | tasks | **Avoid for now** | Not core to the first slices (§H). | — |
| 14 | calling | **Avoid for now** | WhatsApp/Twilio voice is Chatwoot **enterprise-licensed**; do not enable unlicensed (§H; prior ADR 0002). | — |
| 15 | billing / pricing | **Avoid for now** | Out of scope this pass (per request). | — |

---

## 5. Open questions (cannot be answered from code)

Each needs a **runtime spike**, a **business/product decision**, or both. Tag in brackets.

- **Q-01 — Global webhook ownership** *(Both)*: Does Bloomwire register its own Meta callback and forward into `WhatsappEventsJob`, or keep Chatwoot's per-number registration? (§D/§E, open q1) — **resolved by S-03**: Bloomwire owns one global webhook and forwards the unmodified payload into `WhatsappEventsJob` (final plan §9, §17). *(Listed here for history.)*
- **Q-02 — Single Bloomwire Meta App strategy** *(Both)*: One app secret + verify-token spanning all tenant WABAs vs per-channel secrets? (§E, `whatsapp_controller.rb:25-42`) — informed by **S-02/S-03**.
- **Q-03 — Platform-admin message access policy** *(Business / policy)*: Disable impersonation, gate it behind explicit tenant consent, and/or audit-log every impersonation + cross-tenant access? (§C.4) — informed by **S-05**.
- **Q-04 — Secret handling** *(Both)*: Encrypt `provider_config` secrets at rest **and** scrub tokens/message bodies from logs/job args? (§C.4) — informed by **S-06**.
- **Q-05 — Outgoing gateway shape** *(Business + design)*: Reuse `Channel::Api` + Platform API, or build a dedicated Bloomwire client API with keys / rate-limits / idempotency / outbound webhooks? (§F; WhatsWay concept §G).
- **Q-06 — Provider strategy** *(Business + design)*: `whatsapp_cloud` only, or also `default` (360dialog)? Routing keys as **indexed columns** vs `provider_config` **jsonb**? (§D).
- **Q-07 — Automation model** *(Product)*: Keep Chatwoot rule-based `automation_rules`, or build a WhatsWay-style visual flow-builder? (§G).
- **Q-08 — Campaign / bulk model** *(Product)*: Adopt a per-recipient queue concept (provider-id + status + cost columns) for bulk send? (§G).
- **Q-09 — Tenant hierarchy** *(Business)*: Is "Account = tenant" sufficient, or will an org/reseller parent be needed later? Core has none today (§A.4).
- **Q-10 — Owner vs staff role nuance** *(Business)*: Is `administrator`/`agent` enough, or is a distinct **owner** role required? (§A.4).

---

## 6. Assumptions (explicit, to be challenged)

- **A-01** — Chatwoot CE/OSS remains the **source of truth** for accounts, inboxes, contacts, conversations, messages, and support workflow; the conversation engine is reused **as-is** (§A, §B, §F; consistent with prior ADR 0002 boundary).
- **A-02** — Bloomwire adds value at the **edges** (provider / control-plane), not by forking the conversation engine (§ Initial observations).
- **A-03** — WhatsApp secrets stay in `Channel::Whatsapp#provider_config`; Bloomwire must **encrypt at rest** and **scrub from logs** (§C/§D/§G). *Design intent to confirm:* Bloomwire's control-plane **custodies** but does **not duplicate** secrets into Bloomwire-owned tables — validate during planning.
- **A-04** — Calling stays **disabled** (Chatwoot enterprise-licensed; §H, prior ADR 0002).
- **A-05** — Pricing/billing is intentionally **excluded** this pass.
- **A-06** — No reseller/organization-above-account is assumed; `Account` is the tenant boundary unless **Q-09** decides otherwise.

---

## 7. Out of scope (this document) / Next step

**Out of scope here:** the final architecture plan, any branches/PRs, migrations, product-code edits, and pricing/billing.

**Status (updated):** spikes **S-01 → S-07** are **complete** (reports in this folder) and the **final architecture plan**
exists (`bloomwire-final-feature-toggle-architecture-plan.md`). **P-01…P-05 are resolved** — P-01…P-04 confirmed (P-04
live *send* = production **[BLOCKER]**), P-05 confirmed as a real privacy risk (privacy-hardening workstream, plan §11).

**Recommended next step:** proceed to the architecture plan's **Phase 1** (feature-toggle foundation); do **not** re-run
the spikes. The spikes settled the **evidence** (S-05/S-06 confirmed the impersonation/audit + secret-at-rest gaps are
real) — they did **not** settle the **policy/mechanism decisions**, which stay **OPEN gates before Phase 2 / real managed
data**: **Q-03** (impersonation policy — disable / consent-gated / audit-only) and **Q-04** (secret-at-rest **mechanism**
— `encrypts` vs external custody + rotation), both tracked in the architecture plan **§17**. Still-open decisions to
settle as their phases approach: **Q-03, Q-04** (privacy — before Phase 2), then **Q-05, Q-06, Q-07, Q-08, Q-09, Q-10**.
