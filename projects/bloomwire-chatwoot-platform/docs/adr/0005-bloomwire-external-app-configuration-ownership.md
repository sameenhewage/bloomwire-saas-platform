# ADR 0005 — Bloomwire External App Configuration Ownership

- **Status:** Accepted (decision) — **implementation parked / future** (Phase 4.4
  External App Configuration Ownership; WhatsApp first vertical)
- **Date:** 2026-06-23
- **Extends:** ADR 0001 (Technical Baseline), ADR 0003 (Permission &
  Channel-Control Boundary). Relates to ADR 0004 (Global Meta/WhatsApp Webhook
  Router, Phase 8) and ADR 0002 (Enterprise Boundary). Builds on the Phase 4
  permission foundation (`Bloomwire::AccessPolicy`) and the WhatsApp setup seam
  shipped in PR #19 (`Bloomwire::WhatsappSetupGuard`,
  `Bloomwire::ChannelControlPolicy`).
- **Scope:** documentation-only. **No code, configuration, migration, schema,
  spec, feature flag, route, policy behavior, or runtime behavior is changed by
  this ADR.** It records decisions and a set of parked future slices. Nothing
  described here is implemented yet, and **Dialog admins are not denied yet.**

---

## Context

ADR 0003 set the durable boundary: **platform owns channel/inbox setup; Dialog
(tenant) admins do not by default.** This ADR turns that boundary into a concrete,
buildable ownership model for **external app/channel configuration**, with
**WhatsApp as the first vertical**.

Discovery findings that motivate this ADR:

- Chatwoot's external-app setup currently lives in **tenant/account-scoped
  controllers** (`Api::V1::Accounts::InboxesController#create/#update/#register_webhook`
  and `Api::V1::Accounts::Whatsapp::AuthorizationsController#create`).
- **PR #19 added a central seam** for WhatsApp setup actions
  (`Bloomwire::WhatsappSetupGuard` → `Bloomwire::ChannelControlPolicy`) wired into
  exactly those actions. The seam is **behavior-neutral today** — it reproduces
  the pre-existing admin gate, so Dialog/account admins are still allowed.
- **`BloomwireBusinessProfile`** already exists (one per Chatwoot account) and is
  the natural account-level Bloomwire control-plane anchor.
- A **SuperAdmin / Bloomwire platform plane already exists** (`super_admin/`
  Administrate console; `platform/api/v1` token API; `Bloomwire::AccessPolicy`
  platform actions such as `activate_tenant`).
- **WhatsApp secrets currently live in `Channel::Whatsapp#provider_config`**
  (jsonb): `api_key`/access token, `phone_number_id`, `business_account_id`
  (WABA), `webhook_verify_token`, `source`.
- Inbound WhatsApp events resolve a channel by **globally-unique `phone_number`**
  (`channel_whatsapp.phone_number` UNIQUE), validated against
  `provider_config['phone_number_id']`. One Bloomwire-owned global webhook is the
  **target** architecture (ADR 0004) but its full inbound router is **later**.

"External apps" in scope of this ownership rule: **WhatsApp, SMS, Email,
Instagram/Facebook, Shopify, and later Telegram/Signal/etc.**

---

## Decision

The following decisions are **locked** by this ADR.

1. **Bloomwire owns all external app/channel configuration.** Connecting,
   disconnecting, creating, reauthorizing, registering webhooks for, and editing
   provider credentials/raw config of external app channels is a
   **Bloomwire/platform** responsibility.
2. **Dialog (tenant) admins can use configured channels but cannot configure
   external apps.** They keep full normal inbox usage (conversations, sending,
   assignment, templates) on already-configured inboxes; they do **not** get
   external-app setup/config authority.
3. **Chatwoot remains the conversation engine and source of truth** for accounts,
   users, inboxes, channels, contacts, conversations, messages, teams, campaigns.
   Bloomwire adds an **ownership/control layer only** and never duplicates
   conversation/contact/message data.
