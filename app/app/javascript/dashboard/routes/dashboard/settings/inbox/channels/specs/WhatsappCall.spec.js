import { mount } from '@vue/test-utils';
import { describe, it, expect, vi } from 'vitest';
import { ref } from 'vue';
import WhatsappCall from '../WhatsappCall.vue';

const isBloomwireManagedAccount = ref(false);

vi.mock('dashboard/composables/useAccount', () => ({
  useAccount: () => ({ isBloomwireManagedAccount }),
}));

// Module-mock the embedded signup so its transitive imports (router/store) do not
// load in this unit test.
vi.mock('../WhatsappEmbeddedSignup.vue', () => ({
  default: { template: '<div class="embedded-signup" />' },
}));

const mountWhatsappCall = () =>
  mount(WhatsappCall, {
    global: {
      mocks: { $t: key => key },
    },
  });

describe('WhatsappCall setup route — Bloomwire-managed hiding (4.4-b-WA.2D)', () => {
  it('renders the WhatsApp Call embedded signup for a plain (non-managed) account', () => {
    isBloomwireManagedAccount.value = false;

    const wrapper = mountWhatsappCall();

    expect(wrapper.find('.embedded-signup').exists()).toBe(true);
    expect(wrapper.html()).not.toContain('INBOX_MGMT.BLOOMWIRE_MANAGED.NOTICE');
  });

  it('shows only the managed notice (no embedded signup) for a Bloomwire-managed account', () => {
    isBloomwireManagedAccount.value = true;

    const wrapper = mountWhatsappCall();

    expect(wrapper.html()).toContain('INBOX_MGMT.BLOOMWIRE_MANAGED.NOTICE');
    expect(wrapper.find('.embedded-signup').exists()).toBe(false);
  });
});
