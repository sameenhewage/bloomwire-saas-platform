import { ref } from 'vue';
import { shallowMount } from '@vue/test-utils';
import Integration from '../Integration.vue';
import { useBloomwireCapabilities } from 'dashboard/composables/useBloomwireCapabilities';

vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));
vi.mock('vue-router', () => ({ useRouter: () => ({ push: vi.fn() }) }));
vi.mock('vuex', () => ({
  useStore: () => ({ getters: { getCurrentAccountId: 1 }, dispatch: vi.fn() }),
}));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('shared/composables/useBranding', () => ({
  useBranding: () => ({ replaceInstallationName: x => x }),
}));
vi.mock('dashboard/composables/useBloomwireCapabilities');

const labelsOf = wrapper =>
  wrapper.findAllComponents({ name: 'Button' }).map(b => b.props('label'));

const mountIntegration = (props = {}, canManageProviderSetup = true) => {
  useBloomwireCapabilities.mockReturnValue({
    canManageProviderSetup: ref(canManageProviderSetup),
  });
  return shallowMount(Integration, {
    props: {
      integrationId: 'slack',
      integrationName: 'Slack',
      integrationEnabled: false,
      integrationAction: 'https://connect.example.com',
      ...props,
    },
    global: {
      mocks: { $t: key => key },
      stubs: { 'router-link': { template: '<a><slot /></a>' } },
    },
  });
};

const CONNECT = 'INTEGRATION_SETTINGS.CONNECT.BUTTON_TEXT';

describe('Integration.vue (Bloomwire provider connect hiding)', () => {
  it('shows the connect button when provider setup is allowed (stock/managed-off)', () => {
    expect(
      labelsOf(mountIntegration({ integrationEnabled: false }, true))
    ).toContain(CONNECT);
  });

  it('hides the connect button when provider setup is Ops-managed', () => {
    expect(
      labelsOf(mountIntegration({ integrationEnabled: false }, false))
    ).not.toContain(CONNECT);
  });

  it('keeps the disconnect button for an enabled integration even when Ops-managed', () => {
    const wrapper = mountIntegration(
      { integrationEnabled: true, integrationAction: 'disconnect' },
      false
    );
    // disconnect button still rendered (uses default delete label), connect absent
    expect(labelsOf(wrapper)).not.toContain(CONNECT);
    expect(wrapper.findAllComponents({ name: 'Button' }).length).toBe(1);
  });
});
