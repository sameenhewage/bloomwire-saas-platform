# Thin controller guard for Bloomwire-controlled WhatsApp setup paths.
#
# Phase 4.4-b-WA.2C — Dialog tenant deny. Delegates the decision to
# Bloomwire::ChannelControlPolicy and raises the same authorization error used by
# the existing controllers (Pundit::NotAuthorizedError -> 401), so behavior is
# consistent with check_admin_authorization? and the OAuth controllers.
#
# Wire it only into first-party WhatsApp setup paths (embedded signup, the
# WhatsApp-typed branches of inbox create/update, register_webhook) and the destroy
# of a Bloomwire-managed WhatsApp inbox. Non-WhatsApp paths must not be gated.
module Bloomwire::WhatsappSetupGuard
  extend ActiveSupport::Concern

  private

  def authorize_whatsapp_setup!
    return if Bloomwire::ChannelControlPolicy.new(user: Current.user, account: Current.account).can_setup_whatsapp?

    raise Pundit::NotAuthorizedError
  end

  # Destroying a Bloomwire-managed WhatsApp inbox disconnects a platform-owned
  # external app — setup/config ownership, not normal inbox usage — so every tenant
  # principal (admins and agents) is denied. Non-managed or non-WhatsApp inboxes are
  # not gated, so plain Chatwoot destroy behavior is unchanged (ADR 0005, 4.4-b-WA.2C).
  def authorize_whatsapp_managed_inbox_destroy!
    return unless BloomwireChannelIntegration.managed_whatsapp_inbox?(@inbox)

    raise Pundit::NotAuthorizedError
  end
end
