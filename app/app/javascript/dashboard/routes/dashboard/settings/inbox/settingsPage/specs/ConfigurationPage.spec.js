import { mount } from '@vue/test-utils';
import { describe, it, expect, vi } from 'vitest';
import { ref } from 'vue';
import ConfigurationPage from '../ConfigurationPage.vue';

const isBloomwireManagedAccount = ref(false);

vi.mock('dashboard/composables/useAccount', () => ({
  useAccount: () => ({ isBloomwireManagedAccount }),
}));

const whatsappInbox = {
  id: 10,
  channel_type: 'Channel::Whatsapp',
  provider: 'whatsapp_cloud',
  provider_config: {
    api_key: 'sekret-key',
    webhook_verify_token: 'verify-tok',
  },
};

const stubs = {
  SettingsFieldSection: { template: '<div><slot /></div>' },
  SettingsToggleSection: {
    template: '<div><slot /><slot name="editor" /></div>',
  },
  SettingsAccordion: { template: '<div><slot /></div>' },
  ImapSettings: true,
  SmtpSettings: true,
  NextButton: { template: '<button><slot /></button>' },
  TextArea: true,
  WhatsappReauthorize: { template: '<div class="wa-reauth" />' },
  'woot-code': { props: ['script'], template: '<code>{{ script }}</code>' },
  'woot-input': { template: '<input />' },
};

const mountConfig = () =>
  mount(ConfigurationPage, {
    props: { inbox: whatsappInbox },
    global: {
      mocks: { $t: key => key },
      stubs,
    },
  });

describe('ConfigurationPage — Bloomwire-managed WhatsApp credential hiding (4.4-b-WA.2D)', () => {
  it('shows the raw API key + update form for a plain (non-managed) account', () => {
    isBloomwireManagedAccount.value = false;

    const html = mountConfig().html();

    expect(html).toContain('sekret-key');
    expect(html).toContain(
      'INBOX_MGMT.SETTINGS_POPUP.WHATSAPP_SECTION_UPDATE_BUTTON'
    );
    expect(html).not.toContain('INBOX_MGMT.BLOOMWIRE_MANAGED.NOTICE');
  });

  it('hides the raw API key/update form and shows the managed notice for a Bloomwire-managed account', () => {
    isBloomwireManagedAccount.value = true;

    const html = mountConfig().html();

    expect(html).toContain('INBOX_MGMT.BLOOMWIRE_MANAGED.NOTICE');
    expect(html).not.toContain('sekret-key');
    expect(html).not.toContain('verify-tok');
    expect(html).not.toContain(
      'INBOX_MGMT.SETTINGS_POPUP.WHATSAPP_SECTION_UPDATE_BUTTON'
    );
  });

  it('keeps the WhatsApp template sync action for a Bloomwire-managed account', () => {
    isBloomwireManagedAccount.value = true;

    const html = mountConfig().html();

    expect(html).toContain(
      'INBOX_MGMT.SETTINGS_POPUP.WHATSAPP_TEMPLATES_SYNC_BUTTON'
    );
  });
});
