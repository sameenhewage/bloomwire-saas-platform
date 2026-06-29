# Phase 15A.1 (ADR-0007): owner-only Platform Admin management console. Inherits the SuperAdmin auth chain
# (authenticate_super_admin! + require_bloomwire_platform_admin!) and ADDS an owner-only gate — only an active
# platform OWNER may list/grant/revoke/reactivate platform admins. admin/support are bounced.
class SuperAdmin::BloomwirePlatformAdminsController < SuperAdmin::ApplicationController
  before_action :require_platform_owner!

  def index
    @platform_admins = Bloomwire::PlatformAdmin.includes(:user).order(:role, :id)
    @roles = Bloomwire::PlatformAdmin.roles.keys
  end

  def create
    p = invite_params
    Bloomwire::PlatformAdminInviter.call(
      actor: current_super_admin, email: p[:email], name: p[:name], role: p[:role], reason: p[:reason]
    )
    redirect_to super_admin_bloomwire_platform_admins_path, flash: { notice: I18n.t('bloomwire.platform_admin.granted') }
  rescue Bloomwire::PlatformAdminInviter::Error => e
    redirect_to super_admin_bloomwire_platform_admins_path, flash: { error: e.message }
  end

  def revoke
    record = Bloomwire::PlatformAdmin.find(params[:id])
    record.soft_revoke!(reason: params[:reason].presence || 'Revoked by platform owner')
    redirect_to super_admin_bloomwire_platform_admins_path, flash: { notice: I18n.t('bloomwire.platform_admin.revoked') }
  rescue Bloomwire::PlatformAdmin::LastOwnerError => e
    redirect_to super_admin_bloomwire_platform_admins_path, flash: { error: e.message }
  end

  def reactivate
    record = Bloomwire::PlatformAdmin.find(params[:id])
    record.reactivate!(approved_by: current_super_admin, reason: params[:reason].presence || 'Reactivated by platform owner')
    redirect_to super_admin_bloomwire_platform_admins_path, flash: { notice: I18n.t('bloomwire.platform_admin.reactivated') }
  end

  private

  def require_platform_owner!
    return if Bloomwire::PlatformAdmin.active_owners.exists?(user_id: current_super_admin&.id)

    redirect_to super_admin_root_path, flash: { error: I18n.t('bloomwire.platform_admin.owner_only') }
  end

  def invite_params
    params.require(:platform_admin).permit(:name, :email, :role, :reason)
  end
end
