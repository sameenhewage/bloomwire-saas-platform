# Phase 12C — Ops-only WhatsApp Channel Provisioning — Discovery Report (Slice 1)

> Discovery-first analysis for Phase 12C. **Base:** `version_1 @ 542a68ed` (PR #60 merge). Graph stale
> (`built_at_commit 381705b8`, ~35 commits behind — all Phase 11B/12B + docs, none touching the provisioning
> control-plane), so all findings are **corroborated against source on disk**; per AGENTS.md no manual
> `graphify update` was run.

## 1. Acceptance truth (restated)
Bloomwire Super Admin/Ops can **provision or link** the WhatsApp channel / setup-mapping in a controlled way;
business/account users **cannot create or modify** real WhatsApp channel setup directly. **Secrets stay only in
`Channel::Whatsapp#provider_config`**; the Bloomwire setup registry stays **non-secret control-plane metadata**.

## 2. Current implementation (as built)

### 2.1 Ops-only surfaces (SuperAdmin / `:super_admin` Devise scope)
| Surface | File | Auth + gate | Capability |
|---|---|---|---|
| Setup-mapping CRUD | `app/controllers/super_admin/bloomwire_whatsapp_setups_controller.rb` | `authenticate_super_admin!` (inherited from `SuperAdmin::ApplicationController`) + `ensure_bloomwire_mode_enabled` | index/new/create/show/edit/update + member `readiness`; **`setup_params` permits ONLY non-secret fields** (`account_id, inbox_id, channel_whatsapp_id, setup_status, status_reason, waba_id, phone_number_id, display_phone_number`) |
| Setup-request queue | `app/controllers/super_admin/bloomwire_whatsapp_setup_requests_controller.rb` | same | index/show/update; Ops sets `status`, `status_reason`, and **links** a request to a mapping via `bloomwire_whatsapp_setup_id` (same-account validated) |
| Readiness console | same setups controller `#readiness` | same | read-only `Bloomwire::WhatsappRealHopReadiness` checklist (never calls Meta, never renders secrets) |

`SuperAdmin::ApplicationController` (`:7-14`) runs `before_action :authenticate_super_admin!` for **every** action;
`/super_admin` uses a separate `SuperAdmin` Devise identity, so account users (`:user` scope) cannot reach it.

### 2.2 Account-side surface (business users, token auth)
| Surface | File | Auth + gate | Capability |
|---|---|---|---|
| Setup **request** intake | `app/controllers/api/v1/accounts/bloomwire/whatsapp_setup_requests_controller.rb` | `ensure_bloomwire_mode_enabled!` (404 when OFF) + `check_admin_authorization?` (agents → 401) | index/create a **`Bloomwire::WhatsappSetupRequest`** only; **safe DTO** (`status, status_reason, completed_at, created_at, updated_at` — no IDs/secrets) |

**Routes (`config/routes.rb`):** account namespace exposes **only** `bloomwire/whatsapp_setup_requests [:index, :create]`
(`:346-347`). There is **no account-side route** to create/modify a `Bloomwire::WhatsappSetup` **mapping**. The
mapping CRUD lives solely under `/super_admin/bloomwire_whatsapp_setups` (`:687-689`).

### 2.3 Native channel-setup restriction (business denial of real channel setup)
`app/controllers/concerns/bloomwire/restricts_native_whatsapp_setup.rb` → `restrict_native_whatsapp_setup!`
returns **403** `{ managed_request: true }` (no secrets) when `BLOOMWIRE_MODE_ENABLED` +
`BLOOMWIRE_RESTRICT_NATIVE_WHATSAPP_SETUP` are ON, for native WhatsApp setup actions
(`whatsapp/authorizations#create`, WhatsApp `inboxes#create/#update`). Plus Phase 11B.7C blocks **all** inbox
creation in managed mode. So business users cannot create/modify the real channel.

### 2.4 Source-of-truth + secrets
- `Bloomwire::WhatsappSetup` (`app/models/bloomwire/whatsapp_setup.rb`): non-secret routing columns only
  (`waba_id, phone_number_id, display_phone_number` + FKs); validations enforce account/inbox/channel
  consistency and `routeable_when_ready_for_webhook`. **No secret columns.**
- `Channel::Whatsapp#provider_config` remains the **only** secret store (`api_key`, `webhook_verify_token`).
  The mapping **references** an existing channel; it never stores credentials.

## 3. Existing test coverage (from a coverage inventory of 7 spec files)
Already covered: SuperAdmin setups CRUD happy paths (create non-secret, update status, reject
`ready_for_webhook` w/o fields, show, reject invalid status), unauthenticated→redirect, master-OFF→surface
unavailable, no-secret rendering, no secret columns; SuperAdmin setup_requests queue + same/cross-account
linking + no-secret; readiness authz (incl. **business admin/agent denied** for the *readiness* action) + OFF +
no-secret; account request API (admin-only, **agents 401**, **OFF 404**, **DTO no IDs/secrets**, secret params
ignored, cross-account 401); both model specs (consistency, uniqueness, ready routeability, no secret columns).

### Confirmed coverage GAPS (what Phase 12C adds — all test-only)
| # | Gap | Slice |
|---|---|---|
| A | An **authenticated business admin/agent** (`:user` scope) is denied the SuperAdmin **setups** CRUD (index/create/update) | 3 |
| B | Ops **happy-path**: create/link an existing `whatsapp_cloud` channel + inbox + matching `phone_number_id` and **successfully** flip `setup_status → ready_for_webhook` | 2 |
| C | Secret-ish params (`provider_config`/`api_key`/`webhook_verify_token`) submitted to SuperAdmin setups create/update are **dropped by strong params** (not persisted/echoed) | 4 |
| D | An authenticated business admin/agent is denied the SuperAdmin **setup_requests** queue (index/show/update) | 3 |
| F | **No account-side route** creates/modifies a `Bloomwire::WhatsappSetup` **mapping** (only the request intake exists) | 3 |

## 4. Decision — smallest safe implementation
**The Ops-only provisioning/link authorization boundary already exists and is enforced in product code.** Phase
12C therefore adds **backend authorization specs only** (no product code, no schema, no new routes/UI) to
**lock** the boundary and close gaps A–F:
- **Slice 2:** prove Ops (SuperAdmin) can provision/link a mapping and flip it to `ready_for_webhook`.
- **Slice 3:** prove an authenticated business admin/agent is denied the SuperAdmin setups + setup_requests
  surfaces, and that no account-side mapping-mutation route exists.
- **Slice 4:** prove secret params are dropped by strong params and no secret is persisted/echoed.
- **Slice 6:** prove Bloomwire OFF ⇒ the whole provisioning control-plane is stock (surfaces unavailable / 404,
  no rows created).
- **Slice 5 (UI/API wiring): NOT required** — the existing SuperAdmin CRUD + account request intake already
  satisfy the architecture; backend authz is the security boundary and is intact.

## 5. Explicitly DEFERRED (stop-condition territory — NOT built in 12C)
Creating the actual **`Channel::Whatsapp` with real Meta secrets** has no first-class Ops UI today (it is an
operational/console step using the existing native/embedded-signup services). Building an Ops surface that
**accepts and stores real Meta credentials** would trigger Phase 12C stop conditions:
- **secret-at-rest policy decision** (CONTEXT.md: encrypt-or-accept+document gate);
- **real Meta API calls** (`Channel::Whatsapp` save runs `validate_provider_config` + `setup_webhooks` against
  Graph);
- **larger product code** than this slice.

This matches the architecture plan's "Phase 4 — Ops-only channel creation" being a separate, gated slice. It is
recorded here as the **remaining blocker for the real live hop** and is out of scope for 12C.

## 6. Constraints honored
No deploy · no real Meta/WhatsApp calls · no secrets printed · no destructive DB · Chatwoot source-of-truth
intact · Bloomwire OFF == stock · backend authorization treated as the security boundary (specs hit controllers,
not UI).
