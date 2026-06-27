import { ref } from 'vue';
import { shallowMount } from '@vue/test-utils';
import SingleIntegrationHooks from '../SingleIntegrationHooks.vue';
import { useIntegrationHook } from 'dashboard/composables/useIntegrationHook';
import { useBloomwireCapabilities } from 'dashboard/composables/useBloomwireCapabilities';

vi.mock('shared/composables/useBranding', () => ({
  useBranding: () => ({ replaceInstallationName: x => x }),
}));
vi.mock('dashboard/composables/useIntegrationHook');
vi.mock('dashboard/composables/useBloomwireCapabilities');

const labelsOf = wrapper =>
  wrapper.findAllComponents({ name: 'Button' }).map(b => b.props('label'));

const mountHooks = ({
  hasConnectedHooks = false,
  canManageProviderSetup = true,
} = {}) => {
  useIntegrationHook.mockReturnValue({
    integration: ref({
      name: 'Dialogflow',
      description: 'd',
      hooks: [{ id: 1 }],
    }),
    hasConnectedHooks: ref(hasConnectedHooks),
  });
  useBloomwireCapabilities.mockReturnValue({
    canManageProviderSetup: ref(canManageProviderSetup),
  });
  return shallowMount(SingleIntegrationHooks, {
    props: { integrationId: 'dialogflow' },
    global: { mocks: { $t: key => key } },
  });
};

const CONNECT = 'INTEGRATION_APPS.CONNECT.BUTTON_TEXT';
const DISCONNECT = 'INTEGRATION_APPS.DISCONNECT.BUTTON_TEXT';

describe('SingleIntegrationHooks.vue (Bloomwire provider connect hiding)', () => {
  it('shows connect when provider setup is allowed (stock/managed-off)', () => {
    expect(labelsOf(mountHooks())).toContain(CONNECT);
  });

  it('hides connect when provider setup is Ops-managed', () => {
    expect(
      labelsOf(mountHooks({ canManageProviderSetup: false }))
    ).not.toContain(CONNECT);
  });

  it('keeps disconnect for a connected hook even when Ops-managed', () => {
    const labels = labelsOf(
      mountHooks({ hasConnectedHooks: true, canManageProviderSetup: false })
    );
    expect(labels).toContain(DISCONNECT);
    expect(labels).not.toContain(CONNECT);
  });
});
