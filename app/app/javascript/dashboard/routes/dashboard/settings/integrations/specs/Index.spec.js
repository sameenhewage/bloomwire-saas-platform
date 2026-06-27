import { ref } from 'vue';
import { shallowMount } from '@vue/test-utils';
import IntegrationsIndex from '../Index.vue';
import { useStore, useStoreGetters } from 'dashboard/composables/store';
import { useBloomwireCapabilities } from 'dashboard/composables/useBloomwireCapabilities';

vi.mock('dashboard/composables/store');
vi.mock('dashboard/composables/useBloomwireCapabilities');
vi.mock('shared/composables/useBranding', () => ({
  useBranding: () => ({ replaceInstallationName: s => s }),
}));

const dispatch = vi.fn();

const mountIndex = (canAccessIntegrations = true) => {
  dispatch.mockClear();
  useStore.mockReturnValue({ dispatch });
  useStoreGetters.mockReturnValue({
    'integrations/getUIFlags': ref({ isFetching: false }),
    'integrations/getAppIntegrations': ref([]),
  });
  useBloomwireCapabilities.mockReturnValue({
    canAccessIntegrations: ref(canAccessIntegrations),
  });

  return shallowMount(IntegrationsIndex, {
    global: {
      mocks: { $t: key => key },
      stubs: {
        SettingsLayout: {
          template: '<div><slot name="header" /><slot name="body" /></div>',
        },
        BaseSettingsHeader: true,
        IntegrationItem: true,
      },
    },
  });
};

describe('integrations/Index.vue (Bloomwire 11B.7E — integrations Ops-owned)', () => {
  it('shows the catalog and fetches when integrations are allowed (stock/managed-off)', () => {
    const wrapper = mountIndex(true);
    expect(wrapper.text()).not.toContain(
      'INTEGRATION_SETTINGS.MANAGED_BY_OPS.TITLE'
    );
    expect(dispatch).toHaveBeenCalledWith('integrations/get');
  });

  it('shows the managed-by-ops state and does not fetch the catalog when Ops-managed', () => {
    const wrapper = mountIndex(false);
    expect(wrapper.text()).toContain(
      'INTEGRATION_SETTINGS.MANAGED_BY_OPS.TITLE'
    );
    expect(dispatch).not.toHaveBeenCalled();
  });
});
