import { ref } from 'vue';
import { shallowMount } from '@vue/test-utils';
import ConfigurationPage from '../ConfigurationPage.vue';
import { useBloomwireCapabilities } from 'dashboard/composables/useBloomwireCapabilities';

vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('dashboard/composables/useBloomwireCapabilities');

const RECONFIGURE = 'INBOX_MGMT.SETTINGS_POPUP.WHATSAPP_RECONFIGURE_BUTTON';
const SYNC = 'INBOX_MGMT.SETTINGS_POPUP.WHATSAPP_TEMPLATES_SYNC_BUTTON';

const embeddedWhatsAppInbox = {
  id: 1,
  channel_type: 'Channel::Whatsapp',
  provider: 'whatsapp_cloud',
  provider_config: {
    source: 'embedded_signup',
    api_key: 'k',
    webhook_verify_token: 't',
  },
};

const mountPage = (canManageNativeWhatsappSetup = true) => {
  window.chatwootConfig = { whatsappAppId: 'app-123' };
  useBloomwireCapabilities.mockReturnValue({
    canManageNativeWhatsappSetup: ref(canManageNativeWhatsappSetup),
  });
  return shallowMount(ConfigurationPage, {
    props: { inbox: embeddedWhatsAppInbox },
    global: {
      mocks: { $t: key => key, $store: { dispatch: vi.fn() } },
      stubs: {
        SettingsFieldSection: { template: '<div><slot /></div>' },
        NextButton: { template: '<button><slot /></button>' },
        WhatsappReauthorize: true,
        SettingsToggleSection: true,
        SettingsAccordion: true,
        ImapSettings: true,
        SmtpSettings: true,
        TextArea: true,
      },
    },
  });
};

const hasBridge = wrapper =>
  wrapper.findComponent({ name: 'WhatsappReauthorize' }).exists();

describe('ConfigurationPage.vue (Bloomwire native WhatsApp reconfigure hiding)', () => {
  it('shows the reconfigure button and bridge when native whatsapp setup is allowed (stock/managed-off)', () => {
    const wrapper = mountPage(true);
    expect(wrapper.text()).toContain(RECONFIGURE);
    expect(hasBridge(wrapper)).toBe(true);
  });

  it('hides the reconfigure button and the hidden bridge when native whatsapp setup is Ops-managed', () => {
    const wrapper = mountPage(false);
    expect(wrapper.text()).not.toContain(RECONFIGURE);
    expect(hasBridge(wrapper)).toBe(false);
  });

  it('keeps WhatsApp template sync visible regardless of the capability (Group B unchanged)', () => {
    expect(mountPage(true).text()).toContain(SYNC);
    expect(mountPage(false).text()).toContain(SYNC);
  });
});
