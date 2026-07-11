import { ref } from 'vue';
import { mount } from '@vue/test-utils';
import { useRoute } from 'vue-router';
import { useMapGetter } from 'dashboard/composables/store';
import { useBloomwireWhatsappOnboarding } from 'dashboard/composables/useBloomwireWhatsappOnboarding';
import { useBranding } from 'shared/composables/useBranding';
import WootWizard from 'dashboard/components/ui/Wizard.vue';
import InboxChannels from '../InboxChannels.vue';

vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));
vi.mock('vue-router', () => ({ useRoute: vi.fn() }));
vi.mock('dashboard/composables/store');
vi.mock('dashboard/composables/useBloomwireWhatsappOnboarding');
vi.mock('shared/composables/useBranding');

const mountPage = ({ subPage = 'whatsapp', managedWhatsapp = true } = {}) => {
  useRoute.mockReturnValue({
    name: 'settings_inboxes_page_channel',
    params: { sub_page: subPage },
  });
  useMapGetter.mockReturnValue(ref({}));
  useBloomwireWhatsappOnboarding.mockReturnValue({
    isAvailable: ref(managedWhatsapp),
  });
  useBranding.mockReturnValue({ replaceInstallationName: value => value });

  return mount(InboxChannels, {
    global: {
      components: { 'woot-wizard': WootWizard },
      stubs: {
        PageHeader: true,
        RouterView: true,
        Icon: true,
      },
    },
  });
};

const wizardTitles = wrapper => wrapper.findAll('h3').map(node => node.text());

describe('InboxChannels managed WhatsApp progress', () => {
  it('shows only the two steps the managed WhatsApp flow actually performs', () => {
    const wrapper = mountPage();

    expect(wizardTitles(wrapper)).toEqual([
      'INBOX_MGMT.CREATE_FLOW.CHANNEL.TITLE',
      'INBOX_MGMT.CREATE_FLOW.MANAGED_WHATSAPP.TITLE',
    ]);
    expect(wrapper.findAll('h3')[1].classes()).toContain('text-n-blue-11');
  });

  it('keeps the stock four-step flow when managed WhatsApp onboarding is unavailable', () => {
    const wrapper = mountPage({ managedWhatsapp: false });

    expect(wizardTitles(wrapper)).toEqual([
      'INBOX_MGMT.CREATE_FLOW.CHANNEL.TITLE',
      'INBOX_MGMT.CREATE_FLOW.INBOX.TITLE',
      'INBOX_MGMT.CREATE_FLOW.AGENT.TITLE',
      'INBOX_MGMT.CREATE_FLOW.FINISH.TITLE',
    ]);
  });

  it('keeps the stock four-step flow for non-WhatsApp channel routes', () => {
    const wrapper = mountPage({ subPage: 'website' });

    expect(wizardTitles(wrapper)).toEqual([
      'INBOX_MGMT.CREATE_FLOW.CHANNEL.TITLE',
      'INBOX_MGMT.CREATE_FLOW.INBOX.TITLE',
      'INBOX_MGMT.CREATE_FLOW.AGENT.TITLE',
      'INBOX_MGMT.CREATE_FLOW.FINISH.TITLE',
    ]);
  });
});
