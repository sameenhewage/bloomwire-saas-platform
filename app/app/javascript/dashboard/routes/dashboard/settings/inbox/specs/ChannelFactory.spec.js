import { ref } from 'vue';
import { shallowMount } from '@vue/test-utils';
import ChannelFactory from '../ChannelFactory.vue';
import { useBloomwireCapabilities } from 'dashboard/composables/useBloomwireCapabilities';

vi.mock('dashboard/composables/useBloomwireCapabilities');

const mountFactory = (
  channelName,
  { canManageProviderSetup = true, canManageNativeWhatsappSetup = true } = {}
) => {
  useBloomwireCapabilities.mockReturnValue({
    canManageProviderSetup: ref(canManageProviderSetup),
    canManageNativeWhatsappSetup: ref(canManageNativeWhatsappSetup),
  });

  return shallowMount(ChannelFactory, {
    props: { channelName },
    global: { mocks: { $t: key => key } },
  });
};

const isBlocked = wrapper => wrapper.text().includes('MANAGED_BY_OPS');

describe('ChannelFactory.vue (Bloomwire direct-route setup guard)', () => {
  it('renders the channel setup form when capabilities allow (stock/managed-off)', () => {
    expect(isBlocked(mountFactory('sms'))).toBe(false);
    expect(isBlocked(mountFactory('whatsapp'))).toBe(false);
  });

  it('shows the managed-by-ops state for a provider channel when provider setup is Ops-managed', () => {
    const wrapper = mountFactory('sms', { canManageProviderSetup: false });
    expect(isBlocked(wrapper)).toBe(true);
  });

  it('shows the managed-by-ops state for whatsapp when native whatsapp setup is Ops-managed', () => {
    const wrapper = mountFactory('whatsapp', {
      canManageNativeWhatsappSetup: false,
    });
    expect(isBlocked(wrapper)).toBe(true);
  });

  it('always renders self-service channels (website/api) even when both capabilities are Ops-managed', () => {
    const opts = {
      canManageProviderSetup: false,
      canManageNativeWhatsappSetup: false,
    };
    expect(isBlocked(mountFactory('website', opts))).toBe(false);
    expect(isBlocked(mountFactory('api', opts))).toBe(false);
  });

  it('does not block whatsapp when only provider setup is Ops-managed (independent capabilities)', () => {
    const wrapper = mountFactory('whatsapp', {
      canManageProviderSetup: false,
    });
    expect(isBlocked(wrapper)).toBe(false);
  });
});
