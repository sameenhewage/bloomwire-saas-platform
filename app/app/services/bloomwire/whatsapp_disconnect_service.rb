# WhatsWay-parity "Disconnect" for a managed WhatsApp inbox: deregister the number on Meta (its status becomes
# DISCONNECTED) and mark the Bloomwire::WhatsappSetup non-routeable (`disconnected`) while KEEPING the
# Channel/Inbox/Setup records, so a later Embedded Signup reconnect reuses the SAME records and re-registers.
#
# Boundary (do not weaken):
# - The Meta /deregister call is NON-FATAL (WhatsWay's disconnectChannel try/catch): a failure logs class-only and
#   the inbox is still disconnected locally (the owner can still reconnect). NEVER logs the token/phone/WABA.
# - Uses ONLY the channel's stored token and makes no other Meta call — the global router owns the shared WABA
#   webhook subscription, so a disconnect never unsubscribes it. Records are KEPT (this is NOT the delete flow).
# - Account-scoped: the inbox must belong to the given account and be a Channel::Whatsapp.
class Bloomwire::WhatsappDisconnectService
  EVENT = 'bloomwire.whatsapp.disconnect'.freeze

  Result = Struct.new(:setup, :error, keyword_init: true) do
    def success?
      error.nil?
    end
  end

  def initialize(account:, inbox:, actor: nil)
    @account = account
    @inbox = inbox
    @actor = actor
  end

  def perform
    return Result.new(error: :not_found) if @inbox.nil? || @inbox.account_id != @account.id

    channel = @inbox.channel
    return Result.new(error: :not_whatsapp) unless channel.is_a?(Channel::Whatsapp)

    deregister(channel)
    Result.new(setup: mark_disconnected(channel))
  end

  private

  # Meta /deregister — NON-FATAL (WhatsWay parity). A failure, or missing creds, still disconnects locally so the
  # owner can reconnect. Sanitized class-only log (never the token / phone_number_id / WABA / raw body).
  def deregister(channel)
    config = channel.provider_config.to_h
    phone_number_id = config['phone_number_id']
    token = config['api_key']
    return if phone_number_id.blank? || token.blank?

    Whatsapp::FacebookApiClient.new(token).deregister_phone_number(phone_number_id)
  rescue StandardError => e
    Rails.logger.warn(
      "[BLOOMWIRE WA DISCONNECT] #{{ event: EVENT, operation: 'deregister', exception_class: e.class.name }.to_json}"
    )
  end

  # Keep the records; mark the setup non-routeable so the global router (routes only ready_for_webhook) stops
  # immediately. Reconnect finds this SAME row by channel/phone_number_id and promotes it back to ready.
  def mark_disconnected(channel)
    setup = Bloomwire::WhatsappSetup.find_by(channel_whatsapp_id: channel.id)
    setup&.update!(setup_status: Bloomwire::WhatsappSetup::DISCONNECTED_STATUS, status_reason: nil)
    setup
  end
end
