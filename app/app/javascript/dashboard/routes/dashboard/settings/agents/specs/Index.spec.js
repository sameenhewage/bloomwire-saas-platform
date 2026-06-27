import { ref } from 'vue';
import { shallowMount } from '@vue/test-utils';
import AgentsIndex from '../Index.vue';
import {
  useStoreGetters,
  useStore,
  useMapGetter,
} from 'dashboard/composables/store';
import { useBloomwireCapabilities } from 'dashboard/composables/useBloomwireCapabilities';

vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));
vi.mock('dashboard/composables/store');
vi.mock('dashboard/composables/useBloomwireCapabilities');
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));

const agents = [
  {
    id: 1,
    name: 'Admin One',
    email: 'a1@e.com',
    role: 'administrator',
    confirmed: true,
  },
  {
    id: 2,
    name: 'Admin Two',
    email: 'a2@e.com',
    role: 'administrator',
    confirmed: true,
  },
];

const mountIndex = (canManageAccountControlPlane = true) => {
  useBloomwireCapabilities.mockReturnValue({
    canManageAccountControlPlane: ref(canManageAccountControlPlane),
  });
  useStore.mockReturnValue({ dispatch: vi.fn() });
  useMapGetter.mockReturnValue(ref([]));
  useStoreGetters.mockReturnValue({
    'agents/getAgents': ref(agents),
    'agents/getUIFlags': ref({ isFetching: false }),
    getCurrentUserID: ref(99),
  });

  return shallowMount(AgentsIndex, {
    global: {
      mocks: { $t: key => key },
      stubs: {
        SettingsLayout: {
          template: '<div><slot name="header" /><slot name="body" /></div>',
        },
        BaseSettingsHeader: { template: '<div><slot name="actions" /></div>' },
        Avatar: true,
        AddAgent: true,
        EditAgent: true,
        Button: true,
        'woot-modal': true,
        'woot-delete-modal': true,
      },
    },
  });
};

describe('Agents/Index.vue (Bloomwire account-control hiding)', () => {
  it('shows agent add/edit/delete actions when account control-plane is manageable', () => {
    const wrapper = mountIndex(true);
    // Add (header) + edit + delete per agent
    expect(
      wrapper.findAllComponents({ name: 'Button' }).length
    ).toBeGreaterThan(0);
  });

  it('hides all agent management actions when account control-plane is Ops-managed', () => {
    const wrapper = mountIndex(false);
    expect(wrapper.findAllComponents({ name: 'Button' })).toHaveLength(0);
  });
});
