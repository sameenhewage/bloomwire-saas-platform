import { ref } from 'vue';
import { shallowMount } from '@vue/test-utils';
import AccountIndex from '../Index.vue';
import { useBloomwireCapabilities } from 'dashboard/composables/useBloomwireCapabilities';

vi.mock('@vuelidate/core', () => ({
  useVuelidate: () => ({
    name: { $error: false, $touch: vi.fn() },
    locale: { $error: false },
    $touch: vi.fn(),
    $invalid: false,
  }),
}));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('dashboard/composables/useUISettings', () => ({
  useUISettings: () => ({ updateUISettings: vi.fn(), uiSettings: {} }),
}));
vi.mock('dashboard/composables/useConfig', () => ({
  useConfig: () => ({ enabledLanguages: [] }),
}));
vi.mock('dashboard/composables/useAccount', () => ({
  useAccount: () => ({ accountId: ref(1) }),
}));
vi.mock('dashboard/composables/useBloomwireCapabilities');

const account = {
  id: 1,
  name: 'Acme',
  locale: '',
  domain: '',
  support_email: '',
  features: {},
};

const mountAccount = (canManageAccountControlPlane = true) => {
  useBloomwireCapabilities.mockReturnValue({
    canManageAccountControlPlane: ref(canManageAccountControlPlane),
  });
  return shallowMount(AccountIndex, {
    global: {
      mocks: {
        $t: key => key,
        $store: {
          getters: {
            'accounts/getAccount': () => account,
            'accounts/getUIFlags': { isUpdating: false, isFetchingItem: false },
            'accounts/isFeatureEnabledonAccount': () => false,
            'globalConfig/isOnChatwootCloud': false,
          },
        },
      },
      stubs: {
        SectionLayout: { template: '<div><slot /></div>' },
        WithLabel: { template: '<div><slot /><slot name="help" /></div>' },
        NextInput: {
          props: ['disabled', 'modelValue'],
          template: '<input class="acc-input" :disabled="disabled" />',
        },
        NextButton: { template: '<button class="save-btn"><slot /></button>' },
        BaseSettingsHeader: true,
        AccountId: true,
        BuildInfo: true,
        AccountDelete: true,
        AudioTranscription: true,
        'woot-loading-state': true,
      },
    },
  });
};

const nameInput = wrapper => wrapper.find('.acc-input');

describe('Account Index.vue (Bloomwire account-name immutable)', () => {
  it('disables the account name input when account control-plane is Ops-managed', () => {
    expect(nameInput(mountAccount(false)).element.disabled).toBe(true);
  });

  it('keeps the account name input editable when manageable (capability true / stock-safe absent)', () => {
    expect(nameInput(mountAccount(true)).element.disabled).toBe(false);
  });

  it('shows a managed-by-ops helper message when Ops-managed', () => {
    expect(mountAccount(false).text()).toContain('MANAGED_BY_OPS');
  });

  it('does not show the managed-by-ops helper when manageable', () => {
    expect(mountAccount(true).text()).not.toContain('MANAGED_BY_OPS');
  });

  it('hides the save button when Ops-managed and shows it when manageable', () => {
    expect(mountAccount(false).find('.save-btn').exists()).toBe(false);
    expect(mountAccount(true).find('.save-btn').exists()).toBe(true);
  });
});
