# Backend decision authority for Bloomwire-controlled channel setup.
#
# Phase 4.4-b-WA.2C — Dialog tenant deny. Decides whether a principal may perform
# raw WhatsApp setup (create/connect/reauthorize a WhatsApp channel or inbox, update
# provider config, register the webhook) in a tenant account. It reuses the EXISTING
# core Chatwoot AccountUser membership/role (NOT Enterprise custom_roles) and returns
# a boolean only — it never reads or exposes Chatwoot conversation/message/contact data.
#
# Rule (ADR 0005 — Bloomwire owns external app/channel configuration):
# - Bloomwire-managed tenant (account has a BloomwireBusinessProfile): WhatsApp setup
#   is platform-only, so EVERY tenant principal (admins, agents, cross-tenant, nil) is
#   denied here. The SuperAdmin platform setup path does NOT use this policy.
# - Plain Chatwoot account (no Bloomwire profile): UNCHANGED — the pre-existing
#   account-administrator gate still applies (admin allowed, everyone else denied), so
#   installs that do not use Bloomwire keep behaving exactly as before.
class Bloomwire::ChannelControlPolicy
  def initialize(user:, account:)
    @user = user
    @account = account
  end

  # Returns a strict boolean. Never raises for nil inputs (safe deny).
  def can_setup_whatsapp?
    return false if @user.nil? || @account.nil?

    # Bloomwire-managed tenants: external WhatsApp configuration is platform-only,
    # so deny every tenant principal here (the SuperAdmin path does not use this
    # policy). Plain Chatwoot accounts fall through to the unchanged admin gate.
    return false if bloomwire_managed_tenant?

    account_administrator?
  end

  private

  # A tenant is Bloomwire-managed once it has a BloomwireBusinessProfile (the
  # account-level Bloomwire control-plane anchor, ADR 0005). Reads only that flag;
  # never touches Chatwoot conversation/message/contact data.
  def bloomwire_managed_tenant?
    BloomwireBusinessProfile.exists?(account_id: @account.id)
  end

  # Membership is read from the core AccountUser role only (no Enterprise roles).
  def account_administrator?
    return false unless @user.is_a?(User)

    membership = AccountUser.find_by(account_id: @account.id, user_id: @user.id)
    membership&.administrator? || false
  end
end
