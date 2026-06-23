# WhatsApp Cloud adapter for the generic channel-setup orchestrator
# (ADR 0005, 4.4-b-WA.2B). First implemented vertical.
#
# It isolates ALL WhatsApp-specific concerns so the orchestrator and the
# BloomwireChannelIntegration model stay channel-agnostic:
# - which request params are accepted/required,
# - how a Channel::Whatsapp + Inbox are created (reusing the existing Chatwoot
#   Whatsapp::ChannelCreationService rather than duplicating it),
# - how the routing key is derived (Meta phone_number_id),
# - which NON-SECRET routing fields land on the ownership row.
#
# Secrets (api_key/access token) stay in Channel::Whatsapp#provider_config and are
# never returned to the orchestrator or copied into the ownership table.
class Bloomwire::ChannelSetup::WhatsappAdapter
  REQUIRED_PARAMS = %i[phone_number phone_number_id business_account_id api_key].freeze
  PERMITTED_PARAMS = %i[phone_number phone_number_id business_account_id api_key business_name].freeze

  def app_kind
    'whatsapp'
  end

  # Strong-params allowlist the platform controller uses for this channel kind.
  def permitted_params
    PERMITTED_PARAMS
  end

  # Routing key derived from the RAW request params so the orchestrator can detect
  # duplicates before any channel is created. For WhatsApp this is the Meta
  # phone_number_id.
  def routing_key(params)
    params[:phone_number_id].presence
  end

  # Creates the Channel::Whatsapp + Inbox via the existing Chatwoot service.
  # Channel-specific failures are translated into a coded SetupError so the
  # orchestrator never has to know about WhatsApp/Meta error shapes.
  def create_channel(account:, params:)
    raise Bloomwire::ChannelSetup::SetupError, :invalid_channel_params if missing_required?(params)
    raise Bloomwire::ChannelSetup::SetupError, :duplicate_phone_number if phone_number_taken?(params)

    Whatsapp::ChannelCreationService.new(account, waba_info(params), phone_info(params), params[:api_key]).perform
  rescue ArgumentError
    raise Bloomwire::ChannelSetup::SetupError, :invalid_channel_params
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique, RuntimeError => e
    # A concurrent setup can insert the same phone number between the pre-check
    # above and this create. The reused Chatwoot service then raises a RuntimeError
    # (its own phone-exists guard) or RecordInvalid/RecordNotUnique (the unique phone
    # index). Re-check and translate that race into the same safe coded error as the
    # pre-check, rather than leaking a raw exception.
    raise Bloomwire::ChannelSetup::SetupError, :duplicate_phone_number if phone_number_taken?(params)
    raise Bloomwire::ChannelSetup::SetupError, :invalid_channel_params if e.is_a?(ActiveRecord::RecordInvalid)

    raise
  end

  # Provider-side step run by the orchestrator AFTER the channel + inbox + ownership
  # row are committed. WhatsApp channels are created through
  # Whatsapp::ChannelCreationService, which tags provider_config['source'] =
  # 'embedded_signup'; that suppresses Channel::Whatsapp's after_commit webhook
  # auto-setup, so we register the webhook explicitly here — exactly as
  # Whatsapp::EmbeddedSignupService does. setup_webhooks handles its own provider
  # errors (logs + prompts reauthorization) and does not raise.
  def post_create!(channel)
    channel.setup_webhooks
  end

  # NON-SECRET routing metadata read back from the persisted channel. These keys
  # map 1:1 to BloomwireChannelIntegration columns; no secrets are included.
  def integration_attributes(channel)
    config = channel.provider_config || {}
    {
      provider: channel.provider,
      phone_number: channel.phone_number,
      phone_number_id: config['phone_number_id'],
      business_account_id: config['business_account_id'],
      routing_key: config['phone_number_id']
    }
  end

  private

  def missing_required?(params)
    REQUIRED_PARAMS.any? { |key| params[key].blank? }
  end

  def phone_number_taken?(params)
    Channel::Whatsapp.exists?(phone_number: params[:phone_number])
  end

  # Chatwoot's Whatsapp::ChannelCreationService stores business_account_id under
  # waba_id; we map our generic business_account_id input onto it.
  def waba_info(params)
    { waba_id: params[:business_account_id], business_name: params[:business_name] }
  end

  def phone_info(params)
    {
      phone_number: params[:phone_number],
      phone_number_id: params[:phone_number_id],
      business_name: params[:business_name]
    }
  end
end
