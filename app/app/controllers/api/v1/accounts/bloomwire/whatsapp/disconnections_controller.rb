# WhatsWay-parity "Disconnect" endpoint for a managed WhatsApp inbox: deregister the number on Meta (status ->
# DISCONNECTED) and mark the setup non-routeable while KEEPING the Channel/Inbox/Setup records, so a later Embedded
# Signup reconnect reuses them and re-registers. Admin-only and inert (404) unless managed self-serve is active
# (mirrors MessagingCapabilitiesController). Scoped to Current.account (no cross-account). Delegates to
# Bloomwire::WhatsappDisconnectService (Meta /deregister is non-fatal; never /delete, never a webhook unsubscribe).
# Returns a safe DTO only (ids/status) — never a secret.
class Api::V1::Accounts::Bloomwire::Whatsapp::DisconnectionsController < Api::V1::Accounts::BaseController
  before_action :ensure_managed_whatsapp_self_serve!
  before_action :check_admin_authorization?

  SAFE_ERROR_MESSAGES = {
    not_found: 'This WhatsApp inbox could not be found.',
    not_whatsapp: 'This inbox is not a WhatsApp inbox.'
  }.freeze

  # POST .../bloomwire/whatsapp/disconnections  (body: { inbox_id: }).
  def create
    inbox = Current.account.inboxes.find_by(id: params[:inbox_id])
    result = ::Bloomwire::WhatsappDisconnectService.new(
      account: Current.account, inbox: inbox, actor: Current.user
    ).perform

    if result.success?
      render json: disconnect_dto(result.setup, inbox), status: :ok
    else
      render json: { error: safe_message(result.error), code: result.error }, status: error_status(result.error)
    end
  end

  private

  # Same gate as the customer Embedded Signup + messaging_capabilities endpoints: inert (404) unless Bloomwire
  # managed mode + managed WhatsApp onboarding + native WhatsApp restricted (the admin half is check_admin_authorization?).
  def ensure_managed_whatsapp_self_serve!
    return if ::Bloomwire::Features.restrict_native_whatsapp_setup? &&
              ::Bloomwire::Features.enabled?(:managed_whatsapp_onboarding)

    head :not_found
  end

  # Safe DTO — ids/status only; NEVER api_key / token / provider_config / phone / WABA / Meta payload.
  def disconnect_dto(setup, inbox)
    {
      managed: true,
      disconnected: true,
      inbox: { id: inbox&.id, name: inbox&.name },
      setup: setup ? { id: setup.id, status: setup.setup_status } : nil
    }
  end

  # Generic, non-secret messages only. `code` is the safe symbol name.
  def safe_message(error)
    SAFE_ERROR_MESSAGES.fetch(error, 'Could not disconnect this WhatsApp inbox. Please try again.')
  end

  def error_status(error)
    error == :not_found ? :not_found : :unprocessable_entity
  end
end
