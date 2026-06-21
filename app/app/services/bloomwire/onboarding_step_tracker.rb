# Tracks and advances Bloomwire tenant onboarding/readiness steps for a single
# Chatwoot account's business profile.
#
# Phase 3 — Business Onboarding / Tenant Setup (slice: onboarding step tracking).
# This is a readiness/control-plane feature ONLY. It lets operators see and move
# a tenant through its Bloomwire setup checkpoints. It does NOT build Chatwoot
# functionality (inboxes, channels, conversations, contacts, messages stay owned
# by Chatwoot), and never reads or copies Chatwoot conversation/message/contact
# data.
#
# Ownership boundaries (see CONTEXT.md / AGENTS.md rule 4):
# - Profile creation is owned by Bloomwire::TenantSetupInitializer, not here. If
#   the profile is missing, this service returns a safe failure rather than
#   creating one.
# - This service never changes the profile's onboarding_status/status, billing,
#   membership, or channel data.
#
# Returns a safe summary (counts + the current step key only).
class Bloomwire::OnboardingStepTracker
  Result = Struct.new(
    :success, :total_steps, :completed_steps, :pending_steps,
    :current_step, :all_completed, :changed, :error,
    keyword_init: true
  )

  def initialize(account_id:)
    @account_id = account_id
  end

  # Idempotently ensure the default onboarding steps exist for the tenant.
  def ensure_steps
    with_profile do |profile|
      created = ensure_default_steps(profile)
      summary(profile, changed: created.positive?)
    end
  end

  # Advance the tenant by completing the next pending step. Idempotent: once all
  # steps are completed, further calls report no change.
  def advance
    with_profile do |profile|
      ensure_default_steps(profile)
      step = next_pending_step(profile)
      step&.update!(status: 'completed')
      summary(profile, changed: step.present?)
    end
  end

  private

  def with_profile
    account = Account.find_by(id: @account_id)
    return failure(:account_not_found) if account.nil?

    profile = account.bloomwire_business_profile
    return failure(:profile_not_found) if profile.nil?

    yield(profile)
  end

  def ensure_default_steps(profile)
    existing_keys = profile.onboarding_steps.pluck(:step_key)
    created = 0

    BloomwireOnboardingStep::DEFAULT_STEPS.each_with_index do |key, index|
      next if existing_keys.include?(key)

      profile.onboarding_steps.create!(step_key: key, status: 'pending', position: index)
      created += 1
    end

    created
  end

  def next_pending_step(profile)
    profile.onboarding_steps.ordered.where.not(status: 'completed').first
  end

  def summary(profile, changed:)
    steps = profile.onboarding_steps.ordered.to_a
    completed = steps.count(&:completed?)
    current = steps.find { |step| !step.completed? }

    Result.new(
      success: true,
      total_steps: steps.size,
      completed_steps: completed,
      pending_steps: steps.size - completed,
      current_step: current&.step_key,
      all_completed: steps.any? && current.nil?,
      changed: changed,
      error: nil
    )
  end

  def failure(error)
    Result.new(
      success: false,
      total_steps: 0,
      completed_steps: 0,
      pending_steps: 0,
      current_step: nil,
      all_completed: false,
      changed: false,
      error: error
    )
  end
end
