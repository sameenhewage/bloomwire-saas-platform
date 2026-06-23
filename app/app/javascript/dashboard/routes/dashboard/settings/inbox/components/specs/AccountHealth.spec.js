import { mount } from '@vue/test-utils';
import { describe, it, expect, vi } from 'vitest';
import { ref } from 'vue';
import AccountHealth from '../AccountHealth.vue';

const isBloomwireManagedAccount = ref(false);

vi.mock('dashboard/composables/useAccount', () => ({
  useAccount: () => ({ isBloomwireManagedAccount }),
}));

vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: key => key }),
}));

// webhook_configuration present but unconfigured => the "register webhook" action
// is the relevant branch (action required).
const healthData = {
  webhook_configuration: {},
  expected_webhook_url: 'https://x',
};

const mountHealth = () =>
  mount(AccountHealth, {
    props: { healthData, isRegisteringWebhook: false },
    global: {
      stubs: {
        ButtonV4: { template: '<button><slot /></button>' },
        Icon: { template: '<i />' },
      },
    },
  });

describe('AccountHealth — Bloomwire-managed webhook registration hiding (4.4-b-WA.2D)', () => {
  it('shows the register-webhook button for a plain (non-managed) account', () => {
    isBloomwireManagedAccount.value = false;

    const html = mountHealth().html();

    expect(html).toContain('INBOX_MGMT.ACCOUNT_HEALTH.WEBHOOK.REGISTER_BUTTON');
    expect(html).not.toContain('INBOX_MGMT.BLOOMWIRE_MANAGED.NOTICE');
  });

  it('hides the register-webhook button and shows the managed notice for a Bloomwire-managed account', () => {
    isBloomwireManagedAccount.value = true;

    const html = mountHealth().html();

    expect(html).not.toContain(
      'INBOX_MGMT.ACCOUNT_HEALTH.WEBHOOK.REGISTER_BUTTON'
    );
    expect(html).toContain('INBOX_MGMT.BLOOMWIRE_MANAGED.NOTICE');
  });
});
