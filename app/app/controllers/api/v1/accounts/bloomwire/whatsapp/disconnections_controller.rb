# "Disconnect" endpoint for a managed WhatsApp inbox. Delegates to Bloomwire::WhatsappDisconnectService, which is
# truthful about how the number is connected and NEVER marks local state disconnected without Meta proof:
# - Standard (Cloud API): deregister on Meta, verify DISCONNECTED, then mark the setup non-routeable while KEEPING
#   the Channel/Inbox/Setup records (a later Embedded Signup reconnect reuses them). Unverified -> 502, no change.
# - Coexistence: NO /deregister (offboarding is a mobile action in the WhatsApp Business app) -> 409 with the exact
#   mobile instructions; local state is left unchanged.
# Coexistence offboarding is NOT reconciled here: it is owned by Bloomwire::Webhooks::PartnerRemovalReconciler when
# Meta delivers the account_update / PARTNER_REMOVED webhook. This endpoint never infers offboarding from a GET.
# Admin-only and inert (404) unless managed self-serve is active (mirrors MessagingCapabilitiesController). Scoped
# to Current.account (no cross-account). Never /delete, never a webhook unsubscribe. Safe DTO only — never a secret.
class Api::V1::Accounts::Bloomwire::Whatsapp::DisconnectionsController < Api::V1::Accounts::BaseController
  before_action :ensure_managed_whatsapp_self_serve!
  before_action :check_admin_authorization?

  SAFE_ERROR_MESSAGES = {
    not_found: 'This WhatsApp inbox could not be found.',
    not_whatsapp: 'This inbox is not a WhatsApp inbox.',
    # We could not authoritatively confirm the number was disconnected at Meta, so nothing local was changed.
    disconnect_unverified: 'We could not confirm this number was disconnected at Meta. Nothing was changed — please try again.',
    # Coexistence numbers are offboarded from the phone, not the Cloud API. Copy names the EXACT mobile path; the
    # disconnect is then reconciled automatically when Meta notifies Bloomwire (account_update / PARTNER_REMOVED).
    mobile_action_required: 'This number is connected through the WhatsApp Business app. To disconnect it, open the ' \
                            'WhatsApp Business app and go to Settings → Account → Business Platform → Disconnect. ' \
                            'Your inbox is unchanged until Meta notifies Bloomwire, which then updates it ' \
                            'automatically; you can refresh the status here to check.'
  }.freeze

  # POST .../bloomwire/whatsapp/disconnections  (body: { inbox_id: }).
  def create
    inbox = Current.account.inboxes.find_by(id: params[:inbox_id])
    result = ::Bloomwire::WhatsappDisconnectService.new(
      account: Current.account, inbox: inbox, actor: Current.user
    ).perform

    render_result(result, inbox)
  end

  private

  def render_result(result, inbox)
    if result.success?
      render json: disconnect_dto(result.setup, inbox), status: :ok
    else
      render json: { error: safe_message(result.error), code: result.error }, status: error_status(result.error)
    end
  end

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

  # not_found -> 404; mobile_action_required -> 409 (the admin must act on the phone, not a client bug);
  # disconnect_unverified -> 502 (Meta could not confirm the change); everything else -> 422.
  def error_status(error)
    case error
    when :not_found then :not_found
    when :mobile_action_required then :conflict
    when :disconnect_unverified then :bad_gateway
    else :unprocessable_entity
    end
  end
end
