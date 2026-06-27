import { ref } from 'vue';
import { shallowMount } from '@vue/test-utils';
import MultipleIntegrationHooks from '../MultipleIntegrationHooks.vue';
import { useMapGetter } from 'dashboard/composables/store';
import { useIntegrationHook } from 'dashboard/composables/useIntegrationHook';
import { useBloomwireCapabilities } from 'dashboard/composables/useBloomwireCapabilities';

vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));
vi.mock('dashboard/composables/store');
vi.mock('dashboard/composables/useIntegrationHook');
vi.mock('dashboard/composables/useBloomwireCapabilities');

const mountHooks = (canManageProviderSetup = true) => {
  useMapGetter.mockReturnValue(ref({ installationName: 'Chatwoot' }));
  useIntegrationHook.mockReturnValue({
    integration: ref({ name: 'OpenAI', visible_properties: [], hooks: [] }),
    isHookTypeInbox: ref(false),
    hasConnectedHooks: ref(false),
  });
  useBloomwireCapabilities.mockReturnValue({
    canManageProviderSetup: ref(canManageProviderSetup),
  });
  return shallowMount(MultipleIntegrationHooks, {
    props: { integrationId: 'openai', showAddButton: true },
    global: {
      mocks: { $t: key => key },
      stubs: {
        BaseSettingsHeader: { template: '<div><slot name="actions" /></div>' },
        NextButton: { template: '<button class="add-hook-btn" />' },
      },
    },
  });
};

describe('MultipleIntegrationHooks.vue (Bloomwire provider add hiding)', () => {
  it('shows the add button when provider setup is allowed (stock/managed-off)', () => {
    expect(mountHooks(true).findAll('.add-hook-btn')).toHaveLength(1);
  });

  it('hides the add button when provider setup is Ops-managed', () => {
    expect(mountHooks(false).findAll('.add-hook-btn')).toHaveLength(0);
  });
});
