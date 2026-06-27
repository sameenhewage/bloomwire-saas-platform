import { ref } from 'vue';
import { shallowMount } from '@vue/test-utils';
import ChannelList from '../ChannelList.vue';
import { useMapGetter } from 'dashboard/composables/store';
import { useAccount } from 'dashboard/composables/useAccount';
import { useBloomwireCapabilities } from 'dashboard/composables/useBloomwireCapabilities';

vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));
vi.mock('vue-router', () => ({ useRouter: () => ({ push: vi.fn() }) }));
vi.mock('dashboard/composables/store');
vi.mock('dashboard/composables/useAccount');
vi.mock('dashboard/composables/useBloomwireCapabilities');

const mountList = ({
  canManageProviderSetup = true,
  canManageNativeWhatsappSetup = true,
  canCreateInbox = true,
} = {}) => {
  useMapGetter.mockReturnValue(ref({ apiChannelName: 'API' }));
  useAccount.mockReturnValue({
    accountId: ref(1),
    currentAccount: ref({ features: {} }),
  });
  useBloomwireCapabilities.mockReturnValue({
    canManageProviderSetup: ref(canManageProviderSetup),
    canManageNativeWhatsappSetup: ref(canManageNativeWhatsappSetup),
    canCreateInbox: ref(canCreateInbox),
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
});
