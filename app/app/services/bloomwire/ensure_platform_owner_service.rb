# Phase 15A.1 (ADR-0007): idempotent bootstrap/setup path for the PRIMARY Bloomwire platform owner.
# Reads BLOOMWIRE_PLATFORM_OWNER_EMAIL (env/config — NOT hardcoded in any migration), finds that user, and
# ensures an active `bloomwire_platform_admins` row with role=owner.
#
# SECURITY (review blocker 1): this service must point to an EXISTING, DEDICATED SuperAdmin. It NEVER promotes
# a normal/business/customer user into a SuperAdmin. It fails safely (no writes) when:
#   - the env is unset (MissingEmailError),
#   - no user exists for the email (UserNotFoundError),
#   - the user exists but users.type != 'SuperAdmin' (NotSuperAdminError).
# Never prints the raw email or any secret (callers report ids/role only).
class Bloomwire::EnsurePlatformOwnerService
  EMAIL_ENV_KEY = 'BLOOMWIRE_PLATFORM_OWNER_EMAIL'.freeze

  class MissingEmailError < StandardError; end
  class UserNotFoundError < StandardError; end
  class NotSuperAdminError < StandardError; end

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
    # Never promote a normal/business user — the configured owner must already be a dedicated SuperAdmin.
    raise NotSuperAdminError, 'Configured platform owner email is not a dedicated SuperAdmin' unless user.type == 'SuperAdmin'

    record = Bloomwire::PlatformAdmin.grant!(
      user: user, approved_by: @approved_by, role: :owner,
      reason: "Primary platform owner (#{EMAIL_ENV_KEY})"
    )

    { user_id: record.user_id, role: record.role, active: record.active? }
  end
end
