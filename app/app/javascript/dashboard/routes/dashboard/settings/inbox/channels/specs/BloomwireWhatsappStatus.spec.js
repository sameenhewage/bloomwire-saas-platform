import { ref } from 'vue';
import { mount, flushPromises } from '@vue/test-utils';
import BloomwireWhatsappStatus from '../BloomwireWhatsappStatus.vue';

// Phase 5 (resume) — durable managed-WhatsApp capability panel on the Inbox Settings surface. The store + admin
// capability are mocked (no HTTP). Proves: it loads the PERSISTED status from the backend on mount (durable /
// survives refresh), renders reason-specific copy (verified_missing shows the grant step; unverifiable hides it
// and never claims "missing"), Recheck reuses the SAME setup id and flips to ready, and it is inert for a
// non-managed inbox or a non-admin. No secret is ever rendered.
const dispatch = vi.fn();
const canSelfServe = ref(true);

vi.mock('dashboard/composables/store', () => ({
  useStore: () => ({ dispatch }),
}));
vi.mock('dashboard/composables/useBloomwireCapabilities', () => ({
  useBloomwireCapabilities: () => ({
    canSelfServeManagedWhatsapp: canSelfServe,
  }),
}));

const B = 'INBOX_MGMT.ADD.WHATSAPP.BLOOMWIRE_MANAGED.ACTION_REQUIRED';
const T = {
  actionRequired: '[data-testid="bloomwire-wa-status-action-required"]',
  grantStep: '[data-testid="bloomwire-wa-status-grant-step"]',
  reason: '[data-testid="bloomwire-wa-status-reason"]',
  pending: '[data-testid="bloomwire-wa-status-pending"]',
  failed: '[data-testid="bloomwire-wa-status-failed"]',
  ready: '[data-testid="bloomwire-wa-status-ready"]',
  recheck: '[data-testid="bloomwire-wa-status-recheck"]',
};

const managedInbox = (overrides = {}) => ({
  id: 42,
  provider_config: { source: 'bloomwire_managed' },
  ...overrides,
});

const actionRequiredDto = (
  reason = 'outbound_messaging_permission_required'
) => ({
  managed: true,
  ready: false,
  setup: { id: 3, status: 'action_required' },
  inbox: { id: 42 },
  action_required: { reason },
});
const readyDto = () => ({
  managed: true,
  ready: true,
  setup: { id: 3, status: 'ready_for_webhook' },
  inbox: { id: 42 },
});

const mockFetch = dto => {
  dispatch.mockImplementation(action => {
    if (action === 'inboxes/fetchBloomwireWhatsAppCapability') {
      return Promise.resolve(dto);
    }
    return Promise.resolve();
  });
};

const mountPanel = (inbox = managedInbox()) =>
  mount(BloomwireWhatsappStatus, {
    props: { inbox },
    global: {
      mocks: { $t: key => key },
      stubs: {
        Icon: { template: '<span />' },
        NextButton: {
          template:
            '<button class="next-button" :disabled="disabled" @click="$emit(\'click\')">{{ label }}</button>',
          props: ['label', 'isLoading', 'disabled', 'solid', 'teal'],
        },
      },
    },
  });

beforeEach(() => {
  dispatch.mockReset();
  canSelfServe.value = true;
});

