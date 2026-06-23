import { mount } from '@vue/test-utils';
import { describe, it, expect, vi } from 'vitest';
import { ref } from 'vue';
import ChannelList from '../ChannelList.vue';

const isBloomwireManagedAccount = ref(false);

vi.mock('dashboard/composables/useAccount', () => ({
  useAccount: () => ({
    accountId: ref(1),
    currentAccount: ref({ id: 1, features: {} }),
    isBloomwireManagedAccount,
  }),
}));

vi.mock('dashboard/composables/store', () => ({
  useMapGetter: () => ref({ apiChannelName: 'API' }),
}));

vi.mock('vue-router', () => ({
  useRouter: () => ({ push: vi.fn() }),
}));

vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: key => key }),
}));

const mountList = () =>
  mount(ChannelList, {
    global: {
      mocks: { $t: key => key },
      stubs: {
        ChannelItem: {
          props: ['channel'],
          template: '<div class="channel-item" :data-key="channel.key" />',
        },
      },
    },
  });

const renderedChannelKeys = wrapper =>
  wrapper.findAll('.channel-item').map(node => node.attributes('data-key'));

describe('ChannelList — Bloomwire-managed WhatsApp hiding (4.4-b-WA.2D)', () => {
  it('shows the WhatsApp channels for a plain (non-managed) account', () => {
    isBloomwireManagedAccount.value = false;

    const keys = renderedChannelKeys(mountList());

    expect(keys).toContain('whatsapp');
    expect(keys).toContain('whatsapp_call');
    expect(keys).toContain('website');
  });

  it('hides the WhatsApp channels for a Bloomwire-managed account', () => {
    isBloomwireManagedAccount.value = true;

    const keys = renderedChannelKeys(mountList());

    expect(keys).not.toContain('whatsapp');
    expect(keys).not.toContain('whatsapp_call');
  });

  it('keeps non-WhatsApp channels for a Bloomwire-managed account', () => {
    isBloomwireManagedAccount.value = true;

    const keys = renderedChannelKeys(mountList());

    expect(keys).toContain('website');
    expect(keys).toContain('email');
    expect(keys).toContain('sms');
  });
});
