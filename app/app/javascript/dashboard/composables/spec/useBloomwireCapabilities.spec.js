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
      'capabilitiesLoaded',
      'canManageAccountControlPlane',
      'canManageProviderSetup',
      'canManageNativeWhatsappSetup',
      'canDeleteManagedProviderInbox',
      'canRemoveInbox',
      'canRegisterProviderWebhook',
      'canCreateInbox',
      'canManageBots',
      'canAccessIntegrations',
      'canSelfServeManagedWhatsapp',
      'canUseAsyncStandardWhatsappOnboarding',
      'canAccessCategoryAdmin',
      'canViewChatwootPlanUpsell',
    ]);
    expect(caps.canManageProviderSetup.value).toBe(false);
  });

  describe('canViewChatwootPlanUpsell (stock-safe, default true)', () => {
    it('reflects an explicit false from the Bloomwire account payload', () => {
      mockGetters({ capabilities: { canViewChatwootPlanUpsell: false } });
      expect(useBloomwireCapabilities().canViewChatwootPlanUpsell.value).toBe(
        false
      );
    });

    it('defaults to true when the capability is absent', () => {
      mockGetters({ capabilities: undefined });
      expect(useBloomwireCapabilities().canViewChatwootPlanUpsell.value).toBe(
        true
      );
    });
  });

  // Universal "Remove inbox" is opt-in (default FALSE) — hidden in stock / older-backend / not-loaded, shown only
  // on an explicit server `true`.
  describe('canRemoveInbox (opt-in, default false)', () => {
    it('defaults to false when the capability map is absent', () => {
      mockGetters({ capabilities: undefined });
      expect(useBloomwireCapabilities().canRemoveInbox.value).toBe(false);
    });

    it('is true only on an explicit server true', () => {
      mockGetters({ capabilities: { canRemoveInbox: true } });
      expect(useBloomwireCapabilities().canRemoveInbox.value).toBe(true);
    });
  });

  // Deterministic-tile fix: `capabilitiesLoaded` must distinguish "the account-show payload has hydrated" from
  // "not loaded yet", so consumers show a loading state instead of treating a not-yet-loaded control as denied.
  describe('capabilitiesLoaded', () => {
    it('is true once the account payload carries a bloomwire_capabilities map', () => {
      mockGetters({ capabilities: { canSelfServeManagedWhatsapp: true } });
      const { capabilitiesLoaded } = useBloomwireCapabilities();
      expect(capabilitiesLoaded.value).toBe(true);
    });

    it('is true even for an empty capability map (payload present, all-default)', () => {
      mockGetters({ capabilities: {} });
      const { capabilitiesLoaded } = useBloomwireCapabilities();
      expect(capabilitiesLoaded.value).toBe(true);
    });

    it('is false when the account record has no bloomwire_capabilities (not hydrated)', () => {
      mockGetters({ capabilities: undefined });
      const { capabilitiesLoaded } = useBloomwireCapabilities();
      expect(capabilitiesLoaded.value).toBe(false);
    });

    it('is false when the account record is not loaded at all', () => {
      useStoreGetters.mockReturnValue({
        getCurrentAccountId: ref(1),
        'accounts/getAccount': ref(() => undefined),
      });
      const { capabilitiesLoaded } = useBloomwireCapabilities();
      expect(capabilitiesLoaded.value).toBe(false);
    });
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

  // ADR-0010 v3: opt-in async-vs-sync routing capability — defaults to FALSE so a stock / older-backend / not-
  // loaded state routes to the pre-existing SYNCHRONOUS flow (never attempts async against a backend that lacks it).
  describe('canUseAsyncStandardWhatsappOnboarding (opt-in, default false)', () => {
    it('defaults to false when the capability map is absent (older backend => sync)', () => {
      mockGetters({ capabilities: undefined });
      expect(
        useBloomwireCapabilities().canUseAsyncStandardWhatsappOnboarding.value
      ).toBe(false);
    });

    it('defaults to false when the specific key is missing (other caps present)', () => {
      mockGetters({ capabilities: { canSelfServeManagedWhatsapp: true } });
      expect(
        useBloomwireCapabilities().canUseAsyncStandardWhatsappOnboarding.value
      ).toBe(false);
    });

    it('is true only on an explicit server true (async is the path)', () => {
      mockGetters({
        capabilities: { canUseAsyncStandardWhatsappOnboarding: true },
      });
      expect(
        useBloomwireCapabilities().canUseAsyncStandardWhatsappOnboarding.value
      ).toBe(true);
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
