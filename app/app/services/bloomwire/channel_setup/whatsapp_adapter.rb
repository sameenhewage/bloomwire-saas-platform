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
class Bloomwire::ChannelSetup::WhatsappAdapter < Bloomwire::ChannelSetup::BaseAdapter
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

    duplicate = duplicate_code(params)
    raise Bloomwire::ChannelSetup::SetupError, duplicate if duplicate

    Whatsapp::ChannelCreationService.new(account, waba_info(params), phone_info(params), params[:api_key]).perform
  rescue ArgumentError
    raise Bloomwire::ChannelSetup::SetupError, :invalid_channel_params
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique, RuntimeError => e
    # A concurrent setup can insert the same phone number / phone_number_id between the
    # pre-checks above and this create (the unique phone index, or the reused Chatwoot
    # service's own RuntimeError phone-exists guard). Re-check and translate that race
    # into the same safe coded error as the pre-checks, not a leaked raw exception.
    duplicate = duplicate_code(params)
    raise Bloomwire::ChannelSetup::SetupError, duplicate if duplicate
    raise Bloomwire::ChannelSetup::SetupError, :invalid_channel_params if e.is_a?(ActiveRecord::RecordInvalid)

    raise
  end

  # Overrides BaseAdapter#post_create! (the default no-op). Provider-side registration
  # run by the orchestrator AFTER the channel + inbox + ownership row commit.
  #
  # We call Whatsapp::WebhookSetupService directly and let failures SURFACE, instead of
  # Channel::Whatsapp#setup_webhooks (which rescues StandardError, only logs, and prompts
  # reauthorization). If Meta rejects the webhook subscription the service raises; we
  # translate that into :webhook_setup_failed so the orchestrator keeps the integration
  # PENDING (retryable) and never reports success/active on a failed registration.
  # (ChannelCreationService tags provider_config['source'] = 'embedded_signup', so the
  # model's after_commit auto-setup is skipped and this is the only registration path.)
  def post_create!(channel)
    config = channel.provider_config || {}
    Whatsapp::WebhookSetupService.new(channel, config['business_account_id'], config['api_key']).perform
  rescue StandardError => e
    Rails.logger.error("[BLOOMWIRE] WhatsApp webhook registration failed: #{e.message}")
    raise Bloomwire::ChannelSetup::SetupError, :webhook_setup_failed
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

  # The two Chatwoot source-of-truth duplicate checks, in priority order. Returns the
  # coded error (or nil) so create_channel applies it identically on the pre-check and
  # on a concurrent-insert race.
  def duplicate_code(params)
    return :duplicate_phone_number if phone_number_taken?(params)
    return :duplicate_phone_number_id if phone_number_id_taken?(params)

    nil
  end

  def phone_number_taken?(params)
    Channel::Whatsapp.exists?(phone_number: params[:phone_number])
  end

  # Chatwoot SOURCE-OF-TRUTH dedupe (ADR 0005): the same Meta phone_number_id may
  # already back a Channel::Whatsapp created via the still-enabled tenant setup path
  # (or before the ownership backfill) — with NO BloomwireChannelIntegration row and
  # possibly a differently formatted phone_number. phone_number_id is the canonical
  # Meta identifier, so we dedupe on it directly against provider_config rather than
  # relying on the phone-number text or the ownership table alone.
  def phone_number_id_taken?(params)
    phone_number_id = params[:phone_number_id]
    return false if phone_number_id.blank?

    Channel::Whatsapp.exists?(["provider_config ->> 'phone_number_id' = ?", phone_number_id])
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
