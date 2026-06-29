# Phase 15F (ADR-0007): owner-only gate for Bloomwire management surfaces (e.g. Email Settings). Layered on
# top of the SuperAdmin auth chain (authenticate_super_admin! + require_bloomwire_platform_admin!) — only an
# ACTIVE platform OWNER may pass; platform admin/support and customer/business users are bounced. Mirrors the
# inline gate used by the Platform Admins console. No secrets are read or echoed.
module Bloomwire::RequiresPlatformOwner
  extend ActiveSupport::Concern

  included do
    before_action :require_platform_owner!
  end

  private

  def require_platform_owner!
    return if Bloomwire::PlatformAdmin.active_owners.exists?(user_id: current_super_admin&.id)

    redirect_to super_admin_root_path, flash: { error: I18n.t('bloomwire.platform_admin.owner_only') }
  end
end
