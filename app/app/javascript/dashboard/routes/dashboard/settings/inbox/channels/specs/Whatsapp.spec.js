import { mount } from '@vue/test-utils';
import { describe, it, expect, vi } from 'vitest';
import { ref } from 'vue';
import Whatsapp from '../Whatsapp.vue';

const isBloomwireManagedAccount = ref(false);

vi.mock('dashboard/composables/useAccount', () => ({
  useAccount: () => ({ isBloomwireManagedAccount }),
}));

// Module-mock the heavy child channel components so their transitive imports
// (e.g. Twilio.vue -> routes index -> createRouter) do not load in this unit test.
vi.mock('../Twilio.vue', () => ({
  default: { template: '<div class="twilio" />' },
}));
vi.mock('../360DialogWhatsapp.vue', () => ({
  default: { template: '<div class="three-sixty" />' },
}));
vi.mock('../CloudWhatsapp.vue', () => ({
  default: { template: '<div class="cloud-whatsapp" />' },
}));
vi.mock('../WhatsappEmbeddedSignup.vue', () => ({
  default: { template: '<div class="embedded-signup" />' },
}));
vi.mock('dashboard/components/ChannelSelector.vue', () => ({
  default: { template: '<div class="channel-selector" />' },
}));

vi.mock('vue-router', () => ({
  useRoute: () => ({
    query: {},
    params: {},
    name: 'settings_inboxes_page_channel',
  }),
  useRouter: () => ({ push: vi.fn() }),
}));

vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: key => key }),
  I18nT: { template: '<span><slot /></span>' },
}));

const stubs = {
  Twilio: true,
  ThreeSixtyDialogWhatsapp: true,
  CloudWhatsapp: { template: '<div class="cloud-whatsapp" />' },
  WhatsappEmbeddedSignup: { template: '<div class="embedded-signup" />' },
  ChannelSelector: { template: '<div class="channel-selector" />' },
  I18nT: { template: '<span><slot /></span>' },
};

const mountWhatsapp = () =>
  mount(Whatsapp, {
    global: {
      mocks: { $t: key => key },
      stubs,
    },
  });

describe('Whatsapp provider page — Bloomwire-managed hiding (4.4-b-WA.2D)', () => {
  it('shows the provider selection for a plain (non-managed) account', () => {
    isBloomwireManagedAccount.value = false;

    const wrapper = mountWhatsapp();

    expect(wrapper.find('.channel-selector').exists()).toBe(true);
    expect(wrapper.html()).not.toContain('INBOX_MGMT.BLOOMWIRE_MANAGED.NOTICE');
  });

  it('shows only the managed notice for a Bloomwire-managed account', () => {
    isBloomwireManagedAccount.value = true;

    const wrapper = mountWhatsapp();

    expect(wrapper.html()).toContain('INBOX_MGMT.BLOOMWIRE_MANAGED.NOTICE');
    expect(wrapper.find('.channel-selector').exists()).toBe(false);
    expect(wrapper.find('.cloud-whatsapp').exists()).toBe(false);
    expect(wrapper.find('.embedded-signup').exists()).toBe(false);
  });
});
