# Phase 17C.2: dedicated customer WhatsApp Embedded Signup endpoint (managed self-serve). Admin-only; inert
# (404) unless Bloomwire managed mode + managed_whatsapp_onboarding feature + native WhatsApp restricted (the
# feature half of canSelfServeManagedWhatsapp; the admin half is check_admin_authorization?). Scoped to
# Current.account (no cross-account). Delegates to Bloomwire::WhatsappEmbeddedSignupService, which uses the
# GLOBAL webhook router (app-to-WABA subscription only) and never touches native /whatsapp/authorization.
# Returns a safe DTO only; errors are sanitized generic messages (never raw Meta payloads / secrets).
class Api::V1::Accounts::Bloomwire::Whatsapp::EmbeddedSignupsController < Api::V1::Accounts::BaseController
  before_action :ensure_managed_whatsapp_self_serve!
  before_action :check_admin_authorization?

  SAFE_ERROR_MESSAGES = {
    missing_code: 'A Meta authorization code is required.',
    missing_waba_id: 'A WhatsApp Business Account is required.',
    not_ready: 'WhatsApp platform configuration is incomplete. Please contact your administrator.',
    encryption_not_configured: 'Secure credential storage is not configured. Please contact your administrator.',
    phone_number_taken: 'This WhatsApp phone number is already connected.',
    number_not_connected: 'This WhatsApp number is not connected on Meta yet. Connect it in WhatsApp Manager, then try again.',
    no_connected_registration: 'This WhatsApp number is not connected on Meta yet. Connect it in WhatsApp Manager, then try again.',
    ambiguous_connected_registration: 'This number is connected under multiple WhatsApp Business Accounts. Remove the duplicate, then try again.',
    cross_business_registration: 'This number is connected under a different business. Connect it under your own account, then try again.',
    meta_error: 'We could not complete WhatsApp setup with Meta. Please try again.'
  }.freeze

  def create
    result = ::Bloomwire::WhatsappEmbeddedSignupService.new(
      account: Current.account, params: embedded_signup_params
    ).perform

    if result.success?
      render json: result.dto, status: :created
    else
      render json: { error: safe_message(result.error), code: result.error }, status: error_status(result.error)
    end
  end

  private

  def embedded_signup_params
    params.permit(:code, :business_id, :waba_id, :phone_number_id, :display_phone_number).to_h.symbolize_keys
  end

  def ensure_managed_whatsapp_self_serve!
    return if ::Bloomwire::Features.restrict_native_whatsapp_setup? &&
              ::Bloomwire::Features.enabled?(:managed_whatsapp_onboarding)

    head :not_found
  end

  # Generic, non-secret messages only (never a raw Meta payload). `code` is the safe symbol name.
  def safe_message(error)
    SAFE_ERROR_MESSAGES.fetch(error, 'Could not complete WhatsApp setup. Please try again.')
  end

  def error_status(error)
    error == :meta_error ? :bad_gateway : :unprocessable_entity
  end
end
