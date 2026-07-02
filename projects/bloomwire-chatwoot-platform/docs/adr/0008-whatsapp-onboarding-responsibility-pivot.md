# ADR-0008 — WhatsApp Onboarding Responsibility Pivot (SuperAdmin = Global Config; customer self-serve)

- Status: Accepted (Phase 17A = removal, implemented; PR B / PR C to follow)
- Extends: ADR-0001/0002/0003 (never overrides); ADR-0005 (global webhook router — unchanged); ADR-0006
  (provider secret at rest — unchanged); ADR-0007 (platform-admin boundary — unchanged)
- Supersedes: the **Ops-driven provisioning / manual setup-mapping UI** parts of ADR-0004. ADR-0004 stays valid
  for the `Bloomwire::WhatsappSetup` mapping *foundation* (the model/table the router reads); only the manual
  Ops CRUD surface it described is retired here.

## Context

The SuperAdmin console had two over-engineered surfaces that duplicated Chatwoot's native
account/user/inbox responsibilities:

- **"Provision new WhatsApp customer"** (`Bloomwire::CustomerProvisioningService`) — created account + owner +
  agents + WhatsApp channel shell + inbox + members + setup mapping in one Ops action.
- **Standalone "New setup mapping" CRUD** (`bloomwire_whatsapp_setups#new/create/edit/update`) — manual Ops
  creation/editing of the router mapping.

Chatwoot already owns accounts/users/inboxes/channels natively, and already has an Add-Inbox flow. The manual
Ops surfaces were extra machinery to maintain and a second way to do what the product should let the customer
do themselves. Phase 16C owner-activation existed *only* because provisioning created owners without an email;
once provisioning is gone, native Devise invite/reset covers owner access.

## Decision

1. **SuperAdmin WhatsApp area = Global WhatsApp Platform Config only.** It surfaces global webhook callback URL,
   verify-token status, router enabled/disabled, webhook health, last webhook received, platform readiness, and
   an optional read-only connected-inbox status list. It does **not** provision customers or create/edit mappings.
2. **Account & user creation stay native** — SuperAdmin → Accounts and SuperAdmin → Users; owner access uses
   native Chatwoot/Devise invite/reset. No Bloomwire-specific provisioning or owner-activation.
3. **Customers complete WhatsApp setup themselves** from Account Settings → Inboxes → **Add Inbox**. When
   Bloomwire mode is ON, the native channel picker routes WhatsApp to a Bloomwire wizard where the account
   administrator enters their **own** WhatsApp/Meta credentials.
4. **The internal `phone_number_id → inbox/channel` mapping (`Bloomwire::WhatsappSetup`) remains** — the global
   webhook router (ADR-0005) resolves inbound webhooks via `ready_for_webhook.where(phone_number_id:)`. It is now
   created/updated by the **customer-side wizard**, never by manual Ops UI.
5. **Secrets stay on `Channel::Whatsapp#provider_config`** (ADR-0006); the mapping remains non-secret. No
   duplicate secret store.

## Consequences

- **Removed (Phase 17A / PR A):** the provisioning controller/route/view + `CustomerProvisioningService`; the
  `new/create/edit/update` actions + views of the setups controller (route → `only: [:index, :show]`); the 16C
  `send_owner_activation` action + `Bloomwire::BusinessOwnerActivator` + "Business owner access" card; the related
  nav/index links and specs.
- **Kept:** the global webhook + router; `Bloomwire::WhatsappSetup` model/table; encrypted channel credentials +
  `WhatsappCredentialWriter`; the readiness calculator; a read-only setups surface (transitional → Global Config).
- **Parked:** `Bloomwire::WhatsappSetupRequest` (Ops intake queue) is deprecated — superseded by the wizard;
  removed later via a separate data-cleanup migration after PR C. **No table drops or data deletion in 17A.**
- **Follow-ups:** PR B = rebuild the read-only surface into the Global WhatsApp Platform Config page; PR C =
  the customer Add-Inbox wizard (creates channel + inbox + mapping), then retire `WhatsappSetupRequest`.

### Implementation status
- **PR B (Phase 17B, merged):** SuperAdmin read-only Global WhatsApp Config page.
- **Phase 17C.1 (merged):** backend foundation — `canSelfServeManagedWhatsapp` capability, `WhatsappSetupCreator`,
  `WHATSAPP_CONFIGURATION_ID` readiness.
- **Phase 17C.2 (merged — PR #102, `84481ed`; this ADR realised for the backend):** dedicated
  **`POST /api/v1/accounts/:id/bloomwire/whatsapp/embedded_signup`** + `Bloomwire::WhatsappEmbeddedSignupService`.
  It uses the **GLOBAL webhook router** — only an
  app-to-WABA subscription (`FacebookApiClient#subscribe_app_to_waba`), **never** a per-channel callback override
  or `channel.setup_webhooks` — creates a `source:'bloomwire_managed'` channel + inbox, stores the customer token
  **only** in encrypted `provider_config`, and writes the `ready_for_webhook` mapping. Native `/whatsapp/
  authorization` is untouched (no carve-out). Customer token storage fails closed outside dev/test unless AR
  encryption is configured.
- **Remaining:** PR C frontend wizard (17C.3) + verify/go-live (17C.4); then retire `WhatsappSetupRequest`.

## Invariants preserved

No `users.type` for business roles · no `BusinessOwner` role · no duplicate chat/message source of truth · no
Enterprise dependency · WhatsApp-first · safe DTOs only · never expose secrets. Feature-OFF (Bloomwire mode) ==
stock Chatwoot.