4. **The Bloomwire Admin / platform plane owns setup.** Setup is performed by a
   SuperAdmin / platform operator acting in a platform context.
5. **The tenant `InboxesController` (and tenant account-scoped controllers) must
   NOT be reused as the platform setup path.** Tenant controllers require
   `AccountUser` membership and represent the tenant plane; using them for
   platform setup mixes planes and risks privilege confusion.
6. **Use a dedicated Bloomwire Admin namespace/controller/service for setup.**
   It reuses the existing Chatwoot WhatsApp channel-creation logic internally
   (e.g. `Whatsapp::ChannelCreationService`) rather than duplicating it.
7. **WhatsApp is the first vertical.** SMS, Email, Instagram/Facebook, Shopify,
   and Telegram/Signal follow later, reusing the same ownership model and policy
   seam.
8. **One global Bloomwire-owned WhatsApp webhook is the target architecture**
   (per ADR 0004): `Meta app → one Bloomwire global endpoint → Bloomwire router →
   correct Chatwoot account/inbox/channel`.
9. **The full inbound global webhook router is later, not part of this phase.**
   Phase 4.4 only prepares **routing/ownership metadata**; the router itself is
   ADR 0004 / Phase 8 and stays behind `BLOOMWIRE_GLOBAL_META_WEBHOOK_ENABLED`
   (default `false`).
10. **Secrets must not be duplicated into routing/ownership tables.** The proposed
    `bloomwire_channel_integrations` table stores **non-secret** ownership and
    routing metadata only.
11. **Raw provider credentials must not be exposed to Dialog tenant users.**
    Tenant-facing DTOs/APIs must not leak `api_key`/access tokens,
    `webhook_verify_token`, or raw provider config (extends global rule 8 /
    CONTEXT.md security contract).
12. **Existing Chatwoot teams, campaigns, contacts, conversations, and normal
    inbox usage remain untouched.** This ADR changes **who may configure**, not
    how messaging works.

---

## Proposed data model design (design only — no migration)

A new Bloomwire-owned table records **which inbox/channel Bloomwire configured for
which tenant**, plus the **non-secret routing identifiers** a future global router
will use. Per CONTEXT.md, Bloomwire tables use the `bloomwire_` prefix.

> **This is a proposed design for review. No migration, model, or schema change is
> created by this ADR.**

**Table (proposed): `bloomwire_channel_integrations`**

```text
id                            bigint, pk
bloomwire_business_profile_id bigint, fk -> bloomwire_business_profiles, not null   # owner anchor
account_id                    bigint, fk -> accounts                                # denormalized for query convenience (derivable via profile)
inbox_id                      bigint, fk -> inboxes, not null                       # the configured Chatwoot inbox
channelable_type              string                                               # polymorphic channel, e.g. "Channel::Whatsapp"
channelable_id                bigint                                                # polymorphic channel id
app_kind                      string, not null                                     # whatsapp | sms | email | instagram | facebook | shopify | ...
provider                      string                                               # e.g. whatsapp_cloud | default(360dialog)
status                        string, not null, default "pending"                  # pending | active | disabled
managed_by_bloomwire          boolean, not null, default true                      # ownership flag for enforcement
routing_key                   string                                               # stable router key where present (WhatsApp: phone_number_id)
# --- WhatsApp routing metadata (non-secret) ---
phone_number                  string                                               # E.164
phone_number_id               string                                               # Meta phone number id
waba_id                       string                                               # WABA / business_account_id
created_by_super_admin_id     bigint, fk -> users (SuperAdmin)                      # audit
created_at / updated_at       timestamps
```

**Constraints (proposed):**

- **Unique integration per inbox** — unique index on `inbox_id`.
- **Unique routing key where present** — partial unique index on `routing_key`
  (`WHERE routing_key IS NOT NULL`).
- **No raw secrets in this table** — never store `api_key`/access tokens,
  `webhook_verify_token`, or raw provider config here.
