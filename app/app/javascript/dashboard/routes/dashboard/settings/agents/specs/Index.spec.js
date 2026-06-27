import { ref } from 'vue';
import { shallowMount } from '@vue/test-utils';
import AgentsIndex from '../Index.vue';
import {
  useStoreGetters,
  useStore,
  useMapGetter,
} from 'dashboard/composables/store';

vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));
vi.mock('dashboard/composables/store');
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

const mountIndex = () => {
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

// Phase 11B.7B: agent management is a business-owner capability and is NOT gated by the Bloomwire
// account-control capability anymore (only stock admin role gating applies).
describe('Agents/Index.vue (Bloomwire 11B.7B — agent management restored)', () => {
  it('renders agent management actions (not gated by the Bloomwire account-control capability)', () => {
    const wrapper = mountIndex();
    // Add (header) + edit + delete per agent → > 0
    expect(
      wrapper.findAllComponents({ name: 'Button' }).length
    ).toBeGreaterThan(0);
  });

  it('shows the Add Agent button', () => {
    const labels = mountIndex()
      .findAllComponents({ name: 'Button' })
      .map(b => b.props('label'))
      .filter(Boolean);
    expect(labels).toContain('AGENT_MGMT.HEADER_BTN_TXT');
  });

  it('shows per-agent edit and delete actions for other admins', () => {
    // currentUserId=99 (≠ agent ids) and two confirmed admins → edit + delete shown for each
    const icons = mountIndex()
      .findAllComponents({ name: 'Button' })
      .map(b => b.props('icon'))
      .filter(Boolean);
    expect(icons).toContain('i-woot-edit-pen');
    expect(icons).toContain('i-woot-bin');
  });
});
