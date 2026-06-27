# UI Hiding Source of Truth (Phase 11B.6 + 11B.7)

Canonical list of what the dashboard UI hides for business/customer account users in Bloomwire managed
mode. **Hard rule:** UI hiding is **cosmetic / UX + defense-in-depth only**. The **backend** (see
`backend-guard-map.md`) is the security boundary and returns `403` regardless of UI. Never hide a control as a
substitute for a backend guard, and never leave a backend-blocked control visible-and-clickable without
flagging it.

Detection hint for the frontend: an Ops-managed block responds `403` with `managed_by_ops: true`
(account/provider/bot guards) or `managed_request: true` (native WhatsApp). See `backend-guard-map.md`.

## Capability seam (IMPLEMENTED — 11B.6B onward)

The frontend now receives effective Bloomwire UI state via a **non-secret, server-derived capability map**, so
hiding is proactive (no longer only reactive to `403`):

- **Backend:** `Bloomwire::Capabilities.for(account_user)` (`app/lib/bloomwire/capabilities.rb`) is emitted as
  `bloomwire_capabilities` on the account payload (`_account.json.jbuilder`). It returns **only derived
  `can*` booleans** — **never** raw `BLOOMWIRE_*` toggle names/values. Each capability = `admin && !restricted?`.
- **Frontend:** `useBloomwireCapabilities()` (`dashboard/composables/useBloomwireCapabilities.js`) reads only
  that map; **stock-safe default `true`** when a key is absent (Bloomwire OFF / older backend / not loaded).

| Capability | False (hidden) when | Drives |
|---|---|---|
| `canManageAccountControlPlane` | `RESTRICT_ACCOUNT_ADMIN` ON | account settings save + fields readonly (11B.7A); account webhooks controls |
| `canManageProviderSetup` | `RESTRICT_PROVIDER_SETUP` ON | provider/channel connect cards & buttons |
| `canManageNativeWhatsappSetup` | `RESTRICT_NATIVE_WHATSAPP_SETUP` ON | native WhatsApp setup/reconfigure |
| `canDeleteManagedProviderInbox` | `RESTRICT_PROVIDER_SETUP` ON | delete button for managed/provider inboxes (self-service stays) |
| `canRegisterProviderWebhook` | `RESTRICT_PROVIDER_SETUP` ON | WhatsApp register-webhook action |
| `canCreateInbox` | `RESTRICT_PROVIDER_SETUP` ON | New Inbox button + all channel cards/factory (11B.7C) |
| `canManageBots` | `RESTRICT_BOT_MANAGEMENT` ON | Bots sidebar entry + page route-block + Add/Edit/Delete/reset + inbox BotConfiguration (11B.7D) |
| `canAccessIntegrations` | `RESTRICT_PROVIDER_SETUP` ON | Integrations sidebar entry + route-block (11B.7E) |

---

## A. SAFE TO HIDE in 11B.6 — confirmed backend-blocked

These controls map 1:1 to a validated backend guard. Hiding them only removes a button that already returns
`403`.

