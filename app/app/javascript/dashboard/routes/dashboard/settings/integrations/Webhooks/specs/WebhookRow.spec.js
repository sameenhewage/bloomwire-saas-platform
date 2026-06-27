import { ref } from 'vue';
import { shallowMount } from '@vue/test-utils';
import WebhookRow from '../WebhookRow.vue';
import { useBloomwireCapabilities } from 'dashboard/composables/useBloomwireCapabilities';

vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));
vi.mock('dashboard/composables/useBloomwireCapabilities');

const mountRow = (canManageAccountControlPlane = true) => {
  useBloomwireCapabilities.mockReturnValue({
    canManageAccountControlPlane: ref(canManageAccountControlPlane),
  });

  return shallowMount(WebhookRow, {
    props: {
      webhook: {
        id: 1,
        name: 'WH',
        url: 'https://example.com/hook',
        subscriptions: [],
      },
      index: 0,
    },
    global: {
      mocks: { $t: key => key },
      stubs: {
        BaseTableRow: { template: '<div><slot /></div>' },
        BaseTableCell: { template: '<div><slot /></div>' },
        ShowMore: true,
        Button: true,
      },
    },
  });
};

describe('WebhookRow.vue (Bloomwire account-control hiding)', () => {
  it('shows edit/delete actions when account control-plane is manageable', () => {
    const wrapper = mountRow(true);
    expect(wrapper.findAllComponents({ name: 'Button' })).toHaveLength(2);
  });

  it('hides edit/delete actions when account control-plane is Ops-managed', () => {
    const wrapper = mountRow(false);
    expect(wrapper.findAllComponents({ name: 'Button' })).toHaveLength(0);
  });
});
