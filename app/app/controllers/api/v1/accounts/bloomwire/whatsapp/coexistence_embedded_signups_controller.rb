# Phase 17D.1: dedicated customer WhatsApp Business App Coexistence endpoint
# (POST /api/v1/accounts/:account_id/bloomwire/whatsapp/coexistence_embedded_signup).
# Admin-only; inert (404) unless managed WhatsApp self-serve is active. Delegates to the dedicated Coexistence
# service, which marks connection_mode=coexistence and keeps the same safe DTO / global-router-only contract as
# 17C.2. This is the BACKEND contract only — the Coexistence UI card stays disabled/"Coming soon" until a later
# frontend phase (17D.3). Never touches native /whatsapp/authorization.
class Api::V1::Accounts::Bloomwire::Whatsapp::CoexistenceEmbeddedSignupsController < Api::V1::Accounts::BaseController
  before_action :ensure_managed_whatsapp_self_serve!
  before_action :check_admin_authorization?

  SAFE_ERROR_MESSAGES = {
    missing_code: 'A Meta authorization code is required.',
    missing_waba_id: 'A WhatsApp Business Account is required.',
    not_ready: 'WhatsApp platform configuration is incomplete. Please contact your administrator.',
    encryption_not_configured: 'Secure credential storage is not configured. Please contact your administrator.',
    phone_number_taken: 'This WhatsApp phone number is already connected.',
    number_not_connected: 'This WhatsApp number is not connected on Meta yet. Finish linking it in the WhatsApp Business App, then try again.',
    meta_error: 'We could not complete WhatsApp Business App coexistence setup with Meta. Please try again.'
  }.freeze

  def create
    started = now_ms
    trace(:create_request_started, result: 'started')

    result = ::Bloomwire::WhatsappCoexistenceEmbeddedSignupService.new(
      account: Current.account, params: embedded_signup_params
    ).perform

    if result.success?
      trace(:create_request_succeeded, result: 'success', http_status: 201, elapsed_ms: now_ms - started)
      render json: result.dto, status: :created
    else
      status = error_status(result.error)
      trace(:create_request_failed, result: 'failure', http_status: Rack::Utils.status_code(status),
                                    error_code: result.error.to_s, elapsed_ms: now_ms - started)
      render json: { error: safe_message(result.error), code: result.error }, status: status
    end
  end

  private

  # Onboarding trace correlation id (opaque, non-secret) minted by the browser and echoed through every stage.
  # Kept OUT of `embedded_signup_params` so it never reaches the Meta service call.
  def onboarding_attempt_id
    params[:onboarding_attempt_id]
  end

  def trace(event, **attrs)
    ::Bloomwire::OnboardingTrace.emit(
      attempt_id: onboarding_attempt_id, account_id: Current.account&.id, actor_id: Current.user&.id,
      event: event.to_s, source: 'controller', **attrs
    )
  end

  def now_ms
    Process.clock_gettime(Process::CLOCK_MONOTONIC, :millisecond)
  end

  def embedded_signup_params
    params.permit(:code, :business_id, :waba_id, :phone_number_id, :display_phone_number).to_h.symbolize_keys
  end

  def ensure_managed_whatsapp_self_serve!
    return if ::Bloomwire::Features.restrict_native_whatsapp_setup? &&
              ::Bloomwire::Features.enabled?(:managed_whatsapp_onboarding)

    head :not_found
  end

  def safe_message(error)
    SAFE_ERROR_MESSAGES.fetch(error, 'Could not complete WhatsApp coexistence setup. Please try again.')
  end

  def error_status(error)
    error == :meta_error ? :bad_gateway : :unprocessable_entity
  end
end
