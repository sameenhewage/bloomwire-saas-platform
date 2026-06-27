import { ref } from 'vue';
import { shallowMount } from '@vue/test-utils';
import ConfigurationPage from '../ConfigurationPage.vue';
import { useBloomwireCapabilities } from 'dashboard/composables/useBloomwireCapabilities';

vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('dashboard/composables/useBloomwireCapabilities');

const RECONFIGURE = 'INBOX_MGMT.SETTINGS_POPUP.WHATSAPP_RECONFIGURE_BUTTON';
const SYNC = 'INBOX_MGMT.SETTINGS_POPUP.WHATSAPP_TEMPLATES_SYNC_BUTTON';
const API_KEY_UPDATE =
  'INBOX_MGMT.SETTINGS_POPUP.WHATSAPP_SECTION_UPDATE_BUTTON';
const API_KEY_DISPLAY = 'INBOX_MGMT.SETTINGS_POPUP.WHATSAPP_SECTION_TITLE';

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

const manualWhatsAppInbox = {
  id: 2,
  channel_type: 'Channel::Whatsapp',
  provider: 'whatsapp_cloud',
  provider_config: { api_key: 'k', webhook_verify_token: 't' },
};

const mountPage = (
  canManageNativeWhatsappSetup = true,
  inbox = embeddedWhatsAppInbox
) => {
  window.chatwootConfig = { whatsappAppId: 'app-123' };
  useBloomwireCapabilities.mockReturnValue({
    canManageNativeWhatsappSetup: ref(canManageNativeWhatsappSetup),
  });
  return shallowMount(ConfigurationPage, {
    props: { inbox },
    global: {
      mocks: { $t: key => key, $store: { dispatch: vi.fn() } },
      stubs: {
        SettingsFieldSection: {
          props: ['label'],
          template: '<div>{{ label }}<slot /></div>',
        },
        NextButton: { template: '<button><slot /></button>' },
        WhatsappReauthorize: true,
        SettingsToggleSection: true,
        SettingsAccordion: true,
        ImapSettings: true,
        SmtpSettings: true,
        TextArea: true,
        'woot-code': true,
        'woot-input': true,
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

describe('ConfigurationPage.vue (Bloomwire manual WhatsApp api-key update hiding)', () => {
  it('shows the manual api-key update control when native whatsapp setup is allowed (stock/managed-off)', () => {
    expect(mountPage(true, manualWhatsAppInbox).text()).toContain(
      API_KEY_UPDATE
    );
  });

  it('hides the manual api-key update control when native whatsapp setup is Ops-managed', () => {
    expect(mountPage(false, manualWhatsAppInbox).text()).not.toContain(
      API_KEY_UPDATE
    );
  });

  it('keeps read-only displays and template sync visible when Ops-managed (Group B unchanged)', () => {
    const text = mountPage(false, manualWhatsAppInbox).text();
    expect(text).toContain(API_KEY_DISPLAY);
    expect(text).toContain(SYNC);
  });

  it('updateWhatsAppInboxAPIKey does not dispatch an inbox update when Ops-managed', async () => {
    const wrapper = mountPage(false, manualWhatsAppInbox);
    wrapper.vm.whatsAppInboxAPIKey = 'new-key';
    await wrapper.vm.updateWhatsAppInboxAPIKey();
    expect(wrapper.vm.$store.dispatch).not.toHaveBeenCalled();
  });

  it('updateWhatsAppInboxAPIKey dispatches an inbox update when allowed', async () => {
    const wrapper = mountPage(true, manualWhatsAppInbox);
    wrapper.vm.whatsAppInboxAPIKey = 'new-key';
    await wrapper.vm.updateWhatsAppInboxAPIKey();
    expect(wrapper.vm.$store.dispatch).toHaveBeenCalledWith(
      'inboxes/updateInbox',
      expect.objectContaining({ id: manualWhatsAppInbox.id })
    );
  });
});
