# Thin controller guard for Bloomwire-controlled WhatsApp setup paths.
#
# Phase 4.4-b-WA — Slice 1. Delegates the decision to
# Bloomwire::ChannelControlPolicy and raises the same authorization error used by
# the existing controllers (Pundit::NotAuthorizedError -> 401), so behavior is
# consistent with check_admin_authorization? and the OAuth controllers.
#
# Wire it only into first-party WhatsApp setup paths (embedded signup, and the
# WhatsApp-typed branches of inbox create/update). Non-WhatsApp paths must not be
# gated.
module Bloomwire::WhatsappSetupGuard
  extend ActiveSupport::Concern

  private

  def authorize_whatsapp_setup!
    return if Bloomwire::ChannelControlPolicy.new(user: Current.user, account: Current.account).can_setup_whatsapp?

    raise Pundit::NotAuthorizedError
  end
end
