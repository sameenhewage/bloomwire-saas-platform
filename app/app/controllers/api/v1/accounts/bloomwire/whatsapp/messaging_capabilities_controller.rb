# Phase 5 (resume): re-verify outbound messaging capability for an existing managed WhatsApp setup and, when the
# account owner has since granted the WABA asset task in Meta, promote it action_required -> ready_for_webhook.
# Admin-only and inert (404) unless managed self-serve is active (mirrors EmbeddedSignupsController). Scoped to
# Current.account (no cross-account). Delegates to Bloomwire::WhatsappCapabilityRecheck (verify-only; no /register,
# no duplicate, no second inbox). Returns a safe DTO only (ids/status/sanitized reason) — never a secret.
class Api::V1::Accounts::Bloomwire::Whatsapp::MessagingCapabilitiesController < Api::V1::Accounts::BaseController
  before_action :ensure_managed_whatsapp_self_serve!
  before_action :check_admin_authorization?

  SAFE_ERROR_MESSAGES = {
    not_found: 'This WhatsApp setup could not be found.',
    not_action_required: 'This WhatsApp inbox does not need an outbound-messaging recheck.',
    setup_incomplete: 'This WhatsApp setup is not fully configured. Please contact your administrator.',
    promote_failed: 'We could not finish enabling outbound messaging. Please try again.'
  }.freeze

  # PATCH .../bloomwire/whatsapp/messaging_capabilities/:id  (:id = Bloomwire::WhatsappSetup id).
  def update
    setup = Bloomwire::WhatsappSetup.find_by(id: params[:id], account_id: Current.account.id)
    result = ::Bloomwire::WhatsappCapabilityRecheck.new(setup: setup).perform

    if result.success?
      render json: capability_dto(result.setup, result.ready?), status: :ok
    else
      render json: { error: safe_message(result.error), code: result.error }, status: error_status(result.error)
    end
  end

  private

  # Same gate as the customer Embedded Signup endpoint: inert (404) unless Bloomwire managed mode + managed
  # WhatsApp onboarding + native WhatsApp restricted (the feature half; the admin half is check_admin_authorization?).
  def ensure_managed_whatsapp_self_serve!
    return if ::Bloomwire::Features.restrict_native_whatsapp_setup? &&
              ::Bloomwire::Features.enabled?(:managed_whatsapp_onboarding)

    head :not_found
  end

  # Safe DTO — ids/status + sanitized reason only; NEVER api_key / token / provider_config / raw actor id.
  def capability_dto(setup, ready)
    dto = {
      setup: { id: setup.id, status: setup.setup_status },
      inbox: { id: setup.inbox_id, name: setup.inbox&.name },
      ready: ready
    }
    unless ready
      dto[:action_required] = {
        reason: setup.status_reason,
        resolution: ::Bloomwire::WhatsappEmbeddedSignupService::OUTBOUND_ACTION_REQUIRED_RESOLUTION
      }
    end
    dto
  end

  # Generic, non-secret messages only (never a raw Meta payload). `code` is the safe symbol name.
  def safe_message(error)
    SAFE_ERROR_MESSAGES.fetch(error, 'Could not complete the outbound-messaging recheck. Please try again.')
  end

  def error_status(error)
    error == :not_found ? :not_found : :unprocessable_entity
  end
end
