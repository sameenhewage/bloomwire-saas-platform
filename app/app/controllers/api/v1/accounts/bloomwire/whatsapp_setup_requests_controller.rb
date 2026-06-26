# Phase 11A: account-level managed WhatsApp setup request intake. Business/account ADMINS can request managed
# WhatsApp setup and view their current request. Inert (404) when Bloomwire mode is OFF (stock Chatwoot).
# Scoped to Current.account (no cross-account access); admin-only (agents are blocked). No secrets are accepted
# from params or rendered — the request record holds only non-secret intake fields.
class Api::V1::Accounts::Bloomwire::WhatsappSetupRequestsController < Api::V1::Accounts::BaseController
  before_action :ensure_bloomwire_mode_enabled!
  before_action :check_admin_authorization?

  def index
    requests = ::Bloomwire::WhatsappSetupRequest.where(account_id: Current.account.id).order(created_at: :desc)
    render json: requests.map { |request| request_json(request) }
  end

  def create
    request = ::Bloomwire::WhatsappSetupRequest.request_for(account: Current.account, requested_by: Current.user)
    render json: request_json(request)
  end

  private

  # Inert when the Bloomwire layer is OFF: behaves as if the surface does not exist (stock Chatwoot unchanged).
  def ensure_bloomwire_mode_enabled!
    head :not_found unless ::Bloomwire::Features.master_enabled?
  end

  # Safe DTO: only non-secret operational status fields (no internal IDs). No provider_config / api_key / token is ever stored or returned.
  def request_json(request)
    {
      status: request.status,
      status_reason: request.status_reason,
      completed_at: request.completed_at,
      created_at: request.created_at,
      updated_at: request.updated_at
    }
  end
end
