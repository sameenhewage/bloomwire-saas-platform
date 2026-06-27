import { ref } from 'vue';
import { shallowMount } from '@vue/test-utils';
import InboxIndex from '../Index.vue';
import {
  useMapGetter,
  useStoreGetters,
  useStore,
} from 'dashboard/composables/store';
import { useAdmin } from 'dashboard/composables/useAdmin';
import { useBloomwireCapabilities } from 'dashboard/composables/useBloomwireCapabilities';

vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('dashboard/composables/store');
vi.mock('dashboard/composables/useAdmin');
vi.mock('dashboard/composables/useBloomwireCapabilities');

const inboxOf = channelType => ({
  id: 1,
  name: 'Test Inbox',
  channel_type: channelType,
});

const mountList = (channelType, canDeleteManagedProviderInbox = false) => {
  useMapGetter.mockReturnValue(ref([inboxOf(channelType)]));
  useStoreGetters.mockReturnValue({
    'inboxes/getUIFlags': ref({ isFetching: false }),
  });
  useStore.mockReturnValue({ dispatch: vi.fn() });
  useAdmin.mockReturnValue({ isAdmin: ref(true) });
  useBloomwireCapabilities.mockReturnValue({
    canDeleteManagedProviderInbox: ref(canDeleteManagedProviderInbox),
  });

  return shallowMount(InboxIndex, {
    global: {
      mocks: { $t: key => key },
      stubs: {
        SettingsLayout: {
          template: '<div><slot name="header" /><slot name="body" /></div>',
        },
        BaseSettingsHeader: { template: '<div><slot name="actions" /></div>' },
        Avatar: true,
        ChannelName: true,
        ChannelIcon: true,
        'router-link': { template: '<a><slot /></a>' },
        'woot-confirm-delete-modal': true,
      },
    },
  });
};

const hasDeleteButton = wrapper =>
  wrapper
    .findAllComponents({ name: 'Button' })
    .some(b => b.props('icon') === 'i-woot-bin');

describe('Inbox Index.vue (Bloomwire managed-inbox delete hiding)', () => {
  it('hides delete for a managed/provider inbox when delete is Ops-managed', () => {
    expect(hasDeleteButton(mountList('Channel::Whatsapp', false))).toBe(false);
  });

  it('keeps delete for a web_widget inbox even when Ops-managed (self-service)', () => {
    expect(hasDeleteButton(mountList('Channel::WebWidget', false))).toBe(true);
  });

  it('keeps delete for an API inbox even when Ops-managed (self-service)', () => {
    expect(hasDeleteButton(mountList('Channel::Api', false))).toBe(true);
  });

  it('keeps delete for a managed/provider inbox when capability allows (stock/managed-off)', () => {
    expect(hasDeleteButton(mountList('Channel::Whatsapp', true))).toBe(true);
  });
});
