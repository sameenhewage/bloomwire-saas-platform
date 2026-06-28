# Phase 15A.1 (ADR-0007): ensure the primary Bloomwire platform owner from BLOOMWIRE_PLATFORM_OWNER_EMAIL.
# Idempotent + safe to re-run. Prints no raw email/secret — only user_id / role / active flags.
#
#   BLOOMWIRE_PLATFORM_OWNER_EMAIL=ops@example.com bundle exec rails bloomwire:ensure_platform_owner
namespace :bloomwire do
  desc 'Ensure the primary platform owner (BLOOMWIRE_PLATFORM_OWNER_EMAIL) is a SuperAdmin + active owner'
  task ensure_platform_owner: :environment do
    result = Bloomwire::EnsurePlatformOwnerService.call
    note = result[:promoted_to_super_admin] ? ' (promoted user to SuperAdmin)' : ''
    puts "[bloomwire] platform owner ensured: user_id=#{result[:user_id]} role=#{result[:role]} " \
         "active=#{result[:active]}#{note}"
  rescue Bloomwire::EnsurePlatformOwnerService::MissingEmailError,
         Bloomwire::EnsurePlatformOwnerService::UserNotFoundError => e
    warn "[bloomwire] platform owner NOT ensured: #{e.message}"
    exit 1
  end
end
