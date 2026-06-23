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
    duplicate_phone_number: 'A channel with this phone number already exists.',
    duplicate_routing_key: 'A channel with this routing identifier already exists.',
    duplicate_integration: 'This inbox already has a Bloomwire channel integration.',
    integration_invalid: 'Could not record the channel integration.'
  }.freeze

  ERROR_STATUSES = {
    unauthorized: :forbidden,
    account_not_found: :not_found
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
    return {} if params[:channel].blank?

    params.require(:channel).permit(*permitted_channel_keys).to_h.symbolize_keys
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

  # Safe, platform-side DTO: ownership + NON-SECRET routing metadata only. No
  # provider_config / api_key / tokens are ever included.
  def integration_dto(integration)
    {
      id: integration.id,
      account_id: integration.account_id,
      inbox_id: integration.inbox_id,
      app_kind: integration.app_kind,
      provider: integration.provider,
      status: integration.status,
      managed_by_bloomwire: integration.managed_by_bloomwire,
      phone_number: integration.phone_number,
      phone_number_id: integration.phone_number_id,
      business_account_id: integration.business_account_id,
      routing_key: integration.routing_key
    }
  end
end