| UI surface (business admin) | Backend guard | Toggle |
|---|---|---|
| Account **settings save/update** (and name/locale/domain/support-email **readonly**, 11B.7A) | PR #43 `accounts#update` | `RESTRICT_ACCOUNT_ADMIN` |
| ~~Add / edit / delete agent, bulk agent import~~ → **REVERTED in 11B.7B (PR #55): agent controls are now VISIBLE** for the business admin | — (agents no longer backend-blocked) | — |
| Account **webhooks** add/edit/delete | PR #43 `webhooks#*` | `RESTRICT_ACCOUNT_ADMIN` |
| **New Inbox** button + all channel cards/factory (incl. `web_widget`/`api`) | PR #56 `inboxes#create` (`canCreateInbox`) | `RESTRICT_PROVIDER_SETUP` |
| **Bots**: sidebar entry, page (route-blocked to managed-state), Add/Edit/Delete/reset-token/reset-secret, inbox-level `BotConfiguration` set/disconnect | PR #57 (`canManageBots`) | `RESTRICT_BOT_MANAGEMENT` |
| **Integrations**: sidebar entry + route (redirect/managed-state); Connect/Add/Configure | PR #58 UI + PR #47 write 403 (`canAccessIntegrations`) | `RESTRICT_PROVIDER_SETUP` |
| Connect **Facebook/Instagram/X/TikTok/Google/Microsoft/Shopify** (OAuth init + "reauthorize") | PR #44 provider setup + callbacks | `RESTRICT_PROVIDER_SETUP` |
| Create **Twilio** channel | PR #44 `channels/twilio_channels#create` | `RESTRICT_PROVIDER_SETUP` |
| Create/edit **email / SMS / LINE / Telegram / voice** inbox | PR #46 `inboxes#create|update` | `RESTRICT_PROVIDER_SETUP` |
| Create/edit **WhatsApp** inbox (native setup) | PR #40 `inboxes#create|update` (whatsapp), `whatsapp/authorizations#create` | `RESTRICT_NATIVE_WHATSAPP_SETUP` |
| Connect/configure **integrations** (Dialogflow/etc. hooks), **Slack** connect, **Linear** connect | PR #47 `integrations/hooks#create|update`, `slack#create|update`, Linear callback | `RESTRICT_PROVIDER_SETUP` |
| **Delete** a managed/provider inbox (WhatsApp/email/SMS/LINE/Telegram/social/voice) | PR #48 `inboxes#destroy` (non self-service) | `RESTRICT_PROVIDER_SETUP` |
| **Re-register webhook** on a WhatsApp inbox | PR #48 `inboxes#register_webhook` | `RESTRICT_PROVIDER_SETUP` |

## B. MUST NOT HIDE YET — explicitly allowed (backend returns success)

Hiding these would remove working, legitimate functionality. Leave visible.

| UI surface | Why it stays | Backend |
|---|---|---|
| **Delete web_widget / API inbox** | self-service inbox deletion is allowed | PR #48 leaves stock |
| **Reset API channel secret** (`reset_secret`) | business owns its API integration secret | allow (Tier-B) |
| **Sync WhatsApp templates** (`sync_templates`) | read-sync, no setup/credential change | allow (Tier-B) |
| **WhatsApp health** view (`health`) | read-only status | allow (Tier-B) |
| **Live call** controls (`conference` token/join/end) | runtime call handling; agents need it | allow (Tier-B) |
| **Conversations / contacts / inbox read** | core runtime | always allowed |
| Anything backed by **runtime token refresh** | required to keep connected integrations working | allow — do not block |

## C. DEFERRED — product decision required before hiding (do NOT hide in 11B.6)

| UI surface | Status | Reference |
|---|---|---|
| **Enable / disable WhatsApp calling** | Recommended Ops-only **if** calling is enabled — re-registers the router-owned Meta webhook. **Candidate for backend slice 11B.5D.** Decide backend first, then hide. | `tier-b-existing-ops-decisions.md` (D) |
| **Set inbound calls** | Allow, or product decision together with calling. | `tier-b-existing-ops-decisions.md` (E) |
| **Disconnect Linear / Notion / Shopify** integration | Product decision; also a stock admin-gate gap (no admin policy on the dedicated destroy controllers). | `tier-b-existing-ops-decisions.md` (G) |

> Hiding a Group-C control before its decision lands creates UX drift (hiding an allowed action, or leaving a
> soon-to-be-blocked one). Wait for the decision/backend slice.

---

## Phase 11B.7 corrections — IMPLEMENTED (final UI expectations)

The 11B.6 hiding was corrected to match the business-owner permission contract (business owner/admin keeps
full in-account visibility + people-management; only setup is Ops-owned). **All merged + runtime-validated
(`a8023a78`, 11B.7R PASS).** Final UI state for a business admin in managed mode:

- **Account name (11B.7A):** the name input (and locale / custom-domain / support-email) is **disabled /
  readonly** with a **"managed by Bloomwire"** helper; the Save button stays hidden.
- **Agents/Teams (11B.7B):** agent **New / Edit / Delete** controls are **VISIBLE** again (governed only by
  stock `isAdmin` / `showEditAction` / `showDeleteAction`); the earlier 11B.6B hiding was reverted. Teams stay
  visible.
- **Inboxes (11B.7C):** **New Inbox** button is **hidden**; channel cards (`ChannelList`) and direct
  `/settings/inboxes/new/:channel` routes (`ChannelFactory`) render a **managed-by-ops state** for **all**
  channel types incl. `web_widget`/`api`. Inbox **list/read/settings stay visible**; self-service
  `web_widget`/`api` **delete stays allowed** (PR #52 unchanged).
- **Bots (11B.7D):** **Bots sidebar entry hidden**; the bots page is **route-blocked to a managed-state** and
  performs **no secret-exposing fetch**; Add/Edit/Delete/reset-token/reset-secret are not reachable; the
  inbox-level **BotConfiguration** set/disconnect is hidden + method-guarded.
- **Integrations (11B.7E):** **Integrations sidebar entry hidden**; integration routes **redirect to the
  dashboard** (`redirectIfIntegrationsManaged`, stock-safe). **Catalog read stays open** — it is consumed by
  runtime conversation surfaces (ContactPanel/Linear, video-call, label suggestions) — but the **admin
  surface UI is hidden**, and connect/config writes remain backend-403 (PR #47).

Each is backend-first (or already backend-enforced) per the hard rule above.

---

## Status: COMPLETE

Phase 11B.6 (capability seam + UI hiding Groups A) **and** Phase 11B.7 (permission-model correction) are
**implemented and runtime-validated** on `version_1 @ a8023a78`. Groups **B** (must-not-hide / allowed) and
**C** (deferred product decisions) above remain as documented. The frontend capability seam (top of this doc)
is live; UI hiding is proactive via `can*` capabilities, with the backend `403` map as the enduring
enforcement boundary.
