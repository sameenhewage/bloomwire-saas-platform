import { ref } from 'vue';
import { useBloomwireCapabilities } from '../useBloomwireCapabilities';
import { useStoreGetters } from 'dashboard/composables/store';

vi.mock('dashboard/composables/store');

const mockGetters = ({ accountId = 1, capabilities } = {}) => {
  useStoreGetters.mockReturnValue({
    getCurrentAccountId: ref(accountId),
    'accounts/getAccount': ref(id =>
      id === accountId
        ? { id, bloomwire_capabilities: capabilities }
        : undefined
    ),
  });
};

describe('useBloomwireCapabilities', () => {
  it('reflects an explicit false capability from the account payload', () => {
    mockGetters({ capabilities: { canManageAccountControlPlane: false } });
    const { canManageAccountControlPlane } = useBloomwireCapabilities();
    expect(canManageAccountControlPlane.value).toBe(false);
  });

  it('reflects an explicit true capability from the account payload', () => {
    mockGetters({ capabilities: { canManageAccountControlPlane: true } });
    const { canManageAccountControlPlane } = useBloomwireCapabilities();
    expect(canManageAccountControlPlane.value).toBe(true);
  });

  it('defaults to true (stock-safe) when the capability map is absent', () => {
    mockGetters({ capabilities: undefined });
    const { canManageAccountControlPlane } = useBloomwireCapabilities();
    expect(canManageAccountControlPlane.value).toBe(true);
  });

  it('defaults to true (stock-safe) when a specific capability key is missing', () => {
    mockGetters({ capabilities: { canManageProviderSetup: false } });
    const { canManageAccountControlPlane } = useBloomwireCapabilities();
    expect(canManageAccountControlPlane.value).toBe(true);
  });

  it('defaults to true (stock-safe) when the account record is not loaded', () => {
    useStoreGetters.mockReturnValue({
      getCurrentAccountId: ref(1),
      'accounts/getAccount': ref(() => undefined),
    });
    const { canManageAccountControlPlane } = useBloomwireCapabilities();
    expect(canManageAccountControlPlane.value).toBe(true);
  });

  it('exposes the full capability map and reflects values', () => {
    mockGetters({ capabilities: { canManageProviderSetup: false } });
    const caps = useBloomwireCapabilities();
    expect(Object.keys(caps)).toEqual([
      'canManageAccountControlPlane',
      'canManageProviderSetup',
      'canManageNativeWhatsappSetup',
      'canDeleteManagedProviderInbox',
      'canRegisterProviderWebhook',
      'canCreateInbox',
    ]);
    expect(caps.canManageProviderSetup.value).toBe(false);
  });
});
