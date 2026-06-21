# Initializes Bloomwire tenant setup for a single Chatwoot account.
#
# Phase 3 — Business Onboarding / Tenant Setup (first slice: foundation).
# This is NOT the full onboarding wizard. It is the smallest safe backend step
# that moves a tenant from "not_started" to "in_progress" so operators can begin
# preparing the business.
#
# Behaviour:
# - Ensures the account has exactly one BloomwireBusinessProfile, creating one
#   with the Phase 2 defaults (status=setup_pending, onboarding_status=not_started)
#   if it is missing.
# - Moves onboarding_status not_started -> in_progress.
# - Leaves in_progress and completed untouched (never downgrades).
# - Never sets status to active, never touches billing/plan, channels, account
#   membership, or any Chatwoot conversation/message/contact data.
# - Idempotent: safe to run repeatedly.
#
# Returns a safe summary (no account names or raw identifiers).
class Bloomwire::TenantSetupInitializer
  Result = Struct.new(
    :success, :profile_created, :previous_onboarding_status,
    :current_onboarding_status, :changed, :error,
    keyword_init: true
  )

  def initialize(account_id:)
    @account_id = account_id
  end

  def perform
    account = Account.find_by(id: @account_id)
    return failure(:account_not_found) if account.nil?

    profile, profile_created = ensure_profile(account)
    previous_status = profile.onboarding_status

    profile.update!(onboarding_status: 'in_progress') if previous_status == 'not_started'
    current_status = profile.onboarding_status

    Result.new(
      success: true,
      profile_created: profile_created,
      previous_onboarding_status: previous_status,
      current_onboarding_status: current_status,
      changed: current_status != previous_status,
      error: nil
    )
  end

  private

  def ensure_profile(account)
    existing = account.bloomwire_business_profile
    return [existing, false] if existing.present?

    [account.create_bloomwire_business_profile!, true]
  end

  def failure(error)
    Result.new(
      success: false,
      profile_created: false,
      previous_onboarding_status: nil,
      current_onboarding_status: nil,
      changed: false,
      error: error
    )
  end
end
