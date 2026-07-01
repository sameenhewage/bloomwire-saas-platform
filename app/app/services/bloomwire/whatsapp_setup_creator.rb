# Phase 17C.1: create/update the internal, NON-SECRET Bloomwire::WhatsappSetup router mapping AFTER a customer
# WhatsApp channel + inbox already exist (created by the customer Add-Inbox wizard in a later slice). This is the
# single seam that turns an existing channel/inbox into a router-resolvable mapping.
#
# Boundary (do not weaken):
# - Accepts ONLY explicit, non-secret routing identifiers (phone_number_id / waba_id / display_phone_number) +
#   the setup_status. It NEVER accepts or stores api_key / access token / provider_config / any secret — those
#   live solely on Channel::Whatsapp#provider_config (ADR-0006).
# - Creates NO account / user / inbox / channel and makes NO Meta/WhatsApp call.
# - Cross-account safe: the inbox and channel must belong to the given account, and the inbox must be that
#   channel's own inbox (mirrors the model validations, failing fast with a safe symbol error).
# - Idempotent per channel_whatsapp_id (find_or_initialize). A phone_number_id already claimed by a DIFFERENT
#   channel fails closed (:phone_number_id_conflict) — never silently re-points another account's routing.
class Bloomwire::WhatsappSetupCreator
  # Safe result: `error` is a symbol NAME only (never a value/secret); success? when no error.
  Result = Struct.new(:setup, :error, keyword_init: true) do
    def success?
      error.nil?
    end
  end

  def self.call(**)
    new(**).call
  end

  # rubocop:disable Metrics/ParameterLists -- explicit, named, non-secret inputs are the intended interface
  def initialize(account:, inbox:, channel_whatsapp:, phone_number_id:, waba_id: nil,
                 display_phone_number: nil, setup_status: Bloomwire::WhatsappSetup::ROUTEABLE_STATUS)
    @account = account
    @inbox = inbox
    @channel = channel_whatsapp
    @phone_number_id = phone_number_id.to_s.strip.presence
    @waba_id = waba_id.to_s.strip.presence
    @display_phone_number = display_phone_number.to_s.strip.presence
    @setup_status = setup_status.presence || Bloomwire::WhatsappSetup::ROUTEABLE_STATUS
  end
  # rubocop:enable Metrics/ParameterLists

  def call
    validation_error = validate
    return Result.new(error: validation_error) if validation_error

    setup = Bloomwire::WhatsappSetup.find_or_initialize_by(channel_whatsapp_id: @channel.id)
    setup.assign_attributes(
      account_id: @account.id,
      inbox_id: @inbox.id,
      phone_number_id: @phone_number_id,
      waba_id: @waba_id,
      display_phone_number: @display_phone_number,
      setup_status: @setup_status
    )
    return Result.new(error: :invalid_setup) unless setup.save

    Result.new(setup: setup)
  rescue ActiveRecord::RecordNotUnique
    Result.new(error: :phone_number_id_conflict)
  end

  private

  def validate
    return :missing_phone_number_id if @phone_number_id.blank?
    return :account_mismatch unless same_account?(@inbox)
    return :channel_account_mismatch unless same_account?(@channel)
    return :channel_inbox_mismatch unless inbox_owns_channel?
    return :phone_number_id_conflict if conflicting_phone_number_id?

    nil
  end

  # The record (inbox / channel) must exist and belong to the given account (cross-tenant guard).
  def same_account?(record)
    record.present? && record.account_id == @account&.id
  end

  # The inbox must be this WhatsApp channel's own inbox (no mixed inbox/channel). Only reached after both the
  # inbox and channel are confirmed present + same-account, so they are safe to dereference here.
  def inbox_owns_channel?
    @inbox.channel_type == 'Channel::Whatsapp' && @inbox.channel_id == @channel.id
  end

  # A DIFFERENT existing setup already claims this phone_number_id (partial-unique index) => fail closed.
  def conflicting_phone_number_id?
    Bloomwire::WhatsappSetup
      .where(phone_number_id: @phone_number_id)
      .where.not(channel_whatsapp_id: @channel.id)
      .exists?
  end
end
