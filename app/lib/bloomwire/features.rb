# Central feature-check service: the single place Bloomwire toggles are read.
# All toggles default OFF. A master toggle AND-gates every sub-feature, and the
# managed-data sub-features additionally require privacy hardening ON (fail-closed).
module Bloomwire::Features
  MASTER = 'BLOOMWIRE_MODE_ENABLED'.freeze

  # symbol => InstallationConfig key. Read only through this service (no scattered ENV reads).
  SUB_FEATURES = {
    managed_whatsapp_onboarding: 'BLOOMWIRE_MANAGED_WHATSAPP_ONBOARDING',
    global_webhook_router: 'BLOOMWIRE_GLOBAL_WEBHOOK_ROUTER',
    restrict_native_whatsapp_setup: 'BLOOMWIRE_RESTRICT_NATIVE_WHATSAPP_SETUP',
    privacy_hardening: 'BLOOMWIRE_PRIVACY_HARDENING',
    outgoing_gateway: 'BLOOMWIRE_OUTGOING_GATEWAY',
    custom_branding: 'BLOOMWIRE_CUSTOM_BRANDING'
  }.freeze

  # Managed-data sub-features that are inert unless privacy hardening is ON (architecture plan §4.1).
  PRIVACY_DEPENDENT_FEATURES = %i[managed_whatsapp_onboarding global_webhook_router].freeze

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
