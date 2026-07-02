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
      canCreateInbox: capability(admin, Bloomwire::Features.restrict_provider_setup?),
      # Phase 11B.7D: bot management (agent bots + inbox-level set/disconnect) is Ops-owned in managed mode.
      canManageBots: capability(admin, Bloomwire::Features.restrict_bot_management?),
      # Phase 11B.7E: integrations (catalog/connect/config admin surface) are Ops-owned in managed mode.
      # Connect/config writes are already blocked server-side (PR #47); this drives the UI hide + route block.
      # The catalog READ (apps#index/show) intentionally stays open — it is consumed by runtime conversation
      # surfaces (ContactPanel Linear, video-call button, label suggestions), so it must not 403.
      canAccessIntegrations: capability(admin, Bloomwire::Features.restrict_provider_setup?),
      # Phase 17C.1: the managed, customer self-serve WhatsApp onboarding wizard (Embedded Signup first) is
      # available to a business ADMINISTRATOR only when ALL hold: native WhatsApp setup is managed (Bloomwire
      # mode ON AND native WhatsApp restricted) AND the explicit managed WhatsApp onboarding feature is enabled
      # (Bloomwire::Features.enabled?(:managed_whatsapp_onboarding) — which is master-gated AND privacy-dependent,
      # so privacy hardening is required too). It is the mutually-exclusive counterpart of
      # canManageNativeWhatsappSetup: when native setup is allowed the admin uses the native flow; when native
      # setup is restricted (managed) AND onboarding is enabled the admin self-serves the managed wizard. With
      # Bloomwire OFF, native-not-restricted, or the onboarding feature OFF this is false; agents are always
      # false. Backend enforcement (the future dedicated endpoint) remains the boundary — this only drives UI.
      canSelfServeManagedWhatsapp: managed_capability(
        admin, Bloomwire::Features.restrict_native_whatsapp_setup? && Bloomwire::Features.enabled?(:managed_whatsapp_onboarding)
      )
    }
  end

  # A capability is true only when the user is an administrator AND the matching restriction is NOT in effect.
  def capability(admin, restricted)
    admin && !restricted
  end

  # A managed capability is true only when the user is an administrator AND the managed feature IS in effect
  # (the positive counterpart of `capability`). Used for managed-mode-only surfaces (e.g. self-serve WhatsApp).
  def managed_capability(admin, enabled)
    admin && enabled
  end
end
