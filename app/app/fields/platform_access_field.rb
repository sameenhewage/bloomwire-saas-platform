require 'administrate/field/base'

# Phase 15A.2: renders a user's Bloomwire platform-access status (the REAL platform role from
# bloomwire_platform_admins) as a readable label in the SuperAdmin Users table — replacing the misleading raw
# users.type column. `data` is the symbol from User#platform_access.
class PlatformAccessField < Administrate::Field::Base
  LABELS = {
    'owner' => 'Owner',
    'admin' => 'Admin',
    'support' => 'Support',
    'revoked' => 'Revoked',
    'not_approved' => 'Not approved',
    'no_access' => 'No platform access'
  }.freeze

  def to_s
    LABELS.fetch(data.to_s, 'No platform access')
  end
end
