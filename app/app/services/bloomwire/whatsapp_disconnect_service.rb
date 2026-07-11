# "Disconnect" for a managed WhatsApp inbox. The behavior depends on how the number is connected, and local state
# is NEVER marked disconnected without authoritative Meta proof (no false "disconnected"):
#
# - Coexistence (number lives in the owner's WhatsApp Business app): there is NO Cloud API /deregister for a
#   coexistence number — offboarding is a MOBILE action the owner performs in the app (Settings → Account →
#   Business Platform → Disconnect). #perform makes NO Meta call and changes NO local state; it returns
#   :mobile_action_required so the caller can show the exact mobile instructions. The offboarding is reconciled by
#   the AUTHORITATIVE owner Bloomwire::Webhooks::PartnerRemovalReconciler when Meta delivers the account_update /
#   PARTNER_REMOVED webhook (the Solution Partner was removed from the WABA). This service NEVER infers offboarding
#   from the inverse of an onboarding-readiness GET, so it can never produce a false local disconnect.
# - Standard (Cloud API): deregister the number on Meta and only mark the Bloomwire::WhatsappSetup non-routeable
#   (`disconnected`) AFTER Meta authoritatively reports the number DISCONNECTED. An already-DISCONNECTED number is
#   reconciled without a duplicate deregister. Any failure or unverifiable state returns :disconnect_unverified and
#   leaves every record untouched (no false local disconnect).
#
# Boundary (do not weaken):
# - Uses ONLY the channel's stored token and makes no other Meta call — the global router owns the shared WABA
#   webhook subscription, so a disconnect never unsubscribes it. Records are KEPT (this is NOT the delete flow).
# - A deregister/verify failure NEVER logs the token/phone/WABA/raw body (sanitized class-only log).
# - Account-scoped: the inbox must belong to the given account and be a Channel::Whatsapp.
class Bloomwire::WhatsappDisconnectService
  EVENT = 'bloomwire.whatsapp.disconnect'.freeze
  DISCONNECTED_META_STATUS = 'DISCONNECTED'.freeze

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

    setup = find_setup(channel)
    # Coexistence: never touch Meta and never change local state — the owner disconnects from the mobile app and
    # Meta confirms it via the account_update / PARTNER_REMOVED webhook (reconciled by PartnerRemovalReconciler).
    # Surface the mobile action so nothing here is silently (and falsely) marked disconnected.
    return Result.new(setup: setup, error: :mobile_action_required) if coexistence?(channel)

    disconnect_standard(channel, setup)
  end

  private

  def coexistence?(channel)
    channel.provider_config.to_h['connection_mode'].to_s == 'coexistence'
  end

  def find_setup(channel)
    Bloomwire::WhatsappSetup.find_by(channel_whatsapp_id: channel.id)
  end

  # Standard (Cloud API) disconnect: only mark the setup disconnected once Meta authoritatively confirms it. Any
  # missing creds, deregister failure, or unverified status leaves the records untouched (truthful, not a false
  # local disconnect). A deregister exception is sanitized (class-only) and never leaks the stored token.
  def disconnect_standard(channel, setup)
    config = channel.provider_config.to_h
    phone_number_id = config['phone_number_id']
    token = config['api_key']
    return Result.new(setup: setup, error: :disconnect_unverified) if phone_number_id.blank? || token.blank?

    client = Whatsapp::FacebookApiClient.new(token)
    return Result.new(setup: mark_disconnected(setup)) if deregistered?(client, phone_number_id)

    Result.new(setup: setup, error: :disconnect_unverified)
  rescue StandardError => e
    log_failure(e, operation: 'deregister')
    Result.new(setup: setup, error: :disconnect_unverified)
  end

  # True only once Meta authoritatively reports DISCONNECTED. If it is already DISCONNECTED, reconcile without a
  # duplicate deregister; otherwise deregister once, then RE-READ the authoritative status to verify.
  def deregistered?(client, phone_number_id)
    return true if client.phone_number_status(phone_number_id) == DISCONNECTED_META_STATUS

    client.deregister_phone_number(phone_number_id)
    client.phone_number_status(phone_number_id) == DISCONNECTED_META_STATUS
  end

  # Keep the records; mark the setup non-routeable so the global router (routes only ready_for_webhook) stops
  # immediately. Reconnect finds this SAME row by channel/phone_number_id and promotes it back to ready.
  def mark_disconnected(setup)
    setup&.update!(setup_status: Bloomwire::WhatsappSetup::DISCONNECTED_STATUS, status_reason: nil)
    setup
  end

  def log_failure(error, operation: 'deregister')
    Rails.logger.warn(
      "[BLOOMWIRE WA DISCONNECT] #{{ event: EVENT, operation: operation, exception_class: error.class.name }.to_json}"
    )
  end
end
