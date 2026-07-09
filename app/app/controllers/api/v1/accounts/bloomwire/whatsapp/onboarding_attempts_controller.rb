# Slice 4 (ADR-0010 v3): async managed WhatsApp onboarding API. Admin-only; inert (404) unless Bloomwire managed
# self-serve AND the async flag are ON (frontend falls back to the synchronous EmbeddedSignupsController when OFF).
# The request does ZERO Meta work: it only creates/updates the attempt and enqueues the background job (after the
# DB commit). Secrets are stored ONLY via the fail-closed model methods; access is always Current.account-scoped
# (a foreign public_uuid is a 404). Responses are the safe DTO only (no secrets).
class Api::V1::Accounts::Bloomwire::Whatsapp::OnboardingAttemptsController < Api::V1::Accounts::BaseController
  Attempt = ::Bloomwire::WhatsappOnboardingAttempt

  before_action :ensure_async_onboarding_enabled!
  before_action :check_admin_authorization?
  before_action :ensure_encryption_ready!, only: %i[create submit]

  # Poll endpoint. Account-scoped: a public_uuid that is not this account's is a 404 (no cross-tenant disclosure).
  def show
    attempt = find_attempt
    return if performed?

    render json: attempt.to_status_dto
  end

  # Opens an attempt BEFORE the Meta popup (no code yet). Returns the opaque public_uuid the browser polls.
  def create
    attempt = Attempt.create!(account: Current.account, status: Attempt::WAITING_META)
    render json: attempt.to_status_dto, status: :accepted
  end

  # The Meta popup completed: store the code + bind the target, bump the generation (supersedes any older job),
  # queue it, and enqueue the worker AFTER the transaction commits. No Meta call happens here.
  def submit
    attempt = find_attempt
    return if performed?

    Attempt.transaction do
      attempt.bump_generation!
      attempt.bind_target!(waba_id: submit_params[:waba_id], phone_number_id: submit_params[:phone_number_id],
                           phone_number: submit_params[:display_phone_number])
      attempt.store_code!(submit_params[:code])
      attempt.transition!(Attempt::QUEUED)
    end
    ::Bloomwire::WhatsappOnboardingJob.perform_later(attempt.id, attempt.submission_generation)
    render json: attempt.to_status_dto, status: :accepted
  end

  private

  def find_attempt
    attempt = Attempt.for_account(Current.account).find_by(public_uuid: params[:id])
    head :not_found if attempt.nil?
    attempt
  end

  def submit_params
    params.permit(:code, :business_id, :waba_id, :phone_number_id, :display_phone_number)
  end

  # Async is the flow whenever Bloomwire managed onboarding is available for the account AND the emergency kill
  # switch is not set (there is NO separate positive async flag). When emergency-disabled, this surface is inert
  # (404) and the frontend falls back to the synchronous embedded-signup path.
  def ensure_async_onboarding_enabled!
    return if ::Bloomwire::Features.async_whatsapp_onboarding?

    head :not_found
  end

  # The Slice 1 readiness contract, now ENFORCED: the async flow cannot be submitted without AR encryption, so a
  # secret is never stored (or attempted) in plaintext. Safe, non-secret error code.
  def ensure_encryption_ready!
    return if Attempt.async_onboarding_available?

    render json: { error: 'Secure credential storage is not configured. Please contact your administrator.',
                   code: Attempt.readiness_error_code },
           status: :unprocessable_entity
  end
end
