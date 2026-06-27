import { ref } from 'vue';
import { shallowMount } from '@vue/test-utils';
import BotIndex from '../Index.vue';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useBloomwireCapabilities } from 'dashboard/composables/useBloomwireCapabilities';

vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('dashboard/composables/store');
vi.mock('dashboard/composables/useBloomwireCapabilities');

const dispatch = vi.fn();

const mountIndex = (canManageBots = true) => {
  dispatch.mockClear();
  useStore.mockReturnValue({ dispatch });
  useMapGetter.mockImplementation(key => {
    if (key === 'agentBots/getUIFlags') return ref({ isFetching: false });
    return ref([]); // agentBots/getBots
  });
  useBloomwireCapabilities.mockReturnValue({
    canManageBots: ref(canManageBots),
  });

  return shallowMount(BotIndex, {
    global: {
      mocks: { $t: key => key },
      stubs: {
        SettingsLayout: {
          template: '<div><slot name="header" /><slot name="body" /></div>',
        },
        BaseSettingsHeader: { template: '<div><slot name="actions" /></div>' },
        Button: true,
        Avatar: true,
        AgentBotModal: true,
        Dialog: true,
        BaseTable: true,
        BaseTableRow: true,
        BaseTableCell: true,
      },
    },
  });
};

const addButtonShown = wrapper =>
  wrapper
    .findAllComponents({ name: 'Button' })
    .some(b => b.props('label') === 'AGENT_BOTS.ADD.TITLE');

describe('agentBots/Index.vue (Bloomwire 11B.7D — bots Ops-owned)', () => {
  it('shows the bots page and Add button + fetches when bot management is allowed (stock/managed-off)', () => {
    const wrapper = mountIndex(true);
    expect(wrapper.text()).not.toContain('AGENT_BOTS.MANAGED_BY_OPS.TITLE');
    expect(addButtonShown(wrapper)).toBe(true);
    expect(dispatch).toHaveBeenCalledWith('agentBots/get');
  });

  it('route-blocks with a managed-by-ops state (no Add button) when Ops-managed', () => {
    const wrapper = mountIndex(false);
    expect(wrapper.text()).toContain('AGENT_BOTS.MANAGED_BY_OPS.TITLE');
    expect(addButtonShown(wrapper)).toBe(false);
  });

  it('does not call the secret-exposing bot list endpoint when Ops-managed', () => {
    mountIndex(false);
    expect(dispatch).not.toHaveBeenCalledWith('agentBots/get');
  });
});
