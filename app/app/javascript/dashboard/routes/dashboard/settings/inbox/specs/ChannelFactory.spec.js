import { ref } from 'vue';
import { shallowMount } from '@vue/test-utils';
import ChannelFactory from '../ChannelFactory.vue';
import Whatsapp from '../channels/Whatsapp.vue';
import BloomwireWhatsapp from '../channels/BloomwireWhatsapp.vue';
import { useBloomwireCapabilities } from 'dashboard/composables/useBloomwireCapabilities';

vi.mock('dashboard/composables/useBloomwireCapabilities');

const mountFactory = (
  channelName,
  {
    canManageProviderSetup = true,
    canManageNativeWhatsappSetup = true,
    canCreateInbox = true,
    canSelfServeManagedWhatsapp = false,
  } = {}
) => {
  useBloomwireCapabilities.mockReturnValue({
    canManageProviderSetup: ref(canManageProviderSetup),
    canManageNativeWhatsappSetup: ref(canManageNativeWhatsappSetup),
    canCreateInbox: ref(canCreateInbox),
    canSelfServeManagedWhatsapp: ref(canSelfServeManagedWhatsapp),
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

  // Phase 11B.7C: direct website/api routes are blocked when ALL inbox creation is Ops-owned.
  it('shows the managed-by-ops state for website/api when inbox creation is Ops-managed', () => {
    expect(isBlocked(mountFactory('website', { canCreateInbox: false }))).toBe(
      true
    );
    expect(isBlocked(mountFactory('api', { canCreateInbox: false }))).toBe(
      true
    );
  });

  // Phase 17C.3: managed self-serve WhatsApp registration wizard.
  describe('managed self-serve WhatsApp (17C.3)', () => {
    it('renders the Bloomwire registration wizard for whatsapp when self-serve is granted, even with native whatsapp + inbox creation restricted', () => {
      const wrapper = mountFactory('whatsapp', {
        canManageNativeWhatsappSetup: false,
        canCreateInbox: false,
        canSelfServeManagedWhatsapp: true,
      });
      expect(isBlocked(wrapper)).toBe(false);
      expect(wrapper.findComponent(BloomwireWhatsapp).exists()).toBe(true);
      expect(wrapper.findComponent(Whatsapp).exists()).toBe(false);
    });

    it('renders the native WhatsApp component (not the managed wizard) when self-serve is not granted', () => {
      const wrapper = mountFactory('whatsapp'); // canSelfServeManagedWhatsapp defaults false
      expect(wrapper.findComponent(BloomwireWhatsapp).exists()).toBe(false);
      expect(wrapper.findComponent(Whatsapp).exists()).toBe(true);
    });

    it('does not swap whatsapp_call to the managed wizard', () => {
      const wrapper = mountFactory('whatsapp_call', {
        canSelfServeManagedWhatsapp: true,
        canManageNativeWhatsappSetup: true,
      });
      expect(wrapper.findComponent(BloomwireWhatsapp).exists()).toBe(false);
    });
  });
});
