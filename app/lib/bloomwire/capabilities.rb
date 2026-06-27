# Phase 11B.6B: server-derived, non-secret UI capability map for the dashboard. Given the requesting
# account_user, it returns ONLY derived boolean capabilities (camelCase, to be consumed directly by the
# frontend `useBloomwireCapabilities` composable) — never raw BLOOMWIRE_* toggle names or values.
#
# Each capability = the user is an administrator AND the matching managed-mode restriction is NOT in effect.
# All restriction checks go through the master-gated Bloomwire::Features helpers, so with Bloomwire OFF every
# capability is true for an administrator (stock Chatwoot). UI hiding is UX only; the backend guards
# (PR #40/#43/#44/#46/#47/#48) remain the enforcement boundary.
module Bloomwire::Capabilities
  module_function

  def for(account_user)
    admin = account_user.respond_to?(:administrator?) && account_user.administrator?

    {
      canManageAccountControlPlane: capability(admin, Bloomwire::Features.restrict_account_admin?),
      canManageProviderSetup: capability(admin, Bloomwire::Features.restrict_provider_setup?),
      canManageNativeWhatsappSetup: capability(admin, Bloomwire::Features.restrict_native_whatsapp_setup?),
      canDeleteManagedProviderInbox: capability(admin, Bloomwire::Features.restrict_provider_setup?),
      canRegisterProviderWebhook: capability(admin, Bloomwire::Features.restrict_provider_setup?),
      # Phase 11B.7C: ALL inbox creation (incl. self-service web_widget/api) is Ops-owned in managed mode.
      canCreateInbox: capability(admin, Bloomwire::Features.restrict_provider_setup?)
    }
  end

  # A capability is true only when the user is an administrator AND the matching restriction is NOT in effect.
  def capability(admin, restricted)
    admin && !restricted
  end
end
