import { ref } from 'vue';
import { mount, RouterLinkStub, flushPromises } from '@vue/test-utils';
import BloomwireWhatsapp from '../BloomwireWhatsapp.vue';
import { useWhatsappEmbeddedSignup } from 'dashboard/composables/useWhatsappEmbeddedSignup';

// Phase 17C.3: customer WhatsApp number-registration wizard. All Meta + store calls are mocked (no real Meta,
// no HTTP). Proves: no credential fields; Connect/Register runs Meta embedded signup and posts ONLY the
// non-secret signup credentials to the Bloomwire store action; success renders a safe DTO with Open inbox +
// Inbox settings (and NEVER an Add Agents step); failures show a single sanitized generic message.
const dispatch = vi.fn();
vi.mock('vuex', () => ({ useStore: () => ({ dispatch }) }));
vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));
vi.mock('dashboard/composables/useWhatsappEmbeddedSignup');

const runEmbeddedSignup = vi.fn();

const CREDS = {
  code: 'META-CODE',
  business_id: 'BIZ-1',
  waba_id: 'WABA-1',
  phone_number_id: 'PNID-1',
};

const DTO = {
  inbox: { id: 42, name: 'Acme WhatsApp' },
  channel: { id: 7, type: 'Channel::Whatsapp', source: 'bloomwire_managed' },
  setup: { id: 3, status: 'ready_for_webhook', readiness: 'ready' },
  phone: { display_phone_number: '••••0001' },
};

const B = 'INBOX_MGMT.ADD.WHATSAPP.BLOOMWIRE_MANAGED';

const mountWizard = () => {
  useWhatsappEmbeddedSignup.mockReturnValue({
    isAuthenticating: ref(false),
    runEmbeddedSignup,
  });
  return mount(BloomwireWhatsapp, {
    global: {
      mocks: { $t: key => key },
      stubs: {
        RouterLink: RouterLinkStub,
        NextButton: {
          template: '<button class="next-button">{{ label }}<slot /></button>',
          props: [
            'label',
            'isLoading',
            'disabled',
            'solid',
            'outline',
            'teal',
            'slate',
          ],
        },
        LoadingState: { template: '<div class="loading-state" />' },
        Icon: true,
      },
    },
  });
};

const submit = async wrapper => {
  await wrapper.find('form').trigger('submit');
  await flushPromises();
};

beforeEach(() => {
  dispatch.mockReset();
  runEmbeddedSignup.mockReset();
});

describe('BloomwireWhatsapp.vue (managed self-serve registration wizard)', () => {
  it('renders only the inbox-name + WhatsApp-number fields — no credential inputs', () => {
    const wrapper = mountWizard();
    const inputs = wrapper.findAll('input');
    expect(inputs).toHaveLength(2);
    expect(
      wrapper.find('[data-testid="bloomwire-wa-inbox-name"]').exists()
    ).toBe(true);
    expect(
      wrapper.find('[data-testid="bloomwire-wa-phone-number"]').exists()
    ).toBe(true);
    const html = wrapper.html().toLowerCase();
    expect(html).not.toContain('app_secret');
    expect(html).not.toContain('verify_token');
    expect(html).not.toContain('webhook');
    expect(html).not.toContain('api_key');
    expect(html).not.toContain('provider_config');
  });

  it('uses the "Register WhatsApp number" wording on the primary action', () => {
    const wrapper = mountWizard();
    expect(wrapper.find('[data-testid="bloomwire-wa-register"]').text()).toBe(
      `${B}.REGISTER_BUTTON`
    );
  });

  it('runs Meta embedded signup and posts ONLY the signup credentials to the Bloomwire endpoint', async () => {
    runEmbeddedSignup.mockResolvedValue(CREDS);
    dispatch.mockResolvedValue(DTO);
    const wrapper = mountWizard();
    await submit(wrapper);
    expect(runEmbeddedSignup).toHaveBeenCalledTimes(1);
    expect(dispatch).toHaveBeenCalledWith(
      'inboxes/createBloomwireWhatsAppEmbeddedSignup',
      CREDS
    );
  });

  it('shows the ready inbox with Open inbox + Inbox settings and NO Add Agents step, exposing no secrets', async () => {
    runEmbeddedSignup.mockResolvedValue(CREDS);
    dispatch.mockResolvedValue(DTO);
    const wrapper = mountWizard();
    await submit(wrapper);

    expect(wrapper.find('[data-testid="bloomwire-wa-success"]').exists()).toBe(
      true
    );
    const routeNames = wrapper
      .findAllComponents(RouterLinkStub)
      .map(link => link.props('to').name);
    expect(routeNames).toEqual(['inbox_dashboard', 'settings_inbox_show']);
    expect(routeNames).not.toContain('settings_inboxes_add_agents');

    const html = wrapper.html();
    expect(html).toContain('••••0001'); // masked number (source of truth from the DTO)
    // raw signup credentials + secrets never rendered
    expect(html).not.toContain('META-CODE');
    expect(html).not.toContain('WABA-1');
    expect(html).not.toContain('PNID-1');
    expect(html.toLowerCase()).not.toContain('api_key');
    expect(html.toLowerCase()).not.toContain('provider_config');
  });

  it('honors a customer-entered inbox name via the existing inbox update API (best-effort rename)', async () => {
    runEmbeddedSignup.mockResolvedValue(CREDS);
    dispatch.mockResolvedValue(DTO);
    const wrapper = mountWizard();
    await wrapper
      .find('[data-testid="bloomwire-wa-inbox-name"]')
      .setValue('My Support Line');
    await submit(wrapper);
    expect(dispatch).toHaveBeenCalledWith('inboxes/updateInbox', {
      id: 42,
      formData: false,
      name: 'My Support Line',
    });
  });

  it('shows the sanitized generic error on failure — never the raw server/Meta error', async () => {
    runEmbeddedSignup.mockResolvedValue(CREDS);
    dispatch.mockRejectedValue(new Error('RAW META 500: leaked-token-xyz'));
    const wrapper = mountWizard();
    await submit(wrapper);

    const error = wrapper.find('[data-testid="bloomwire-wa-error"]');
    expect(error.exists()).toBe(true);
    expect(error.text()).toBe(`${B}.ERROR`);
    expect(wrapper.html()).not.toContain('RAW META');
    expect(wrapper.html()).not.toContain('leaked-token');
    expect(wrapper.find('[data-testid="bloomwire-wa-success"]').exists()).toBe(
      false
    );
  });

  it('does not call the endpoint when the customer cancels the Meta popup', async () => {
    runEmbeddedSignup.mockResolvedValue(null);
    const wrapper = mountWizard();
    await submit(wrapper);
    expect(dispatch).not.toHaveBeenCalled();
    expect(wrapper.find('[data-testid="bloomwire-wa-error"]').text()).toBe(
      `${B}.CANCELLED`
    );
  });
});
