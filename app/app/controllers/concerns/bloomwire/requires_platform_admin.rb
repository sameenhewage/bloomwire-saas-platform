# Phase 15A (ADR-0007): when Bloomwire Mode is ON, the /super_admin console requires BOTH a SuperAdmin session
# AND an explicit Bloomwire platform-admin approval (bloomwire_platform_admins). Wired AFTER
# `authenticate_super_admin!` in SuperAdmin::ApplicationController, so identity (users.type = 'SuperAdmin') is
# already established; this adds the authorization check on top. Mode OFF => stock Chatwoot (gate inert).
#
# Fail-closed: an unapproved SuperAdmin is signed out of the :super_admin scope and redirected to the login
# with a non-secret message. No secrets / tokens / provider_config / phone numbers are read or echoed.
module Bloomwire::RequiresPlatformAdmin
  extend ActiveSupport::Concern

  private

  def require_bloomwire_platform_admin!
    return unless Bloomwire::Features.master_enabled?
    return if Bloomwire::PlatformAdmin.approved?(current_super_admin)

    sign_out(:super_admin)
    redirect_to new_super_admin_session_path, flash: { error: I18n.t('bloomwire.platform_admin_required') }
  end
end
