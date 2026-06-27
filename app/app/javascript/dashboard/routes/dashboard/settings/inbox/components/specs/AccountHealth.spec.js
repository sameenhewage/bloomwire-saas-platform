import { ref } from 'vue';
import { shallowMount } from '@vue/test-utils';
import AccountHealth from '../AccountHealth.vue';
import { useBloomwireCapabilities } from 'dashboard/composables/useBloomwireCapabilities';

vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));
vi.mock('dashboard/composables/useBloomwireCapabilities');

const REGISTER = 'INBOX_MGMT.ACCOUNT_HEALTH.WEBHOOK.REGISTER_BUTTON';
const HEALTH_TITLE = 'INBOX_MGMT.ACCOUNT_HEALTH.TITLE';
const WEBHOOK_TITLE = 'INBOX_MGMT.ACCOUNT_HEALTH.WEBHOOK.TITLE';

// webhook_configuration present (section shown) but no URL => not configured => register action required.
const healthData = {
  display_phone_number: '+15550000000',
  verified_name: 'Test',
  name_status: 'APPROVED',
  quality_rating: 'GREEN',
  messaging_limit_tier: 'TIER_1K',
  account_mode: 'LIVE',
  webhook_configuration: {},
  expected_webhook_url: 'https://expected.example.com/webhook',
};

const mountHealth = (canRegisterProviderWebhook = true) => {
  useBloomwireCapabilities.mockReturnValue({
    canRegisterProviderWebhook: ref(canRegisterProviderWebhook),
  });
  return shallowMount(AccountHealth, {
    props: { healthData, isRegisteringWebhook: false },
    global: {
      mocks: { $t: key => key },
      stubs: {
        ButtonV4: { template: '<button><slot /></button>' },
        Icon: true,
      },
    },
  });
};

describe('AccountHealth.vue (Bloomwire register-webhook hiding)', () => {
  it('shows the register-webhook button when allowed (stock/managed-off)', () => {
    expect(mountHealth(true).text()).toContain(REGISTER);
  });

  it('hides the register-webhook button when Ops-managed', () => {
    expect(mountHealth(false).text()).not.toContain(REGISTER);
  });

  it('keeps the health/status read view visible regardless of the capability', () => {
    const text = mountHealth(false).text();
    expect(text).toContain(HEALTH_TITLE);
    expect(text).toContain(WEBHOOK_TITLE);
  });

  it('emits registerWebhook when the button is clicked while allowed', async () => {
    const wrapper = mountHealth(true);
    const btn = wrapper
      .findAll('button')
      .find(b => b.text().includes(REGISTER));
    await btn.trigger('click');
    expect(wrapper.emitted('registerWebhook')).toBeTruthy();
  });
});
