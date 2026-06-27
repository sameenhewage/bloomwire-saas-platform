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

  const buildCapability = key =>
    computed(() => {
      const value = capabilities.value?.[key];
      return value === undefined ? STOCK_SAFE_DEFAULT : value;
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
  };
}
