# "Disconnect" endpoint for a managed WhatsApp inbox. Delegates to Bloomwire::WhatsappDisconnectService, which is
# truthful about how the number is connected and NEVER marks local state disconnected without Meta proof:
# - Standard (Cloud API): deregister on Meta, verify DISCONNECTED, then mark the setup non-routeable while KEEPING
#   the Channel/Inbox/Setup records (a later Embedded Signup reconnect reuses them). Unverified -> 502, no change.
# - Coexistence: NO /deregister (offboarding is a mobile action in the WhatsApp Business app) -> 409 with the exact
#   mobile instructions; local state is left unchanged.
# recheck (POST .../disconnections/recheck): the SINGLE Coexistence offboarding reconciliation owner. After the owner
# completes the mobile disconnect, it marks the preserved setup disconnected ONLY on authoritative Meta proof (200);
# still-connected -> 409, unverifiable -> 502, a Standard number -> 422 — always leaving state unchanged unless proven.
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
    # Coexistence numbers are offboarded from the phone, not the Cloud API. Copy names the EXACT mobile path so the
    # admin can complete it, then points to the Recheck action (the reconciliation owner) that confirms with Meta.
    mobile_action_required: 'This number is connected through the WhatsApp Business app. To disconnect it, open the ' \
                            'WhatsApp Business app and go to Settings → Account → Business Platform → Disconnect. ' \
                            'Then use Recheck here and Bloomwire will confirm with Meta; your inbox is unchanged until ' \
                            'Meta confirms the change.',
    # Recheck ran but Meta still reports the number connected — the mobile disconnect has not completed yet.
    still_connected: 'This number is still connected at Meta. Complete the disconnect in the WhatsApp Business app ' \
                     '(Settings → Account → Business Platform → Disconnect), then try Recheck again.',
    # We could not read the authoritative Meta status, so nothing local was changed.
    recheck_unverified: 'We could not confirm this number\'s status at Meta. Nothing was changed — please try again.',
    # Recheck is only for Coexistence numbers; a Standard number disconnects via the deregister flow.
    not_coexistence: 'This number is not connected through the WhatsApp Business app, so there is nothing to recheck.'
  }.freeze

  # POST .../bloomwire/whatsapp/disconnections  (body: { inbox_id: }).
  def create
    inbox = Current.account.inboxes.find_by(id: params[:inbox_id])
    result = ::Bloomwire::WhatsappDisconnectService.new(
      account: Current.account, inbox: inbox, actor: Current.user
    ).perform

    render_result(result, inbox)
  end

  # POST .../bloomwire/whatsapp/disconnections/recheck  (body: { inbox_id: }). Coexistence offboarding
  # reconciliation: mark the preserved setup disconnected ONLY on authoritative Meta proof; otherwise leave it.
  def recheck
    inbox = Current.account.inboxes.find_by(id: params[:inbox_id])
    result = ::Bloomwire::WhatsappDisconnectService.new(
      account: Current.account, inbox: inbox, actor: Current.user
    ).recheck

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

  # not_found -> 404; mobile_action_required / still_connected -> 409 (the admin must act on the phone, not a client
  # bug); disconnect_unverified / recheck_unverified -> 502 (Meta could not confirm the change); everything else -> 422.
  def error_status(error)
    case error
    when :not_found then :not_found
    when :mobile_action_required, :still_connected then :conflict
    when :disconnect_unverified, :recheck_unverified then :bad_gateway
    else :unprocessable_entity
    end
  end
end
