# Phase 11B.2: control-plane guard that blocks business account ADMINISTRATORS from dangerous account-admin
# actions (agent & role management, account settings, webhooks) when Bloomwire restriction mode is ON
# (BLOOMWIRE_MODE_ENABLED + BLOOMWIRE_RESTRICT_ACCOUNT_ADMIN). Those actions are then owned by Bloomwire
# Ops/SuperAdmin, which operate via the separate /super_admin Devise surface and are unaffected by this guard.
# OFF => stock Chatwoot.
#
# It is wired AFTER the controller's existing Pundit authorization and only fires for an administrator, so
# agents/unauthenticated callers keep hitting the stock policy path unchanged (nothing is loosened). It returns
# a 403 with a non-secret message and reads/echoes no secrets.
module Bloomwire::RestrictsAccountControlPlane
  extend ActiveSupport::Concern

  private

  def restrict_account_control_plane!
    return unless Bloomwire::Features.restrict_account_admin?
    return unless @current_account_user&.administrator?

    render json: { error: I18n.t('bloomwire.account_control_plane_restricted'), managed_by_ops: true }, status: :forbidden
  end
end