- **Secrets remain where they are for now** — WhatsApp credentials stay in
  `Channel::Whatsapp#provider_config`. Moving them to **encrypted storage** is a
  **separate future ADR**, not decided here.

**Relations:** `BloomwireBusinessProfile has_many :channel_integrations`; each
integration references exactly one `Inbox` → one `Channel` → one `Account`.
Routing identifiers (`phone_number`, `phone_number_id`, `waba_id`, `routing_key`)
are **platform-side only** and must not appear in tenant DTOs.

---

## Proposed TDD acceptance criteria (for the next implementation slices)

Written RED/GREEN now; **implemented later**, slice by slice. Risk-sensitive
slices use the Independent TDD workflow (failing acceptance + edge/security tests
before implementation).

### A. Ownership foundation (4.4-b-WA.2A) — behavior-neutral

- **RED:** no `bloomwire_channel_integrations` model/mapping exists; there is no
  Bloomwire-owned record of which inbox/channel belongs to which tenant.
- **GREEN:** the model + table exist; an integration row maps
  `profile → inbox → channel → account` with non-secret routing metadata;
  creating it changes **no** existing WhatsApp/inbox behavior and **no** policy
  decision; a backfill can represent existing WhatsApp inboxes read-only.

### B. Bloomwire Admin setup path (4.4-b-WA.2B)

- **RED:** there is no platform-scoped path for a Bloomwire Admin to create a
  WhatsApp Cloud channel/inbox for a tenant; setup only exists in tenant
  controllers.
- **GREEN:** a Bloomwire Admin (SuperAdmin), via the dedicated Bloomwire Admin
  namespace/service, creates exactly one `Channel::Whatsapp`
  (`provider: whatsapp_cloud`) + one `Inbox` for a target tenant, reusing
  `Whatsapp::ChannelCreationService`; one `bloomwire_channel_integration` row is
  recorded with correct `routing_key` (`phone_number_id`) and `account`; secrets
  are stored in provider config and **not** returned in the response.

### C. Dialog admin deny (4.4-b-WA.2C)

- **RED (must fail before implementation):** a Dialog admin (AccountUser
  `administrator`) can today create/connect/reauthorize/`register_webhook`/update
  `provider_config` for WhatsApp (the seam is behavior-neutral).
- **GREEN:** for managed external-app setup, the same actions return **401/403**,
  create **no** channel/inbox, and trigger **no** provider/webhook call. Agents
  remain denied.

### D. Normal usage unaffected (cross-cutting)

- **GREEN:** a Dialog admin can still update non-setup inbox fields (name,
  auto-assignment, working hours), and use conversations/contacts/templates/
  campaigns/sending on an existing inbox. None of these are gated.

### E. Secrets not leaked (security)

- **GREEN:** inbox/channel JSON returned to a Dialog admin contains **no** raw
  `api_key`/access token, `webhook_verify_token`, or raw `provider_config`
  secrets; routing identifiers are not exposed to tenant users.

### F. Global webhook routing metadata only (4.4-b-WA.3)

- **RED:** no Bloomwire-owned mapping from `phone_number_id`/`waba_id` to
  account/inbox/channel exists.
- **GREEN:** routing metadata is recorded and queryable
  (`phone_number_id`/`waba_id` → integration → inbox/account); **no** inbound
  router, global endpoint, or change to Chatwoot's native per-phone-number webhook
  behavior is introduced (that remains ADR 0004 / Phase 8).

---

## Risks

- **Provider credentials currently in `provider_config`** (plaintext jsonb on
  `channel_whatsapp`). Ownership is being asserted before credential storage is
  hardened; encryption is deferred to a separate ADR.
- **Tenant DTO/API may expose secrets** unless explicitly scrubbed — inbox/channel
  serializers must be audited before the Bloomwire Admin path goes live.
- **Mixing SuperAdmin with the tenant account dashboard** can cause privilege
  confusion; the dedicated platform namespace (decision 5/6) exists to avoid this.
