import { ref } from 'vue';
import { shallowMount, flushPromises } from '@vue/test-utils';
import { useStore } from 'vuex';
import ChannelList from '../ChannelList.vue';
import { useMapGetter } from 'dashboard/composables/store';
import { useAccount } from 'dashboard/composables/useAccount';
import { useBloomwireCapabilities } from 'dashboard/composables/useBloomwireCapabilities';

const pushMock = vi.fn();

vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));
vi.mock('vue-router', () => ({ useRouter: () => ({ push: pushMock }) }));
vi.mock('vuex', () => ({ useStore: vi.fn() }));
vi.mock('dashboard/composables/store');
vi.mock('dashboard/composables/useAccount');
vi.mock('dashboard/composables/useBloomwireCapabilities');

let dispatchMock;
let capabilitiesLoadedRef;

const mountList = ({
  canManageProviderSetup = true,
  canManageNativeWhatsappSetup = true,
  canCreateInbox = true,
  canSelfServeManagedWhatsapp = false,
  // Default TRUE so the pure visibility-logic tests below render synchronously (capabilities already hydrated).
  capabilitiesLoaded = true,
  // Optional dispatch behavior for the hydration/failure/retry tests. Receives the shared capabilities ref.
  onDispatch,
} = {}) => {
  pushMock.mockClear();
  capabilitiesLoadedRef = ref(capabilitiesLoaded);
  dispatchMock = vi.fn(() =>
    onDispatch ? onDispatch(capabilitiesLoadedRef) : Promise.resolve()
  );
  useStore.mockReturnValue({ dispatch: dispatchMock });
  useMapGetter.mockReturnValue(ref({ apiChannelName: 'API' }));
  useAccount.mockReturnValue({
    accountId: ref(1),
    currentAccount: ref({ features: {} }),
  });
  useBloomwireCapabilities.mockReturnValue({
    capabilitiesLoaded: capabilitiesLoadedRef,
    canManageProviderSetup: ref(canManageProviderSetup),
    canManageNativeWhatsappSetup: ref(canManageNativeWhatsappSetup),
    canCreateInbox: ref(canCreateInbox),
    canSelfServeManagedWhatsapp: ref(canSelfServeManagedWhatsapp),
  });

  return shallowMount(ChannelList, {
    global: {
      mocks: { $t: key => key },
      stubs: {
        ChannelItem: true,
        LoadingState: true,
        NextButton: {
          template: '<button v-bind="$attrs" @click="$emit(\'click\')" />',
        },
      },
    },
  });
};

const channelKeys = wrapper =>
  wrapper
    .findAllComponents({ name: 'ChannelItem' })
    .map(c => c.props('channel').key);

