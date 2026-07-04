import { ref } from 'vue';
import { shallowMount } from '@vue/test-utils';
import ChannelList from '../ChannelList.vue';
import { useMapGetter } from 'dashboard/composables/store';
import { useAccount } from 'dashboard/composables/useAccount';
import { useBloomwireCapabilities } from 'dashboard/composables/useBloomwireCapabilities';

const pushMock = vi.fn();

vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));
vi.mock('vue-router', () => ({ useRouter: () => ({ push: pushMock }) }));
vi.mock('dashboard/composables/store');
vi.mock('dashboard/composables/useAccount');
vi.mock('dashboard/composables/useBloomwireCapabilities');

const mountList = ({
  canManageProviderSetup = true,
  canManageNativeWhatsappSetup = true,
  canCreateInbox = true,
  canSelfServeManagedWhatsapp = false,
} = {}) => {
  pushMock.mockClear();
  useMapGetter.mockReturnValue(ref({ apiChannelName: 'API' }));
  useAccount.mockReturnValue({
    accountId: ref(1),
    currentAccount: ref({ features: {} }),
  });
  useBloomwireCapabilities.mockReturnValue({
    canManageProviderSetup: ref(canManageProviderSetup),
    canManageNativeWhatsappSetup: ref(canManageNativeWhatsappSetup),
    canCreateInbox: ref(canCreateInbox),
    canSelfServeManagedWhatsapp: ref(canSelfServeManagedWhatsapp),
  });

  return shallowMount(ChannelList, {
    global: {
      mocks: { $t: key => key },
      stubs: { ChannelItem: true },
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
