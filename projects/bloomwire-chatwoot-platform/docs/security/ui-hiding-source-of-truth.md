# UI Hiding Source of Truth (for Phase 11B.6)

Canonical list of what the dashboard UI may hide for business/customer account users in Bloomwire managed
mode. **Hard rule:** UI hiding is **cosmetic / UX + defense-in-depth only**. The **backend** (see
`backend-guard-map.md`) is the security boundary and returns `403` regardless of UI. Never hide a control as a
substitute for a backend guard, and never leave a backend-blocked control visible-and-clickable without
flagging it.

11B.6 must not assume effective Bloomwire toggle state is already available in the frontend. Proactive
toggle-gated UI hiding requires a safe frontend config/API/capability seam that exposes only non-secret
effective Bloomwire UI capabilities. Until that seam exists, backend `403` responses (`managed_by_ops` /
`managed_request`) remain the enforcement source, and the UI may only react to those responses.

Detection hint for the frontend: an Ops-managed block responds `403` with `managed_by_ops: true`
(account/provider guards) or `managed_request: true` (native WhatsApp). See `backend-guard-map.md`.

---

## A. SAFE TO HIDE in 11B.6 — confirmed backend-blocked

These controls map 1:1 to a validated backend guard. Hiding them only removes a button that already returns
`403`.

| UI surface (business admin) | Backend guard | Toggle |
|---|---|---|
| Account **settings save/update** | PR #43 `accounts#update` | `RESTRICT_ACCOUNT_ADMIN` |
| **Add / edit / delete agent**, bulk agent import | PR #43 `agents#*` | `RESTRICT_ACCOUNT_ADMIN` |
| Account **webhooks** add/edit/delete | PR #43 `webhooks#*` | `RESTRICT_ACCOUNT_ADMIN` |
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

## 11B.6 go/no-go

**GO** to implement UI hiding for **Group A** only — **conditioned on first building the frontend capability
seam described above** (the frontend does not yet receive effective Bloomwire toggle state), or, until that
seam exists, **reacting to the backend `403` / `managed_by_ops` / `managed_request` responses** — with the
explicit contract that the backend guard remains the enforcement. The `Toggle` column above names the
**backend** governing toggle for each surface (what the future capability seam would derive from), not a value
the frontend currently has. **NO-GO** for Groups B and C. Any Group-C control that gets hidden ahead of a
backend slice must be called out as **not yet backend-enforced**.
