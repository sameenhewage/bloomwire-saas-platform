import { computed } from 'vue';
import { useStoreGetters } from 'dashboard/composables/store';

/**
 * Composable exposing the server-derived, non-secret Bloomwire UI capability booleans for the current
 * account (from the account payload's `bloomwire_capabilities` map).
 *
 * Stock-safe default: when a capability is missing (Bloomwire OFF, an older backend, or the account record
 * is not loaded yet) it is treated as TRUE so stock Chatwoot UI is preserved. Only an explicit `false` from
 * the server hides a control. UI hiding is UX only — the backend guards/403 remain the enforcement boundary.
 *
 * @returns {Object<string, import('vue').ComputedRef<boolean>>}
 */
const STOCK_SAFE_DEFAULT = true;

export function useBloomwireCapabilities() {
  const getters = useStoreGetters();

  const capabilities = computed(() => {
    const accountId = getters.getCurrentAccountId?.value;
    const getAccount = getters['accounts/getAccount']?.value;
    const account =
      typeof getAccount === 'function' ? getAccount(accountId) : undefined;
    return account?.bloomwire_capabilities ?? {};
  });

  // `fallback` is the value used when the key is absent. Stock-hiding capabilities default TRUE (preserve stock
  // Chatwoot); opt-in managed capabilities MUST pass `false` so they stay hidden in stock / older-backend / not-
  // loaded states and only appear on an explicit server `true`.
  const buildCapability = (key, fallback = STOCK_SAFE_DEFAULT) =>
    computed(() => {
      const value = capabilities.value?.[key];
      return value === undefined ? fallback : value;
    });

  return {
    canManageAccountControlPlane: buildCapability(
      'canManageAccountControlPlane'
    ),
    canManageProviderSetup: buildCapability('canManageProviderSetup'),
    canManageNativeWhatsappSetup: buildCapability(
      'canManageNativeWhatsappSetup'
    ),
    canDeleteManagedProviderInbox: buildCapability(
      'canDeleteManagedProviderInbox'
    ),
    canRegisterProviderWebhook: buildCapability('canRegisterProviderWebhook'),
    canCreateInbox: buildCapability('canCreateInbox'),
    canManageBots: buildCapability('canManageBots'),
    canAccessIntegrations: buildCapability('canAccessIntegrations'),
    // Phase 17C.3: managed self-serve WhatsApp Embedded Signup wizard. Opt-in (default FALSE) — only shown when
    // the backend explicitly grants it (admin + native WhatsApp restricted + managed_whatsapp_onboarding on).
    canSelfServeManagedWhatsapp: buildCapability(
      'canSelfServeManagedWhatsapp',
      false
    ),
    // Phase 17F.1: administrator-only, READ-ONLY "Categories & Inboxes" overview. Opt-in (default FALSE) — the
    // page/nav only appear on an explicit server `true` (admin + BLOOMWIRE_CATEGORY_ADMIN_UI on). The backend
    // controller (admin-only + feature-gated 404) remains the enforcement boundary; this only drives UI gating.
    canAccessCategoryAdmin: buildCapability('canAccessCategoryAdmin', false),
  };
}