describe('ChannelList.vue (Bloomwire provider/whatsapp setup hiding)', () => {
  it('shows all channel cards when capabilities are true (stock/managed-off)', () => {
    const keys = channelKeys(mountList());
    expect(keys).toEqual(
      expect.arrayContaining(['website', 'api', 'whatsapp', 'facebook', 'sms'])
    );
  });

  it('hides provider channel cards but keeps website/api when provider setup is Ops-managed', () => {
    const keys = channelKeys(mountList({ canManageProviderSetup: false }));
    expect(keys).toContain('website');
    expect(keys).toContain('api');
    expect(keys).not.toContain('facebook');
    expect(keys).not.toContain('sms');
    expect(keys).not.toContain('email');
    expect(keys).not.toContain('telegram');
    expect(keys).not.toContain('line');
    expect(keys).not.toContain('instagram');
    expect(keys).not.toContain('voice');
  });

  it('hides whatsapp setup cards when native whatsapp setup is Ops-managed', () => {
    const keys = channelKeys(
      mountList({ canManageNativeWhatsappSetup: false })
    );
    expect(keys).not.toContain('whatsapp');
    expect(keys).not.toContain('whatsapp_call');
    // provider + self-service still visible
    expect(keys).toContain('facebook');
    expect(keys).toContain('website');
  });

  it('keeps whatsapp visible while hiding providers (independent capabilities)', () => {
    const keys = channelKeys(mountList({ canManageProviderSetup: false }));
    expect(keys).toContain('whatsapp');
  });

  // Phase 11B.7C: managed mode blocks ALL inbox creation, so even website/api cards are hidden.
  it('hides every channel card (incl. website/api) when inbox creation is Ops-managed', () => {
    const keys = channelKeys(mountList({ canCreateInbox: false }));
    expect(keys).toHaveLength(0);
  });

  it('still shows website/api when only provider/whatsapp are managed but inbox creation is allowed', () => {
    const keys = channelKeys(
      mountList({
        canManageProviderSetup: false,
        canManageNativeWhatsappSetup: false,
        canCreateInbox: true,
      })
    );
    expect(keys).toContain('website');
    expect(keys).toContain('api');
  });

  // Phase 17C.3: in managed mode native whatsapp + inbox creation are restricted, but the WhatsApp card is shown
  // for self-serve registration when the managed capability is granted.
  it('shows the whatsapp card when canSelfServeManagedWhatsapp is true, even with native whatsapp + inbox creation restricted', () => {
    const keys = channelKeys(
      mountList({
        canManageNativeWhatsappSetup: false,
        canManageProviderSetup: false,
        canCreateInbox: false,
        canSelfServeManagedWhatsapp: true,
      })
    );
    expect(keys).toContain('whatsapp');
    // still only the managed WhatsApp registration card — not whatsapp_call, and not other restricted channels
    expect(keys).not.toContain('whatsapp_call');
    expect(keys).not.toContain('facebook');
    expect(keys).not.toContain('website');
  });

  it('does not show the whatsapp card in managed mode when self-serve is not granted', () => {
    const keys = channelKeys(
      mountList({
        canManageNativeWhatsappSetup: false,
        canCreateInbox: false,
        canSelfServeManagedWhatsapp: false,
      })
    );
    expect(keys).not.toContain('whatsapp');
  });
});

describe('ChannelList.vue (Bloomwire 17F.2A — no blank Add Inbox surface)', () => {
  const findUnavailable = wrapper =>
    wrapper.find('[data-testid="channel-unavailable"]');
  const findBack = wrapper =>
    wrapper.find('[data-testid="channel-unavailable-back"]');
  const whatsappItem = wrapper =>
    wrapper
      .findAllComponents({ name: 'ChannelItem' })
      .find(c => c.props('channel').key === 'whatsapp');

  it('renders a safe unavailable state (never blank) with a usable Back action when no channel is permitted', () => {
    const wrapper = mountList({
      canManageProviderSetup: false,
      canManageNativeWhatsappSetup: false,
      canCreateInbox: false,
      canSelfServeManagedWhatsapp: false,
    });
    // no cards permitted
    expect(channelKeys(wrapper)).toHaveLength(0);
    // but the surface is NOT blank: an explicit unavailable state is shown
    expect(findUnavailable(wrapper).exists()).toBe(true);
    // and a usable Back action is present
    expect(findBack(wrapper).exists()).toBe(true);
  });

  it('does NOT render the unavailable state when at least one channel is permitted', () => {
    const wrapper = mountList({
      canManageNativeWhatsappSetup: false,
      canManageProviderSetup: false,
      canCreateInbox: false,
      canSelfServeManagedWhatsapp: true,
    });
    expect(channelKeys(wrapper)).toContain('whatsapp');
    expect(findUnavailable(wrapper).exists()).toBe(false);
  });

  it('Back action navigates to the inbox list without creating records', async () => {
    const wrapper = mountList({
      canManageProviderSetup: false,
      canManageNativeWhatsappSetup: false,
      canCreateInbox: false,
      canSelfServeManagedWhatsapp: false,
    });
    await findBack(wrapper).trigger('click');
    expect(pushMock).toHaveBeenCalledWith({ name: 'settings_inbox_list' });
  });

  it('routes the WhatsApp card to the existing managed wizard (settings_inboxes_page_channel, sub_page=whatsapp)', () => {
    const wrapper = mountList({
      canManageNativeWhatsappSetup: false,
      canManageProviderSetup: false,
      canCreateInbox: false,
      canSelfServeManagedWhatsapp: true,
    });
    whatsappItem(wrapper).vm.$emit('channelItemClick', 'whatsapp');
    expect(pushMock).toHaveBeenCalledWith({
      name: 'settings_inboxes_page_channel',
      params: { sub_page: 'whatsapp', accountId: 1 },
    });
  });

  it('creates no records / navigation on mount (no side effects entering the launcher)', () => {
    mountList({
      canManageProviderSetup: false,
      canManageNativeWhatsappSetup: false,
      canCreateInbox: false,
      canSelfServeManagedWhatsapp: false,
    });
    expect(pushMock).not.toHaveBeenCalled();
  });
});

