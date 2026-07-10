# Slice 4 (ADR-0010 v3): async managed WhatsApp onboarding API. Admin-only. Creating a NEW async attempt is inert
# (404) unless Bloomwire managed onboarding is available AND the emergency kill switch is off (frontend then uses
# the synchronous EmbeddedSignupsController). Submitting, relaunching, cancelling, or polling an EXISTING attempt is
# kill-switch-INDEPENDENT so an attempt created before a rollback remains recoverable. Existing actions require the
# base feature and are account-scoped. The request does ZERO Meta work: it only creates/updates the attempt and
# enqueues the background job (after the DB commit). Secrets are stored ONLY via the fail-closed model methods;
# a foreign public_uuid returns 404. Responses are the safe DTO only (no secrets).
class Api::V1::Accounts::Bloomwire::Whatsapp::OnboardingAttemptsController < Api::V1::Accounts::BaseController
  Attempt = ::Bloomwire::WhatsappOnboardingAttempt

  before_action :ensure_async_onboarding_enabled!, only: %i[create]
  before_action :ensure_managed_onboarding_available!, only: %i[show submit relaunch cancel]
  before_action :check_admin_authorization?
  before_action :ensure_encryption_ready!, only: %i[create]

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

  def relaunch
    attempt = find_attempt
    return if performed?

    dto = attempt.with_lock { attempt.to_status_dto if attempt.status == Attempt::WAITING_META }
    unless dto
      render json: { code: 'attempt_not_relaunchable' }, status: :conflict
      return
    end

    render json: dto
  end

  def cancel
    attempt = find_attempt
    return if performed?

    cancelled = attempt.with_lock do
      next true if attempt.status == Attempt::CANCELLED
      next false unless attempt.status == Attempt::WAITING_META

      attempt.transition!(Attempt::CANCELLED)
      attempt.update!(processing_owner: nil, lease_expires_at: nil, job_enqueued_at: nil, processing_started_at: nil)
      attempt.clear_secrets!
      true
    end

    unless cancelled
      render json: { code: 'attempt_not_cancellable' }, status: :conflict
      return
    end

    render json: attempt.reload.to_status_dto
  end

  # The Meta popup completed: store the code + bind the target, bump the generation (supersedes any older job),
  # queue it, and enqueue the worker AFTER the transaction commits. A replay of an in-flight submission reuses its
  # persisted generation without overwriting credentials. No Meta call happens here.
  def submit
    attempt = find_attempt
    return if performed?

    unless submittable_status?(attempt)
      render json: { code: 'attempt_not_submittable' }, status: :conflict
      return
    end

    ensure_encryption_ready!
    return if performed?

    generation = prepare_submission(attempt)
    unless generation
      render json: { code: 'attempt_not_submittable' }, status: :conflict
      return
    end

    ::Bloomwire::WhatsappOnboardingJob.perform_later(attempt.id, generation)
    render json: attempt.reload.to_status_dto, status: :accepted
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

  def submittable_status?(attempt)
    attempt.status == Attempt::WAITING_META || Attempt::REDRIVABLE_STATUSES.include?(attempt.status)
  end

  def prepare_submission(attempt)
    attempt.with_lock do
      if attempt.status == Attempt::WAITING_META
        attempt.bump_generation!
        attempt.bind_target!(waba_id: submit_params[:waba_id], phone_number_id: submit_params[:phone_number_id],
                             business_id: submit_params[:business_id], phone_number: submit_params[:display_phone_number])
        attempt.store_code!(submit_params[:code])
        attempt.transition!(Attempt::QUEUED)
      elsif Attempt::REDRIVABLE_STATUSES.exclude?(attempt.status)
        next
      end

      attempt.submission_generation
    end
  end

  # Gates NEW async work (create): async is the flow whenever Bloomwire managed onboarding is available AND the
  # emergency kill switch is not set (there is NO separate positive async flag). When emergency-disabled creation is
  # inert (404) and the frontend falls back to the synchronous embedded-signup path.
  def ensure_async_onboarding_enabled!
    return if ::Bloomwire::Features.async_whatsapp_onboarding?

    head :not_found
  end

  # Gates completing, recovering, cancelling, or reading an existing attempt. Deliberately kill-switch-INDEPENDENT:
  # an attempt created before an emergency rollback must remain manageable to completion. These actions still
  # require the base Bloomwire managed-onboarding feature (feature OFF => unavailable).
  def ensure_managed_onboarding_available!
    return if ::Bloomwire::Features.managed_whatsapp_onboarding_available?

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
