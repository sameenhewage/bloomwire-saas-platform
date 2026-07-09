# Resolves the Cloud API /register two-step-verification PIN for a WhatsApp phone number, so an EXISTING number
# (one that already carries a Meta 2SV PIN from a prior registration) is re-registered with its KNOWN pin instead
# of a fresh random one — which Meta rejects with #133005 ("Two step verification PIN Mismatch").
#
# The PIN is a secret: it is resolved SERVER-SIDE only, never logged, never returned in any API/DTO, and is stored
# encrypted (Channel::Whatsapp#provider_config, ADR-0006) after a successful register.
#
# Priority (highest first):
#   1. :stored     — the encrypted verification_pin already on THIS account's channel for this phone_number_id
#                    (written by a prior successful Bloomwire registration). Reused on every reconnect — the
#                    permanent mechanism, so a number, once connected, keeps working without re-supplying a pin.
#   2. :configured — a securely-configured existing PIN, scoped PER phone_number_id, supplied ONLY via the server
#                    env var BLOOMWIRE_WHATSAPP_EXISTING_REGISTRATION_PINS (a JSON object
#                    {"<phone_number_id>":"<pin>"}). Bootstraps a pre-existing number whose 2SV PIN Bloomwire never
#                    stored (e.g. one first registered by a legacy tool). NEVER global; a number absent from the
#                    map is never given a configured pin. Set only where that number lives (e.g. dev).
#   3. :generated  — a fresh random 6-digit PIN, used ONLY for a genuinely new number with no known PIN.
#
# Resolution#known? is false ONLY for :generated, so the caller can fail closed (never silently retry random) when
# Meta reports #133005 for a number we had no correct PIN for.
class Bloomwire::WhatsappRegistrationPin
  EXISTING_PINS_ENV = 'BLOOMWIRE_WHATSAPP_EXISTING_REGISTRATION_PINS'.freeze

  Resolution = Struct.new(:pin, :source, keyword_init: true) do
    def known?
      source != :generated
    end
  end

  def initialize(account:, phone_number_id:)
    @account = account
    @phone_number_id = phone_number_id.to_s
  end

  def resolve
    stored = stored_pin
    return Resolution.new(pin: stored, source: :stored) if stored.present?

    configured = configured_pin
    return Resolution.new(pin: configured, source: :configured) if configured.present?

    Resolution.new(pin: generate_pin, source: :generated)
  end

  private

  # The encrypted PIN already stored on THIS account's channel for this exact phone_number_id (reconnect reuse).
  def stored_pin
    setup = Bloomwire::WhatsappSetup.find_by(account_id: @account.id, phone_number_id: @phone_number_id)
    setup&.channel_whatsapp&.provider_config&.dig('verification_pin').presence
  end

  # A pre-seeded existing PIN for THIS phone_number_id, from the server env map only. Absent / blank / malformed
  # env => nil (so the caller falls through to a generated pin).
  def configured_pin
    configured_pins[@phone_number_id].presence
  end

  def configured_pins
    raw = ENV.fetch(EXISTING_PINS_ENV, nil)
    return {} if raw.blank?

    parsed = JSON.parse(raw)
    parsed.is_a?(Hash) ? parsed.transform_values(&:to_s) : {}
  rescue JSON::ParserError
    {}
  end

  def generate_pin
    format('%06d', SecureRandom.random_number(1_000_000))
  end
end
