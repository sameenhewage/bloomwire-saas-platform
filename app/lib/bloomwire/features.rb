# Central feature-check service: the single place Bloomwire toggles are read.
# All toggles default OFF. A master toggle AND-gates every sub-feature, and the
# managed-data sub-features additionally require privacy hardening ON (fail-closed).
module Bloomwire::Features
  MASTER = 'BLOOMWIRE_MODE_ENABLED'.freeze

  # symbol => InstallationConfig key. Read only through this service (no scattered ENV reads).
  SUB_FEATURES = {
    managed_whatsapp_onboarding: 'BLOOMWIRE_MANAGED_WHATSAPP_ONBOARDING',
    # ADR-0010 v3: the RESUMABLE ASYNC onboarding path (attempt record + background processor). OFF == the existing
    # synchronous embedded-signup flow. Privacy-dependent (it persists encrypted customer secrets), default OFF.
    async_whatsapp_onboarding: 'BLOOMWIRE_ASYNC_WHATSAPP_ONBOARDING',
    global_webhook_router: 'BLOOMWIRE_GLOBAL_WEBHOOK_ROUTER',
    restrict_native_whatsapp_setup: 'BLOOMWIRE_RESTRICT_NATIVE_WHATSAPP_SETUP',
    restrict_account_admin: 'BLOOMWIRE_RESTRICT_ACCOUNT_ADMIN',
    restrict_provider_setup: 'BLOOMWIRE_RESTRICT_PROVIDER_SETUP',
    restrict_bot_management: 'BLOOMWIRE_RESTRICT_BOT_MANAGEMENT',
    # Phase 17E.2: restrict a business AGENT's contact list/search/show to contacts reachable through their
    # assigned inboxes (via contact_inboxes). Admins are unaffected. OFF == stock Chatwoot (agents see all).
    restrict_agent_contact_visibility: 'BLOOMWIRE_RESTRICT_AGENT_CONTACT_VISIBILITY',
    privacy_hardening: 'BLOOMWIRE_PRIVACY_HARDENING',
    outgoing_gateway: 'BLOOMWIRE_OUTGOING_GATEWAY',
    custom_branding: 'BLOOMWIRE_CUSTOM_BRANDING',
    # Phase 17F.1: gate the administrator-only, READ-ONLY "Categories & Inboxes" overview (page + API). OFF ==
    # stock Chatwoot (no overview route/page/API). Admin-only + account-scoped; no schema, no writes, no mapping.
    category_admin_ui: 'BLOOMWIRE_CATEGORY_ADMIN_UI'
  }.freeze

  # Managed-data sub-features that are inert unless privacy hardening is ON (architecture plan §4.1).
  PRIVACY_DEPENDENT_FEATURES = %i[managed_whatsapp_onboarding async_whatsapp_onboarding global_webhook_router].freeze

  # InstallationConfig key names for the managed-data sub-features. Used by the write-path guard so the
  # privacy prerequisite holds at ANY SuperAdmin config seam, not only the custom Bloomwire page.
  PRIVACY_DEPENDENT_KEYS = PRIVACY_DEPENDENT_FEATURES.map { |feature| SUB_FEATURES.fetch(feature) }.freeze

  # InstallationConfig keys whose stored value must never be shown or echoed in cleartext on SuperAdmin
  # surfaces while privacy hardening is ON (ADR-0003). Single source of truth for both the app_config
  # view and the generic Administrate installation_configs editor.
  MASKED_SECRET_KEYS = %w[WHATSAPP_APP_SECRET BLOOMWIRE_WHATSAPP_GLOBAL_VERIFY_TOKEN].freeze

  module_function

  def enabled?(feature)
    feature = feature.to_sym
    return master_enabled? if feature == :mode

    raise ArgumentError, "Unknown Bloomwire feature: #{feature.inspect}" unless SUB_FEATURES.key?(feature)
    return false unless master_enabled?
    return false if PRIVACY_DEPENDENT_FEATURES.include?(feature) && !raw_enabled?(:privacy_hardening)

    raw_enabled?(feature)
  end

  def master_enabled?
    raw_enabled?(:mode)
  end

  # True when native (account-level) WhatsApp setup/configuration must be blocked for business users:
  # Bloomwire master mode ON AND the restrict toggle ON. The single gate the native setup guard reads.
  def restrict_native_whatsapp_setup?
    master_enabled? && raw_enabled?(:restrict_native_whatsapp_setup)
  end

  # True when business account ADMINISTRATORS must be blocked from dangerous account-admin / control-plane
  # actions (agent & role management, account settings, webhooks): Bloomwire master mode ON AND the restrict
  # account-admin toggle ON. The single gate the account-control-plane guard reads.
  def restrict_account_admin?
    master_enabled? && raw_enabled?(:restrict_account_admin)
  end

  # True when business/customer account users (admins AND agents) must be blocked from external provider /
  # channel setup flows (Facebook page register/reauthorize, Twilio channel create, provider OAuth
  # authorizations, Shopify connect): Bloomwire master mode ON AND the restrict provider-setup toggle ON.
  # In managed mode these flows are Ops/SuperAdmin-owned. The single gate the provider-setup guard reads.
  def restrict_provider_setup?
    master_enabled? && raw_enabled?(:restrict_provider_setup)
  end

  # True when business/customer account users (admins AND agents) must be blocked from bot management
  # (agent-bot list/show — which expose access_token/secret/bot_config — plus create/update/destroy/avatar,
  # token/secret reset, and inbox-level set/disconnect bot): Bloomwire master mode ON AND the restrict
  # bot-management toggle ON. In managed mode bots are Ops/SuperAdmin-owned. The single gate the bot guard reads.
  def restrict_bot_management?
    master_enabled? && raw_enabled?(:restrict_bot_management)
  end

  # Phase 17E.2: True when a business AGENT's contact list/search/show must be scoped to contacts reachable
  # through their assigned inboxes (multi-category/multi-inbox privacy): Bloomwire master mode ON AND the
  # restrict toggle ON. Admins are always exempt (see Bloomwire::ContactVisibility). OFF == stock Chatwoot.
  def restrict_agent_contact_visibility?
    master_enabled? && raw_enabled?(:restrict_agent_contact_visibility)
  end

  # True when `name` is a managed-data InstallationConfig key that requires privacy hardening ON
  # before it may be persisted to true (write-path guard, fail-closed).
  def privacy_dependent_key?(name)
    PRIVACY_DEPENDENT_KEYS.include?(name)
  end

  # True when `name` is a masked secret key AND privacy hardening is effectively ON (master AND-gated
  # via enabled?). The single seam used by every SuperAdmin config surface to decide masking + no-wipe.
  def masked_secret_key?(name)
    MASKED_SECRET_KEYS.include?(name.to_s) && enabled?(:privacy_hardening)
  end

  # Stored toggle value WITHOUT the master AND-gate. Used by the SuperAdmin bootstrap page UI.
  def raw_enabled?(feature)
    ActiveModel::Type::Boolean.new.cast(GlobalConfigService.load(config_key(feature), false)).present?
  end

  def config_key(feature)
    feature = feature.to_sym
    return MASTER if feature == :mode

    SUB_FEATURES.fetch(feature) { raise ArgumentError, "Unknown Bloomwire feature: #{feature.inspect}" }
  end
end
