# Backend, tenant-scoped permission foundation for Bloomwire features.
#
# Phase 4 — Slice 1: Permission Foundation / Access Policy.
#
# Decides whether a principal may perform a Bloomwire tenant action. The policy
# reuses the EXISTING core Chatwoot AccountUser membership/role; it does NOT use
# Enterprise custom_roles, and it never reads or exposes Chatwoot
# conversation/message/contact data — it returns a boolean decision only.
#
# Principals:
# - SuperAdmin (STI subclass of User): platform-level — allowed for every action.
# - A User who is an `administrator` AccountUser of the tenant's account: may VIEW
#   that tenant's metadata, but only once the tenant is active.
# - Everyone else (agents, non-members, cross-tenant, nil): denied.
#
# Platform control actions (e.g. activate_tenant) are reserved for SuperAdmin in
# this foundation; tenant users cannot perform them unless this policy is later
# extended to allow it.
class Bloomwire::AccessPolicy
  VIEW_ACTIONS = %i[view_business_profile view_onboarding_status view_chatwoot_readiness].freeze
  PLATFORM_ACTIONS = %i[activate_tenant].freeze
  KNOWN_ACTIONS = (VIEW_ACTIONS + PLATFORM_ACTIONS).freeze

  def initialize(user:, profile:)
    @user = user
    @profile = profile
  end

  # Returns a strict boolean. Never raises for nil/unknown inputs (safe deny).
  def can?(action)
    action = action&.to_sym
    return false unless KNOWN_ACTIONS.include?(action)
    return false if @user.nil? || @profile.nil?
    return true if super_admin?
    return false if PLATFORM_ACTIONS.include?(action)

    own_active_tenant_admin?
  end

  private

  def super_admin?
    @user.is_a?(SuperAdmin)
  end

  # Tenant users may view their own tenant metadata only once it is active.
  def own_active_tenant_admin?
    return false unless @profile.status == 'active'

    tenant_admin?
  end

  # Membership is read from the core AccountUser role only (no Enterprise roles).
  def tenant_admin?
    return false unless @user.is_a?(User)
    return false if @profile.account_id.nil?

    membership = AccountUser.find_by(account_id: @profile.account_id, user_id: @user.id)
    membership&.administrator? || false
  end
end
