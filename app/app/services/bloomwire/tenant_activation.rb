# Backend-enforced manual activation gate for a Bloomwire tenant.
#
# Phase 3 — Business Onboarding / Tenant Setup (final slice: manual activation).
#
# A tenant may only move to `active` when its Bloomwire profile exists, its
# Chatwoot setup is Ready (per Bloomwire::ChatwootReadiness), and every onboarding
# step is completed. This is a CONTROL-PLANE status change ONLY: it never creates
# or configures Chatwoot inboxes/channels/webhooks, and never reads or copies
# Chatwoot conversation/message/contact data (see AGENTS.md rules 1, 3, 4, 8).
#
# A failed gate mutates nothing and returns a safe, non-identifying reason code.
# Activation owns exactly one transition (rule 4):
#   status:            setup_pending -> active
#   onboarding_status: not_started/in_progress -> completed
# Already-active tenants are idempotent (success, no change).
class Bloomwire::TenantActivation
  Result = Struct.new(
    :success, :status, :onboarding_status, :already_active, :changed, :error,
    keyword_init: true
  )

  # Safe, non-identifying failure reason codes (no raw ids/data).
  PROFILE_NOT_FOUND = :profile_not_found
  CHATWOOT_NOT_READY = :chatwoot_not_ready
  ONBOARDING_STEPS_MISSING = :onboarding_steps_missing
  ONBOARDING_INCOMPLETE = :onboarding_incomplete

  def initialize(profile)
    @profile = profile
  end

  def activate
    return failure(PROFILE_NOT_FOUND) if @profile.nil?
    return already_active if @profile.status == 'active'

    reason = blocking_reason
    return failure(reason) if reason

    @profile.update!(status: 'active', onboarding_status: 'completed')
    success(changed: true)
  end

  private

  def blocking_reason
    return CHATWOOT_NOT_READY unless chatwoot_ready?

    summary = @profile.onboarding_step_summary
    return ONBOARDING_STEPS_MISSING if summary.total.zero?
    return ONBOARDING_INCOMPLETE unless summary.all_completed

    nil
  end

  def chatwoot_ready?
    Bloomwire::ChatwootReadiness.new(@profile.account, profile: @profile).status ==
      Bloomwire::ChatwootReadiness::READY
  end

  def already_active
    result(success: true, already_active: true, changed: false, error: nil)
  end

  def success(changed:)
    result(success: true, already_active: false, changed: changed, error: nil)
  end

  def failure(error)
    Result.new(
      success: false, status: @profile&.status, onboarding_status: @profile&.onboarding_status,
      already_active: false, changed: false, error: error
    )
  end

  def result(success:, already_active:, changed:, error:)
    Result.new(
      success: success, status: @profile.status, onboarding_status: @profile.onboarding_status,
      already_active: already_active, changed: changed, error: error
    )
  end
end
