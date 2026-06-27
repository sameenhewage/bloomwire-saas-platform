import { ref } from 'vue';
import { shallowMount } from '@vue/test-utils';
import BotConfiguration from '../BotConfiguration.vue';
import { useBloomwireCapabilities } from 'dashboard/composables/useBloomwireCapabilities';

vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('dashboard/composables/useBloomwireCapabilities');

const dispatch = vi.fn();

const mountConfig = (canManageBots = true) => {
  dispatch.mockClear();
  useBloomwireCapabilities.mockReturnValue({
    canManageBots: ref(canManageBots),
  });

  return shallowMount(BotConfiguration, {
    props: { inbox: { id: 1 } },
    global: {
      mocks: {
        $t: key => key,
        $route: { params: {} },
        $store: {
          dispatch,
          getters: {
            'agentBots/getBots': [],
            'agentBots/getUIFlags': {
              isFetching: false,
              isFetchingAgentBot: false,
            },
            'agentBots/getActiveAgentBot': () => ({}),
          },
        },
      },
      stubs: {
        SettingsFieldSection: {
          template: '<div><slot /><slot name="extra" /></div>',
        },
        LoadingState: true,
        NextButton: true,
        SelectInput: true,
      },
    },
  });
};

describe('BotConfiguration.vue (Bloomwire 11B.7D — inbox bot set/disconnect)', () => {
  it('shows the bot configuration form and fetches when allowed (stock/managed-off)', () => {
    const wrapper = mountConfig(true);
    expect(wrapper.text()).not.toContain('AGENT_BOTS.MANAGED_BY_OPS.TITLE');
    expect(wrapper.find('form').exists()).toBe(true);
    expect(dispatch).toHaveBeenCalledWith('agentBots/get');
  });

  it('shows the managed-by-ops state and hides the form when Ops-managed', () => {
    const wrapper = mountConfig(false);
    expect(wrapper.text()).toContain('AGENT_BOTS.MANAGED_BY_OPS.TITLE');
    expect(wrapper.find('form').exists()).toBe(false);
  });

  it('does not fetch the secret-exposing bot data on mount when Ops-managed', () => {
    mountConfig(false);
    expect(dispatch).not.toHaveBeenCalled();
  });

  it('method guards prevent set/disconnect dispatch when Ops-managed', async () => {
    const wrapper = mountConfig(false);
    dispatch.mockClear();
    await wrapper.vm.updateActiveAgentBot();
    await wrapper.vm.disconnectBot();
    expect(dispatch).not.toHaveBeenCalled();
  });
});