- **Denying tenant setup before the Bloomwire setup path exists would block setup
  completely.** Therefore the deny slice (4.4-b-WA.2C) must land **after** the
  Bloomwire Admin setup path (4.4-b-WA.2B).
- **Global webhook routing needs careful migration** from the current
  phone-number route behavior; routing metadata (4.4-b-WA.3) is collected first,
  the router (ADR 0004 / Phase 8) is built separately and toggle-gated.

---

## Non-goals (explicitly out of scope of this phase / documentation-only PR)

```text
- no frontend implementation yet
- no tenant deny yet (no policy behavior change in this docs-only work)
- no webhook router implementation yet
- no Twilio/SMS/Email/Instagram/Facebook/Shopify implementation yet
- no changes to Chatwoot conversations / teams / campaigns / contacts
- no migrations, models, controllers, services, routes, or tests changed
- no production behavior change
```

---

## Phase placement / slice breakdown

Phase **4.4 — External App Configuration Ownership** (WhatsApp first vertical):

- **4.4-b-WA.1 — WhatsApp setup control seam** — ✅ done/merged (PR #19). Central
  backend seam for WhatsApp setup actions (behavior-neutral).
- **4.4-b-WA.2A — Channel integration ownership foundation** — ⏳ next.
  Behavior-neutral ownership/mapping model + design for
  `bloomwire_channel_integrations`. No tenant deny, no frontend.
- **4.4-b-WA.2B — Bloomwire Admin WhatsApp setup service/path** — ⏳ planned.
  Platform-context creation of WhatsApp channel/inbox for a tenant; reuse Chatwoot
  channel-creation logic; store ownership/routing metadata; never expose
  credentials to Dialog users.
- **4.4-b-WA.2C — Dialog admin WhatsApp self-service deny** — ⏳ planned (after
  2B). Flip the seam to deny tenant admins for WhatsApp setup/config; normal
  inbox usage unaffected.
- **4.4-b-WA.2D — Tenant frontend hiding/disabled UX** — ⏳ planned (after backend
  enforcement). Hide/disable external-app setup cards/forms for Dialog admins
  (UX only, not security).
- **4.4-b-WA.3 — Global WhatsApp webhook routing foundation** — ⏳ planned.
  Prepare Bloomwire-owned routing metadata only; full router stays ADR 0004 /
  Phase 8.

**Recommended next implementation PR after this docs PR:** **4.4-b-WA.2A**
(ownership foundation) — behavior-neutral, lowest risk, unblocks 2B/2C/2D/3.

Later verticals (reuse this model): **SMS → Email → Instagram/Facebook → Shopify
→ Telegram/Signal.**

---

## Consequences

- **Positive:** turns the ADR 0003 boundary into a concrete, testable build plan;
  keeps a single ownership record per inbox; separates non-secret routing metadata
  from secrets; sequences the deny **after** a working platform setup path so
  tenants are never left unable to get channels; keeps the future webhook router
  cleanly additive.
- **Trade-offs:** introduces a Bloomwire-owned table and a platform setup surface
  to maintain; credential hardening (encryption) and DTO scrubbing become explicit
  follow-ups; until 2B/2C land, WhatsApp setup remains a platform-performed action
  via existing surfaces with the behavior-neutral seam.

## References

- `0001-technical-baseline.md`, `0002-bloomwire-enterprise-boundary-and-telemetry.md`,
  `0003-bloomwire-permission-and-channel-control-boundary.md`,
  `0004-bloomwire-global-meta-whatsapp-webhook-router.md`
- `../../CONTEXT.md`, `../product/05-development-phases.md`
- Existing seam (context only — not modified by this ADR):
  `app/app/controllers/concerns/bloomwire/whatsapp_setup_guard.rb`,
  `app/app/services/bloomwire/channel_control_policy.rb`,
  `app/app/controllers/api/v1/accounts/inboxes_controller.rb`,
  `app/app/services/whatsapp/channel_creation_service.rb`.
