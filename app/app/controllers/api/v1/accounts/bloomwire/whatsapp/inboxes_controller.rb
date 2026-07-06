# Admin-facing "Remove WhatsApp Inbox" deprovision endpoint (managed mode). Admin-only; inert (404) unless managed
# WhatsApp self-serve is active; strictly account-scoped (an inbox is only ever resolved from Current.account, so a
# cross-account id 404s). The request path is SHORT: it authorizes, verifies account + managed source, blocks routing,
# and enqueues a retry-safe/idempotent background job (Bloomwire::WhatsappInboxDeprovisionService#prepare); the heavy
# purge runs off-request. Returns a SAFE, ACCEPTED response only — never the phone number, phone_number_id, WABA id,
# or any credential.
#
# This is a DEDICATED path; it does NOT weaken the stock InboxesController destroy guard
# (restrict_managed_provider_inbox_destroy!), which still blocks deleting managed inboxes via the generic route.
class Api::V1::Accounts::Bloomwire::Whatsapp::InboxesController < Api::V1::Accounts::BaseController
  before_action :ensure_managed_whatsapp_self_serve!
  before_action :check_admin_authorization?

  SAFE_ERRORS = {
    not_whatsapp: 'This inbox is not a WhatsApp inbox.',
    not_managed: 'This WhatsApp inbox is not managed by Bloomwire and cannot be removed here.'
  }.freeze

  def destroy
    inbox = Current.account.inboxes.find_by(id: params[:id])
    # Idempotent: an already-removed (or cross-account) inbox is simply gone.
    return render_gone if inbox.nil?

    result = ::Bloomwire::WhatsappInboxDeprovisionService.new(
      account: Current.account, inbox: inbox, actor: Current.user
    ).prepare

    if result.success?
      # 202: routing is blocked and the deletion has been enqueued; the heavy purge completes asynchronously.
      render json: { status: 'removal_started' }, status: :accepted
    elsif result.error == :not_found
      render_gone
    else
      render json: { error: SAFE_ERRORS.fetch(result.error, 'Could not remove this inbox.'), code: result.error },
             status: :unprocessable_entity
    end
  end

  private

  def render_gone
    render json: { error: 'This WhatsApp inbox no longer exists.', code: 'not_found' }, status: :not_found
  end

  def ensure_managed_whatsapp_self_serve!
    return if ::Bloomwire::Features.restrict_native_whatsapp_setup? &&
              ::Bloomwire::Features.enabled?(:managed_whatsapp_onboarding)

    head :not_found
  end
end