describe('BloomwireWhatsappStatus (durable Inbox Settings panel)', () => {
  it('is inert (no query, no panel) for a non-managed WhatsApp inbox', async () => {
    mockFetch(actionRequiredDto());
    const wrapper = mountPanel(
      managedInbox({ provider_config: { source: 'whatsapp' } })
    );
    await flushPromises();
    expect(dispatch).not.toHaveBeenCalledWith(
      'inboxes/fetchBloomwireWhatsAppCapability',
      expect.anything()
    );
    expect(wrapper.find(T.actionRequired).exists()).toBe(false);
    expect(wrapper.find(T.ready).exists()).toBe(false);
  });

  it('is inert when the admin capability (canSelfServeManagedWhatsapp) is off', async () => {
    canSelfServe.value = false;
    mockFetch(actionRequiredDto());
    const wrapper = mountPanel();
    await flushPromises();
    expect(dispatch).not.toHaveBeenCalledWith(
      'inboxes/fetchBloomwireWhatsAppCapability',
      expect.anything()
    );
    expect(wrapper.find(T.actionRequired).exists()).toBe(false);
  });

  it('loads the PERSISTED status from the backend on mount (durable — survives refresh/navigation)', async () => {
    mockFetch(actionRequiredDto());
    const wrapper = mountPanel();
    await flushPromises();
    expect(dispatch).toHaveBeenCalledWith(
      'inboxes/fetchBloomwireWhatsAppCapability',
      { inboxId: 42 }
    );
    expect(wrapper.find(T.actionRequired).exists()).toBe(true);
  });

  it('shows the grant step + PERMISSION_REQUIRED reason for a verified-missing task', async () => {
    mockFetch(actionRequiredDto('outbound_messaging_permission_required'));
    const wrapper = mountPanel();
    await flushPromises();
    expect(wrapper.find(T.grantStep).exists()).toBe(true);
    expect(wrapper.find(T.reason).text()).toBe(
      `${B}.REASON.PERMISSION_REQUIRED`
    );
  });

  it('HIDES the grant step and shows a neutral message for an UNVERIFIABLE state (never claims missing)', async () => {
    mockFetch(actionRequiredDto('outbound_messaging_permission_unverifiable'));
    const wrapper = mountPanel();
    await flushPromises();
    expect(wrapper.find(T.grantStep).exists()).toBe(false);
    expect(wrapper.find(T.reason).text()).toBe(`${B}.REASON.UNVERIFIABLE`);
  });

  it('shows the activation-incomplete reason (grant present) without the grant step', async () => {
    mockFetch(actionRequiredDto('outbound_messaging_activation_incomplete'));
    const wrapper = mountPanel();
    await flushPromises();
    expect(wrapper.find(T.grantStep).exists()).toBe(false);
    expect(wrapper.find(T.reason).text()).toBe(
      `${B}.REASON.ACTIVATION_INCOMPLETE`
    );
  });

  it('shows the ready panel (no action-required) for a routeable setup', async () => {
    mockFetch(readyDto());
    const wrapper = mountPanel();
    await flushPromises();
    expect(wrapper.find(T.ready).exists()).toBe(true);
    expect(wrapper.find(T.actionRequired).exists()).toBe(false);
  });

  it('Recheck reuses the SAME setup id and flips to ready on success', async () => {
    dispatch.mockImplementation(action => {
      if (action === 'inboxes/fetchBloomwireWhatsAppCapability') {
        return Promise.resolve(actionRequiredDto());
      }
      if (action === 'inboxes/recheckBloomwireWhatsAppCapability') {
        return Promise.resolve(readyDto());
      }
      return Promise.resolve();
    });
    const wrapper = mountPanel();
    await flushPromises();
    await wrapper.find(T.recheck).trigger('click');
    await flushPromises();
    expect(dispatch).toHaveBeenCalledWith(
      'inboxes/recheckBloomwireWhatsAppCapability',
      { setupId: 3 }
    );
    expect(wrapper.find(T.ready).exists()).toBe(true);
    expect(wrapper.find(T.actionRequired).exists()).toBe(false);
  });

  it('Recheck that is still not active shows the still-pending message (stays action_required)', async () => {
    dispatch.mockImplementation(action => {
      if (action === 'inboxes/fetchBloomwireWhatsAppCapability') {
        return Promise.resolve(actionRequiredDto());
      }
      if (action === 'inboxes/recheckBloomwireWhatsAppCapability') {
        return Promise.resolve(actionRequiredDto());
      }
      return Promise.resolve();
    });
    const wrapper = mountPanel();
    await flushPromises();
    await wrapper.find(T.recheck).trigger('click');
    await flushPromises();
    expect(wrapper.find(T.pending).exists()).toBe(true);
    expect(wrapper.find(T.actionRequired).exists()).toBe(true);
  });

  it('Recheck failure shows a safe retry message', async () => {
    dispatch.mockImplementation(action => {
      if (action === 'inboxes/fetchBloomwireWhatsAppCapability') {
        return Promise.resolve(actionRequiredDto());
      }
      if (action === 'inboxes/recheckBloomwireWhatsAppCapability') {
        return Promise.reject(new Error('network'));
      }
      return Promise.resolve();
    });
    const wrapper = mountPanel();
    await flushPromises();
    await wrapper.find(T.recheck).trigger('click');
    await flushPromises();
    expect(wrapper.find(T.failed).exists()).toBe(true);
  });

  it('never renders a token/secret from the DTO', async () => {
    mockFetch(actionRequiredDto());
    const wrapper = mountPanel();
    await flushPromises();
    expect(wrapper.html()).not.toContain('api_key');
    expect(wrapper.html()).not.toMatch(/EAA[A-Za-z0-9]/); // Meta token prefix shape
  });
});
