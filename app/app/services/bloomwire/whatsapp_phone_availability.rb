# Advisory duplicate-number preflight for the managed WhatsApp onboarding wizard.
#
# Given a customer-typed WhatsApp number, reports ONLY whether that number is already connected in Bloomwire so
# the UI can warn BEFORE opening the Meta Embedded Signup popup. This is advisory: the authoritative duplicate
# guard still runs after the Meta callback (Meta may confirm a different number than the one typed).
#
# SECURITY CONTRACT (do not weaken): returns ONLY the enum "available" / "already_connected". It NEVER returns or
# exposes the owning account/inbox/channel id or name, phone_number_id, WABA id, or any credential — so it cannot
# leak another tenant's details even though the underlying uniqueness is global.
class Bloomwire::WhatsappPhoneAvailability
  AVAILABLE = 'available'.freeze
  ALREADY_CONNECTED = 'already_connected'.freeze

  # Normalizes to the SAME shape Channel::Whatsapp stores ("+<digits>", per Whatsapp::PhoneInfoService), so the
  # check mirrors the authoritative global uniqueness guard (unique index on Channel::Whatsapp#phone_number).
  def self.normalize(raw)
    digits = raw.to_s.gsub(/\D/, '')
    digits.blank? ? '' : "+#{digits}"
  end

  # Global check (matches the authoritative guard); blank input is treated as "available" (nothing to warn about).
  def self.status_for(raw)
    normalized = normalize(raw)
    return AVAILABLE if normalized.blank?

    Channel::Whatsapp.exists?(phone_number: normalized) ? ALREADY_CONNECTED : AVAILABLE
  end
end
