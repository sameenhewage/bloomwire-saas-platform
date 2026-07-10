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
    restriction_capabilities(admin).merge(managed_capabilities(admin))
  end

  # Restriction-gated capabilities: true unless the matching managed-mode restriction is in effect (OFF == stock,
  # so all true for an administrator). Split out from `managed_capabilities` to keep each method's ABC size sane.
  def restriction_capabilities(admin)
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
      canAccessIntegrations: capability(admin, Bloomwire::Features.restrict_provider_setup?)
    }
  end

  # Managed-mode-only capabilities: the positive counterpart — true only when the managed feature IS in effect.
  def managed_capabilities(admin)
    {
      # Universal "Remove inbox": an administrator may permanently delete ANY of their own account's inboxes through
      # the inbox Settings page whenever Bloomwire mode is ON (the former managed/provider destroy restriction is
      # lifted; a WhatsApp delete is Meta-safe). With Bloomwire OFF this is false (stock — the inbox-list delete is
      # the path). Agents are always false. The backend InboxesController#destroy (admin + account-scoped) remains
      # the enforcement boundary; this only drives the Settings-page UI.
      canRemoveInbox: managed_capability(admin, Bloomwire::Features.master_enabled?),
      # Phase 17C.1: the managed, customer self-serve WhatsApp onboarding wizard (Embedded Signup first) is
      # available to a business ADMINISTRATOR only when ALL hold: native WhatsApp setup is managed (Bloomwire
      # mode ON AND native WhatsApp restricted) AND the explicit managed WhatsApp onboarding feature is enabled
      # (Bloomwire::Features.enabled?(:managed_whatsapp_onboarding) — which is master-gated AND privacy-dependent,
      # so privacy hardening is required too). It is the mutually-exclusive counterpart of
      # canManageNativeWhatsappSetup: when native setup is allowed the admin uses the native flow; when native
      # setup is restricted (managed) AND onboarding is enabled the admin self-serves the managed wizard. With
      # Bloomwire OFF, native-not-restricted, or the onboarding feature OFF this is false; agents are always
      # false. Backend enforcement remains the boundary — this only drives UI.
      canSelfServeManagedWhatsapp: managed_capability(admin, Bloomwire::Features.managed_whatsapp_onboarding_available?),
      # ADR-0010 v3: the EXPLICIT async-vs-sync routing signal for Standard onboarding only. The frontend routes on
      # this capability, NOT on an HTTP 404. True => async Standard; false while managed onboarding is available =>
      # protected synchronous Standard fallback (emergency switch on). Coexistence remains on its existing flow.
      canUseAsyncStandardWhatsappOnboarding: managed_capability(admin, Bloomwire::Features.async_whatsapp_onboarding?),
      # Phase 17F.1: the administrator-only, READ-ONLY "Categories & Inboxes" overview. Available to a business
      # ADMINISTRATOR only when the managed category-admin UI feature is enabled (master-gated). Agents are always
      # false. With Bloomwire OFF or the feature OFF this is false (stock — no overview). Drives UI route/nav gating;
      # the backend controller (admin-only + feature-gated 404) remains the enforcement boundary.
      canAccessCategoryAdmin: managed_capability(admin, Bloomwire::Features.enabled?(:category_admin_ui))
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
