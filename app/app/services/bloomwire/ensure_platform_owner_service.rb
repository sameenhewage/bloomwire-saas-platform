# Phase 15A.1 (ADR-0007): idempotent bootstrap/setup path for the PRIMARY Bloomwire platform owner.
# Reads BLOOMWIRE_PLATFORM_OWNER_EMAIL (env/config — NOT hardcoded in any migration), finds that user,
# ensures users.type = 'SuperAdmin', and ensures an active `bloomwire_platform_admins` row with role=owner.
#
# Fail-safe: raises (no create) if the email is unset or no user exists — creating the owner from scratch is
# out of scope for this setup path. Never prints the raw email or any secret (callers report ids/role only).
class Bloomwire::EnsurePlatformOwnerService
  EMAIL_ENV_KEY = 'BLOOMWIRE_PLATFORM_OWNER_EMAIL'.freeze

  class MissingEmailError < StandardError; end
  class UserNotFoundError < StandardError; end

  def self.call(email: nil, approved_by: nil)
    new(email: email, approved_by: approved_by).call
  end

  def initialize(email: nil, approved_by: nil)
    @email = (email || ENV.fetch(EMAIL_ENV_KEY, nil)).to_s.strip.downcase
    @approved_by = approved_by
  end

  def call
    raise MissingEmailError, "#{EMAIL_ENV_KEY} is not set" if @email.blank?

    user = User.from_email(@email)
    raise UserNotFoundError, 'No user found for the configured platform owner email' if user.nil?

    promoted = ensure_super_admin_type!(user)
    record = Bloomwire::PlatformAdmin.grant!(
      user: user, approved_by: @approved_by, role: :owner,
      reason: "Primary platform owner (#{EMAIL_ENV_KEY})"
    )

    { user_id: record.user_id, role: record.role, active: record.active?, promoted_to_super_admin: promoted }
  end

  private

  # Promote to the SuperAdmin STI type if needed, WITHOUT triggering Devise emails/validations. Returns true
  # if a promotion happened (so the caller can surface a non-secret notice).
  def ensure_super_admin_type!(user)
    return false if user.type == 'SuperAdmin'

    # rubocop:disable Rails/SkipsModelValidations
    user.update_column(:type, 'SuperAdmin')
    # rubocop:enable Rails/SkipsModelValidations
    true
  end
end
