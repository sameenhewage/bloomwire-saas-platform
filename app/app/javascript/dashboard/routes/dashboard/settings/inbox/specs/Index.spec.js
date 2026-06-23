import { mount } from '@vue/test-utils';
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { computed } from 'vue';
import Index from '../Index.vue';

const state = vi.hoisted(() => ({ inboxes: [], isAdmin: true }));

vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: key => key }),
}));

vi.mock('dashboard/composables', () => ({
  useAlert: () => {},
}));

vi.mock('dashboard/composables/useAdmin', () => ({
  useAdmin: () => ({ isAdmin: computed(() => state.isAdmin) }),
}));

vi.mock('dashboard/composables/store', () => ({
  useMapGetter: () => computed(() => state.inboxes),
  useStoreGetters: () => ({
    'inboxes/getUIFlags': computed(() => ({ isFetching: false })),
  }),
  useStore: () => ({ dispatch: vi.fn() }),
}));

const stubs = {
  SettingsLayout: {
    template: '<div><slot name="header" /><slot name="body" /></div>',
  },
  BaseSettingsHeader: {
    template: '<div><slot name="actions" /><slot name="count" /></div>',
  },
  Avatar: true,
  ChannelName: true,
  ChannelIcon: true,
  Button: {
    props: ['icon'],
    template: '<button :data-icon="icon"><slot /></button>',
  },
  'router-link': { template: '<a><slot /></a>' },
  RouterLink: { template: '<a><slot /></a>' },
  'woot-confirm-delete-modal': true,
};

const mountIndex = () =>
  mount(Index, {
    global: {
      mocks: { $t: key => key },
      stubs,
    },
  });

const deleteButtonCount = wrapper =>
  wrapper.findAll('[data-icon="i-woot-bin"]').length;

describe('Inbox Index — Bloomwire-managed WhatsApp delete hiding (4.4-b-WA.2D)', () => {
  beforeEach(() => {
    state.isAdmin = true;
    state.inboxes = [];
  });

  it('hides the delete action for a Bloomwire-managed WhatsApp inbox', () => {
    state.inboxes = [
      {
        id: 1,
        name: 'WA Managed',
        channel_type: 'Channel::Whatsapp',
        bloomwire_managed: true,
      },
    ];

    expect(deleteButtonCount(mountIndex())).toBe(0);
  });

  it('shows the delete action for a non-managed WhatsApp inbox', () => {
    state.inboxes = [
      {
        id: 2,
        name: 'WA Plain',
        channel_type: 'Channel::Whatsapp',
        bloomwire_managed: false,
      },
    ];

    expect(deleteButtonCount(mountIndex())).toBe(1);
  });

  it('shows the delete action for a non-WhatsApp inbox (flag absent)', () => {
    state.inboxes = [
      { id: 3, name: 'Website', channel_type: 'Channel::WebWidget' },
    ];

    expect(deleteButtonCount(mountIndex())).toBe(1);
  });

  it('hides delete only for the managed WhatsApp inbox in a mixed list', () => {
    state.inboxes = [
      {
        id: 1,
        name: 'WA Managed',
        channel_type: 'Channel::Whatsapp',
        bloomwire_managed: true,
      },
      {
        id: 2,
        name: 'WA Plain',
        channel_type: 'Channel::Whatsapp',
        bloomwire_managed: false,
      },
      { id: 3, name: 'Website', channel_type: 'Channel::WebWidget' },
    ];

    expect(deleteButtonCount(mountIndex())).toBe(2);
  });
});
