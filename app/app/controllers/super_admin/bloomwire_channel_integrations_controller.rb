# Platform-context Bloomwire Admin endpoint for external-channel setup
# (ADR 0005, 4.4-b-WA.2B). Generic by design: `app_kind` selects the adapter, so
# the same route serves future channels (SMS/Email/Instagram/Shopify). WhatsApp is
# the first supported kind.
#
# Authentication is the SuperAdmin Devise session (inherited from
# SuperAdmin::ApplicationController#authenticate_super_admin!), so Dialog tenant
# users cannot reach it. Responses are a SAFE DTO only — never raw
# provider_config / API keys / tokens.
class SuperAdmin::BloomwireChannelIntegrationsController < SuperAdmin::ApplicationController
  # Safe, non-identifying error messages (no raw ids/credentials), mirroring the
  # SuperAdmin::BloomwireBusinessProfilesController#activate convention.
  ERROR_MESSAGES = {
    unauthorized: 'Not authorized to configure external channels.',
    account_not_found: 'Tenant account not found.',
    profile_not_found: 'Cannot set up a channel: this tenant has no Bloomwire profile.',
    unsupported_app_kind: 'Unsupported channel type.',
    invalid_channel_params: 'Missing or invalid channel parameters.',
    phone_metadata_unverifiable: 'Could not verify the WhatsApp phone number with Meta. Check the WhatsApp Business Account ID and access token.',
    phone_number_id_mismatch: 'The WhatsApp phone number ID was not found in the supplied WhatsApp Business Account.',
    phone_number_mismatch: 'The submitted phone number does not match the supplied WhatsApp phone number ID.',
    duplicate_phone_number: 'A channel with this phone number already exists.',
    duplicate_phone_number_id: 'A channel with this WhatsApp phone number ID already exists.',
    duplicate_routing_key: 'A channel with this routing identifier already exists.',
    duplicate_integration: 'This inbox already has a Bloomwire channel integration.',
    webhook_setup_failed: 'Provider webhook registration failed; the channel setup is pending. Retry to complete it.',
    integration_invalid: 'Could not record the channel integration.'
  }.freeze

  ERROR_STATUSES = {
    unauthorized: :forbidden,
    account_not_found: :not_found,
    webhook_setup_failed: :bad_gateway
  }.freeze

  def create
    account = Account.find_by(id: params[:account_id])
    return render_error(:account_not_found) if account.nil?

    result = Bloomwire::ChannelSetup::Service.new(
      actor: current_super_admin,
      account: account,
      app_kind: params[:app_kind],
      params: channel_params
    ).perform

    return render(json: integration_dto(result.integration), status: :created) if result.success?

    render_error(result.error)
  end

  private

  def channel_params
    channel = params[:channel]
    # A malformed payload (channel sent as a JSON string/array/scalar) is not a
    # parameter object and cannot be permitted. Treat it as empty so the adapter's
    # required-param check returns a safe :invalid_channel_params (422) instead of
    # letting .permit raise and surface a 500.
    return {} unless channel.respond_to?(:permit)

    channel.permit(*permitted_channel_keys).to_h.symbolize_keys
  end

  # Each adapter declares the params it accepts, keeping the controller generic.
  def permitted_channel_keys
    adapter = Bloomwire::ChannelSetup::Service.adapter_for(params[:app_kind])
    adapter ? adapter.permitted_params : []
  end

  def render_error(code)
    render json: { error: ERROR_MESSAGES.fetch(code, 'Channel setup failed.') },
           status: ERROR_STATUSES.fetch(code, :unprocessable_entity)
  end

  # Minimal, safe SuperAdmin DTO (ADR 0005 security gate). A browser/API response
  # must NOT carry raw phone numbers, Meta vendor identifiers (phone_number_id,
  # business_account_id, routing_key), provider_config, credentials, or raw DB ids.
  # We return setup-confirmation fields only, plus a MASKED phone for human display.
  def integration_dto(integration)
    {
      app_kind: integration.app_kind,
      provider: integration.provider,
      status: integration.status,
      managed_by_bloomwire: integration.managed_by_bloomwire,
      phone_number_masked: masked_phone(integration.phone_number)
    }
  end

  # Last 4 digits only, so the operator can confirm which number was configured
  # without the response exposing the raw E.164 number.
  def masked_phone(phone_number)
    digits = phone_number.to_s.gsub(/\D/, '')
    return nil if digits.empty?

    "\u2022\u2022\u2022\u2022#{digits.last(4)}"
  end
end
