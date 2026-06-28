# Bloomwire Phase 14 S2a: Ops-only writer that merges WhatsApp provider credentials into an EXISTING
# Channel::Whatsapp#provider_config. It is the secure replacement for the rails-console step documented in the
# customer onboarding runbook (§3.1).
#
# Guarantees:
# - WRITE-ONLY secret: a blank/absent api_key keeps the current token (never wiped, never echoed).
# - Non-secret routing ids (phone_number_id, business_account_id) are updated only when provided (blank == keep).
# - MERGE (never replace) so existing keys (webhook_verify_token, source, calling flags, ...) are preserved.
# - save(validate: false) so Channel::Whatsapp#validate_provider_config (a live Meta GET) is NOT triggered;
#   updating an existing channel also does not fire the create-only sync_templates / setup_webhooks callbacks,
#   so no Meta call is made. Mirrors the model's own enable_voice_calling! save.
# - Never captures webhook_verify_token (auto-generated; the global router uses BLOOMWIRE_WHATSAPP_GLOBAL_VERIFY_TOKEN)
#   or verification_pin. provider_config is encrypted at rest (ADR-0006) by the model.
class Bloomwire::WhatsappCredentialWriter
  # The only secret this surface writes; rendered write-only and masked in the UI.
  SECRET_KEYS = %w[api_key].freeze
  # Non-secret routing identifiers Ops may set/correct alongside the token.
  NON_SECRET_KEYS = %w[phone_number_id business_account_id].freeze
  WRITABLE_KEYS = (SECRET_KEYS + NON_SECRET_KEYS).freeze

  pattr_initialize [:channel!, :attributes!]

  def perform
    config = channel.provider_config.to_h.dup
    WRITABLE_KEYS.each do |key|
      value = normalized(attributes[key])
      next if value.nil? # blank/absent => keep current value (no-wipe, including the write-only api_key)

      config[key] = value
    end
    channel.provider_config = config
    channel.save!(validate: false)
    channel
  end

  private

  def normalized(value)
    value.to_s.strip.presence
  end
end
