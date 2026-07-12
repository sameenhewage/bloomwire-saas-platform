import { ref } from 'vue';
import { createStore } from 'vuex';
import { flushPromises, shallowMount } from '@vue/test-utils';
import CollaboratorsPage from '../CollaboratorsPage.vue';
import { useBloomwireCapabilities } from 'dashboard/composables/useBloomwireCapabilities';

vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));
vi.mock('vue-router', () => ({
  useRoute: () => ({ params: { accountId: '1' } }),
  useRouter: () => ({ push: vi.fn() }),
}));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('dashboard/composables/useConfig', () => ({
  useConfig: () => ({ isEnterprise: false }),
}));
vi.mock('dashboard/composables/useBloomwireCapabilities');

const DEFAULT_RULE_1 = 'INBOX_MGMT.ASSIGNMENT.DEFAULT_RULE_1';
const DEFAULT_RULE_2 = 'INBOX_MGMT.ASSIGNMENT.DEFAULT_RULE_2';
const UPGRADE_PROMPT = 'INBOX_MGMT.ASSIGNMENT.UPGRADE_PROMPT';
const UPGRADE_BUTTON = 'INBOX_MGMT.ASSIGNMENT.UPGRADE_TO_BUSINESS';

const createTestStore = () =>
  createStore({
    modules: {
      accounts: {
        namespaced: true,
        getters: {
          isFeatureEnabledonAccount: () => (_accountId, feature) =>
            feature === 'assignment_v2',
        },
      },
      agents: {
        namespaced: true,
        getters: { getAgents: () => [] },
      },
      inboxMembers: {
        namespaced: true,
        actions: {
          get: () => Promise.resolve({ data: { payload: [] } }),
        },
      },
    },
  });

const mountPage = async canViewChatwootPlanUpsell => {
  useBloomwireCapabilities.mockReturnValue({
    canViewChatwootPlanUpsell: ref(canViewChatwootPlanUpsell),
  });

  const wrapper = shallowMount(CollaboratorsPage, {
    props: {
      inbox: {
        id: 50,
        enable_auto_assignment: true,
        auto_assignment_config: {},
      },
    },
    global: {
      plugins: [createTestStore()],
      mocks: { $t: key => key },
      stubs: {
        SettingsFieldSection: {
          template: '<section><slot /><slot name="extra" /></section>',
        },
        SettingsAccordion: { template: '<section><slot /></section>' },
        SettingsToggleSection: {
          template: '<section><slot name="editor" /></section>',
        },
        NextButton: {
          props: ['label'],
          template: '<button>{{ label }}<slot /></button>',
        },
        TagInput: true,
        DropdownMenu: true,
        Icon: true,
        'woot-modal': true,
        'woot-input': true,
      },
    },
  });
  await flushPromises();
  return wrapper;
};

describe('CollaboratorsPage Bloomwire plan upsell', () => {
  it('keeps default assignment rules but hides the Chatwoot Business upsell in Bloomwire mode', async () => {
    const text = (await mountPage(false)).text();

    expect(text).toContain(DEFAULT_RULE_1);
    expect(text).toContain(DEFAULT_RULE_2);
    expect(text).not.toContain(UPGRADE_PROMPT);
    expect(text).not.toContain(UPGRADE_BUTTON);
  });

  it('preserves the Chatwoot Business upsell when Bloomwire mode is OFF', async () => {
    const text = (await mountPage(true)).text();

    expect(text).toContain(DEFAULT_RULE_1);
    expect(text).toContain(DEFAULT_RULE_2);
    expect(text).toContain(UPGRADE_PROMPT);
    expect(text).toContain(UPGRADE_BUTTON);
  });
});
