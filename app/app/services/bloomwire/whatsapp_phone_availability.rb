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
  # WhatsWay-parity Disconnect keeps the Channel/Inbox/Setup records (setup -> 'disconnected', deregistered on
  # Meta). A number whose ONLY WhatsApp channel(s) belong to the CURRENT account AND are DISCONNECTED is
  # RECONNECTABLE by this account — a later Embedded Signup reuses the SAME records — so it reports "available",
  # not "already_connected" (otherwise the wizard would block the very reconnect the disconnected panel invites).
  def self.status_for(raw, account: nil)
    normalized = normalize(raw)
    return AVAILABLE if normalized.blank?

    channels = Channel::Whatsapp.where(phone_number: normalized).to_a
    return AVAILABLE if channels.empty?
    return AVAILABLE if account && channels.all? { |channel| reconnectable_by_account?(channel, account) }

    ALREADY_CONNECTED
  end

  # Reconnectable only when the channel belongs to the given account AND its Bloomwire setup is DISCONNECTED. A
  # channel owned by another account, or one with an active/other-status (or no) setup, is NOT reconnectable here.
  def self.reconnectable_by_account?(channel, account)
    return false unless channel.account_id == account.id

    Bloomwire::WhatsappSetup.exists?(
      channel_whatsapp_id: channel.id, setup_status: Bloomwire::WhatsappSetup::DISCONNECTED_STATUS
    )
  end
  private_class_method :reconnectable_by_account?
end
