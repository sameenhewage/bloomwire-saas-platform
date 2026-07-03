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
      'canManageBots',
      'canAccessIntegrations',
      'canSelfServeManagedWhatsapp',
      'canAccessCategoryAdmin',
    ]);
    expect(caps.canManageProviderSetup.value).toBe(false);
  });

  // Phase 17C.3: opt-in managed capability — defaults to FALSE (must stay hidden in stock / older backend), and
  // only appears on an explicit server `true`.
  describe('canSelfServeManagedWhatsapp (opt-in, default false)', () => {
    it('defaults to false when the capability map is absent', () => {
      mockGetters({ capabilities: undefined });
      const { canSelfServeManagedWhatsapp } = useBloomwireCapabilities();
      expect(canSelfServeManagedWhatsapp.value).toBe(false);
    });

    it('defaults to false when the specific key is missing (other caps present)', () => {
      mockGetters({ capabilities: { canManageProviderSetup: true } });
      const { canSelfServeManagedWhatsapp } = useBloomwireCapabilities();
      expect(canSelfServeManagedWhatsapp.value).toBe(false);
    });

    it('is true only on an explicit server true', () => {
      mockGetters({ capabilities: { canSelfServeManagedWhatsapp: true } });
      const { canSelfServeManagedWhatsapp } = useBloomwireCapabilities();
      expect(canSelfServeManagedWhatsapp.value).toBe(true);
    });
  });

  // Phase 17F.1: opt-in managed capability for the admin-only, read-only "Categories & Inboxes" overview —
  // defaults to FALSE (stays hidden in stock / older backend / agent) and only appears on an explicit server `true`.
  describe('canAccessCategoryAdmin (opt-in, default false)', () => {
    it('defaults to false when the capability map is absent', () => {
      mockGetters({ capabilities: undefined });
      const { canAccessCategoryAdmin } = useBloomwireCapabilities();
      expect(canAccessCategoryAdmin.value).toBe(false);
    });

    it('defaults to false when the specific key is missing (other caps present)', () => {
      mockGetters({ capabilities: { canManageProviderSetup: true } });
      const { canAccessCategoryAdmin } = useBloomwireCapabilities();
      expect(canAccessCategoryAdmin.value).toBe(false);
    });

    it('is true only on an explicit server true', () => {
      mockGetters({ capabilities: { canAccessCategoryAdmin: true } });
      const { canAccessCategoryAdmin } = useBloomwireCapabilities();
      expect(canAccessCategoryAdmin.value).toBe(true);
    });
  });
});