// Deterministic-state fix: the WhatsApp tile must not intermittently disappear while server-derived
// capabilities (which live only on the account-show payload) are still hydrating. A loading skeleton is shown
// during hydration (never the empty "managed by Ops" surface), and an authoritative failure yields a
// recoverable error with retry — not a silent empty page.
describe('ChannelList.vue (deterministic WhatsApp tile — capability hydration race)', () => {
  // Managed admin (account-1 shape): WhatsApp is the ONLY permitted tile, via canSelfServeManagedWhatsapp.
  const MANAGED_ADMIN = {
    canManageNativeWhatsappSetup: false,
    canManageProviderSetup: false,
    canCreateInbox: false,
    canSelfServeManagedWhatsapp: true,
  };
  const loading = w => w.find('[data-testid="channel-loading"]').exists();
  const errorState = w => w.find('[data-testid="channel-load-error"]').exists();
  const empty = w => w.find('[data-testid="channel-unavailable"]').exists();
  const retry = w => w.find('[data-testid="channel-load-retry"]');

  // (1) delayed account hydration → tile appears after loading (never the empty state during the wait)
  it('shows a loading state (not the empty surface) then the WhatsApp tile once capabilities hydrate', async () => {
    const wrapper = mountList({
      ...MANAGED_ADMIN,
      capabilitiesLoaded: false,
      onDispatch: capsRef => {
        capsRef.value = true;
        return Promise.resolve();
      },
    });
    expect(loading(wrapper)).toBe(true);
    expect(empty(wrapper)).toBe(false);
    expect(channelKeys(wrapper)).toHaveLength(0);

    await flushPromises();
    expect(loading(wrapper)).toBe(false);
    expect(channelKeys(wrapper)).toContain('whatsapp');
    expect(empty(wrapper)).toBe(false);
  });

  // (2) delayed feature/config hydration → the account-show fetch is dispatched exactly once, tile once
  it('fetches the authoritative account exactly once and renders the WhatsApp tile a single time', async () => {
    const wrapper = mountList({
      ...MANAGED_ADMIN,
      capabilitiesLoaded: false,
      onDispatch: capsRef => {
        capsRef.value = true;
        return Promise.resolve();
      },
    });
    await flushPromises();
    expect(dispatchMock).toHaveBeenCalledTimes(1);
    expect(dispatchMock).toHaveBeenCalledWith('accounts/get', {});
    expect(channelKeys(wrapper).filter(k => k === 'whatsapp')).toHaveLength(1);
  });

  // (3) already-hydrated (fast path / different resolve order) → same final list, no fetch, no loading flash
  it('renders the same final WhatsApp tile with no fetch when capabilities are already hydrated', async () => {
    const wrapper = mountList({ ...MANAGED_ADMIN, capabilitiesLoaded: true });
    await flushPromises();
    expect(dispatchMock).not.toHaveBeenCalled();
    expect(loading(wrapper)).toBe(false);
    expect(channelKeys(wrapper)).toContain('whatsapp');
  });

  // (4) transient request failure (swallowed by accounts/get; caps never arrive) → visible error, not empty
  it('shows a recoverable error (never a blank/empty page) when capabilities never hydrate', async () => {
    const wrapper = mountList({
      ...MANAGED_ADMIN,
      capabilitiesLoaded: false,
      onDispatch: () => Promise.resolve(), // resolves, but caps stay absent (silent failure)
    });
    await flushPromises();
    expect(errorState(wrapper)).toBe(true);
    expect(retry(wrapper).exists()).toBe(true);
    expect(empty(wrapper)).toBe(false);
    expect(loading(wrapper)).toBe(false);
    expect(channelKeys(wrapper)).toHaveLength(0);
  });

  it('shows the recoverable error when the account request rejects', async () => {
    const wrapper = mountList({
      ...MANAGED_ADMIN,
      capabilitiesLoaded: false,
      onDispatch: () => Promise.reject(new Error('network')),
    });
    await flushPromises();
    expect(errorState(wrapper)).toBe(true);
    expect(empty(wrapper)).toBe(false);
  });

  // (5) retry after failure → tile appears
  it('recovers on retry: the WhatsApp tile appears after a successful retry', async () => {
    let calls = 0;
    const wrapper = mountList({
      ...MANAGED_ADMIN,
      capabilitiesLoaded: false,
      onDispatch: capsRef => {
        calls += 1;
        if (calls > 1) capsRef.value = true; // succeeds on retry
        return Promise.resolve();
      },
    });
    await flushPromises();
    expect(errorState(wrapper)).toBe(true);

    await retry(wrapper).trigger('click');
    await flushPromises();
    expect(errorState(wrapper)).toBe(false);
    expect(channelKeys(wrapper)).toContain('whatsapp');
  });

  // (6) eligible admin (hydrated) → WhatsApp tile visible
  it('shows the WhatsApp tile for an eligible managed admin (hydrated)', async () => {
    const wrapper = mountList({ ...MANAGED_ADMIN, capabilitiesLoaded: true });
    await flushPromises();
    expect(channelKeys(wrapper)).toContain('whatsapp');
  });

  // (7) unauthorized agent → tile hidden/blocked (agent: every managed capability false)
  it('keeps the WhatsApp tile hidden/blocked for an unauthorized agent (no self-serve, no create)', async () => {
    const wrapper = mountList({
      canManageNativeWhatsappSetup: false,
      canManageProviderSetup: false,
      canCreateInbox: false,
      canSelfServeManagedWhatsapp: false,
      capabilitiesLoaded: true,
    });
    await flushPromises();
    expect(channelKeys(wrapper)).not.toContain('whatsapp');
    // and it fails safe to the explicit unavailable state (never a blank surface)
    expect(empty(wrapper)).toBe(true);
    expect(loading(wrapper)).toBe(false);
  });

  // (8) repeated mounts / browser-refresh-equivalent initialization → deterministic tile each time
  it('renders the WhatsApp tile deterministically across repeated mounts (refresh-equivalent)', async () => {
    for (let i = 0; i < 5; i += 1) {
      const wrapper = mountList({
        ...MANAGED_ADMIN,
        capabilitiesLoaded: false,
        onDispatch: capsRef => {
          capsRef.value = true;
          return Promise.resolve();
        },
      });
      // eslint-disable-next-line no-await-in-loop
      await flushPromises();
      expect(channelKeys(wrapper)).toContain('whatsapp');
      expect(empty(wrapper)).toBe(false);
    }
  });

  // (9) account switch → no stale provider state (a fresh mount computes from the new account's capabilities)
  it('does not carry stale provider state across an account switch', async () => {
    // first account: agent (no whatsapp)
    const first = mountList({
      canManageNativeWhatsappSetup: false,
      canManageProviderSetup: false,
      canCreateInbox: false,
      canSelfServeManagedWhatsapp: false,
      capabilitiesLoaded: true,
    });
    await flushPromises();
    expect(channelKeys(first)).not.toContain('whatsapp');

    // switch to a managed admin account: whatsapp must appear (no stale "hidden")
    const second = mountList({ ...MANAGED_ADMIN, capabilitiesLoaded: true });
    await flushPromises();
    expect(channelKeys(second)).toContain('whatsapp');
  });

  // (10) no regression to Standard/Coexistence selection: the WhatsApp card still routes to the managed wizard
  it('still routes the WhatsApp card to the managed wizard (Standard/Coexistence entry unchanged)', async () => {
    const wrapper = mountList({ ...MANAGED_ADMIN, capabilitiesLoaded: true });
    await flushPromises();
    const wa = wrapper
      .findAllComponents({ name: 'ChannelItem' })
      .find(c => c.props('channel').key === 'whatsapp');
    wa.vm.$emit('channelItemClick', 'whatsapp');
    expect(pushMock).toHaveBeenCalledWith({
      name: 'settings_inboxes_page_channel',
      params: { sub_page: 'whatsapp', accountId: 1 },
    });
  });
});
