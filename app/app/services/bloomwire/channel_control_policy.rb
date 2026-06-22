# Backend decision authority for Bloomwire-controlled channel setup.
#
# Phase 4.4-b-WA — Slice 1 (behavior-neutral). Decides whether a principal may
# perform raw WhatsApp setup (create/connect/reauthorize a WhatsApp channel or
# inbox) in a tenant account. It reuses the EXISTING core Chatwoot AccountUser
# membership/role (NOT Enterprise custom_roles) and returns a boolean only — it
# never reads or exposes Chatwoot conversation/message/contact data.
#
# Current rule (matches the reachable, pre-existing admin gate):
# - A User who is an `administrator` AccountUser of the tenant's account — allowed.
# - Everyone else (agents, non-members, cross-tenant, nil) — denied.
#
# SuperAdmin / platform-initiated WhatsApp setup is intentionally FUTURE WORK: these
# account-scoped controllers require AccountUser membership before this policy is
# reachable, so a membership-less SuperAdmin cannot reach WhatsApp setup today. We do
# not claim platform support here until it is made truly reachable with tests.
#
# Intentionally PROFILE-AGNOSTIC in this slice: it does NOT read
# BloomwireBusinessProfile, so tenants without a profile keep working exactly as
# before. A later slice may introduce a tenant capability and flip the default to
# platform-controlled.
class Bloomwire::ChannelControlPolicy
  def initialize(user:, account:)
    @user = user
    @account = account
  end

  # Returns a strict boolean. Never raises for nil inputs (safe deny).
  def can_setup_whatsapp?
    return false if @user.nil? || @account.nil?

    account_administrator?
  end

  private

  # Membership is read from the core AccountUser role only (no Enterprise roles).
  def account_administrator?
    return false unless @user.is_a?(User)

    membership = AccountUser.find_by(account_id: @account.id, user_id: @user.id)
    membership&.administrator? || false
  end
end
