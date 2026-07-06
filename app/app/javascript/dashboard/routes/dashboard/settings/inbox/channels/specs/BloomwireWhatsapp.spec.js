import { ref } from 'vue';
import { mount, RouterLinkStub, flushPromises } from '@vue/test-utils';
import BloomwireWhatsapp from '../BloomwireWhatsapp.vue';
import { useWhatsappEmbeddedSignup } from 'dashboard/composables/useWhatsappEmbeddedSignup';

// Phase 17C.3 / 17D.3: customer WhatsApp connection wizard. All Meta + store calls are mocked (no real Meta, no
// HTTP). The wizard opens on a connection-choice screen with two ENABLED options: Coexistence (Connect Existing
// WhatsApp Business App — 17D.3) and Register New Number (Standard). Both reuse the same credential-free form +
// Meta Embedded Signup; each posts ONLY the non-secret signup credentials to its OWN store action (coexistence →
// createBloomwireWhatsAppCoexistenceEmbeddedSignup; standard → createBloomwireWhatsAppEmbeddedSignup). Success
// renders a safe DTO with Open inbox + Inbox settings (NEVER an Add Agents step); failures show one sanitized
// generic message.
const dispatch = vi.fn();
const routeLeaveGuard = vi.fn();
const trace = vi.fn();
vi.mock('vuex', () => ({ useStore: () => ({ dispatch }) }));
vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));
vi.mock('vue-router', () => ({
  onBeforeRouteLeave: fn => routeLeaveGuard(fn),
}));
vi.mock('dashboard/composables/useWhatsappEmbeddedSignup');
// The wizard mints its own tracer; keep it inert + observable (no real network) so trace calls never break tests.
vi.mock(
  'dashboard/routes/dashboard/settings/inbox/channels/whatsapp/onboardingTrace',
  () => ({
    createOnboardingTracer: () => ({
      attemptId: 'att-wizard-abc123',
      shortRef: 'att-wiza',
      trace,
    }),
    shortAttemptRef: id => String(id || '').slice(0, 8),
  })
);

const runEmbeddedSignup = vi.fn();
const cancelEmbeddedSignup = vi.fn();

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
    cancel: cancelEmbeddedSignup,
  });
  return mount(BloomwireWhatsapp, {
    global: {
      mocks: { $t: key => key },
      stubs: {
        RouterLink: RouterLinkStub,
        NextButton: {
          template:
            '<button class="next-button" :disabled="disabled" @click="$emit(\'click\')">{{ label }}<slot /></button>',
          props: [
            'label',
            'isLoading',
            'disabled',
            'solid',
            'outline',
            'teal',
            'slate',
            'faded',
            'ghost',
          ],
        },
        LoadingState: { template: '<div class="loading-state" />' },
        Icon: true,
      },
    },
  });
};

// Advance from the connection-choice screen into the Standard registration form.
const startRegister = async wrapper => {
  await wrapper
    .find('[data-testid="bloomwire-wa-choice-standard-cta"]')
    .trigger('click');
  await flushPromises();
};

// Advance from the connection-choice screen into the Coexistence form (Phase 17D.3).
const startCoexistence = async wrapper => {
  await wrapper
    .find('[data-testid="bloomwire-wa-coexistence-cta"]')
    .trigger('click');
  await flushPromises();
};

const submit = async wrapper => {
  await wrapper.find('form').trigger('submit');
  await flushPromises();
};

beforeEach(() => {
  dispatch.mockReset();
  runEmbeddedSignup.mockReset();
  cancelEmbeddedSignup.mockReset();
  trace.mockReset();
  routeLeaveGuard.mockReset();
});

describe('BloomwireWhatsapp.vue — connection-choice screen', () => {
  it('opens on the choice screen with exactly two options (Coexistence + Register New Number) and no form', () => {
    const wrapper = mountWizard();
    expect(wrapper.find('[data-testid="bloomwire-wa-choose"]').exists()).toBe(
      true
    );
    expect(
      wrapper.find('[data-testid="bloomwire-wa-choice-coexistence"]').exists()
    ).toBe(true);
    expect(
      wrapper.find('[data-testid="bloomwire-wa-choice-standard"]').exists()
    ).toBe(true);
    // no registration form yet → no inputs (and definitely no credential inputs)
    expect(wrapper.findAll('input')).toHaveLength(0);
  });

  it('shows Coexistence as available/enabled (NOT coming-soon/disabled), lists its prerequisites, and continues to the form', async () => {
    const wrapper = mountWizard();
    // the status badge is rendered (now the enabled "Available now" STATUS copy)
    expect(
      wrapper.find('[data-testid="bloomwire-wa-coexistence-status"]').text()
    ).toBe(`${B}.CHOOSE.COEXISTENCE.STATUS`);
    // the CTA is enabled (no `disabled` attribute) and uses the connect CTA label — not the old coming-soon label
    const cta = wrapper.find('[data-testid="bloomwire-wa-coexistence-cta"]');
    expect(cta.attributes('disabled')).toBeUndefined();
    expect(cta.text()).toBe(`${B}.CHOOSE.COEXISTENCE.CTA`);
    // prerequisite list is still rendered
    expect(
      wrapper.findAll('[data-testid="bloomwire-wa-choice-coexistence"] li')
        .length
    ).toBe(8);

    // clicking advances into the shared credential-free form; no backend call happens until the form is submitted
    await startCoexistence(wrapper);
    expect(wrapper.find('[data-testid="bloomwire-wa-choose"]').exists()).toBe(
      false
    );
    expect(wrapper.find('[data-testid="bloomwire-wa-register"]').exists()).toBe(
      true
    );
    expect(runEmbeddedSignup).not.toHaveBeenCalled();
    expect(dispatch).not.toHaveBeenCalled();
  });

  it('continues to the Standard registration form when Register New Number is clicked', async () => {
    const wrapper = mountWizard();
    await startRegister(wrapper);
    expect(wrapper.find('[data-testid="bloomwire-wa-choose"]').exists()).toBe(
      false
    );
    expect(wrapper.find('[data-testid="bloomwire-wa-register"]').exists()).toBe(
      true
    );
    expect(wrapper.findAll('input')).toHaveLength(2);
  });
});

describe('BloomwireWhatsapp.vue — Standard registration flow', () => {
  it('renders only the inbox-name + WhatsApp-number fields — no credential inputs', async () => {
    const wrapper = mountWizard();
    await startRegister(wrapper);
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

  it('uses the "Register WhatsApp number" wording on the primary action', async () => {
    const wrapper = mountWizard();
    await startRegister(wrapper);
    expect(wrapper.find('[data-testid="bloomwire-wa-register"]').text()).toBe(
      `${B}.REGISTER_BUTTON`
    );
  });

  it('runs Meta embedded signup and posts ONLY the signup credentials to the Bloomwire endpoint', async () => {
    runEmbeddedSignup.mockResolvedValue(CREDS);
    dispatch.mockResolvedValue(DTO);
    const wrapper = mountWizard();
    await startRegister(wrapper);
    await submit(wrapper);
    expect(runEmbeddedSignup).toHaveBeenCalledTimes(1);
    // Only the non-secret credentials + the opaque onboarding_attempt_id correlation are sent.
    expect(dispatch).toHaveBeenCalledWith(
      'inboxes/createBloomwireWhatsAppEmbeddedSignup',
      { ...CREDS, onboarding_attempt_id: 'att-wizard-abc123' }
    );
    // Standard must NOT regress onto the coexistence endpoint
    expect(dispatch).not.toHaveBeenCalledWith(
      'inboxes/createBloomwireWhatsAppCoexistenceEmbeddedSignup',
      expect.anything()
    );
  });

  it('shows the ready inbox with Open inbox + Inbox settings and NO Add Agents step, exposing no secrets', async () => {
    runEmbeddedSignup.mockResolvedValue(CREDS);
    dispatch.mockResolvedValue(DTO);
    const wrapper = mountWizard();
    await startRegister(wrapper);
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
    await startRegister(wrapper);
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
    await startRegister(wrapper);
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
    await startRegister(wrapper);
    await submit(wrapper);
    expect(dispatch).not.toHaveBeenCalled();
    expect(wrapper.find('[data-testid="bloomwire-wa-error"]').text()).toBe(
      `${B}.CANCELLED`
    );
  });
});

describe('BloomwireWhatsapp.vue — Coexistence flow (Phase 17D.3)', () => {
  it('renders only the inbox-name + WhatsApp-number fields (no credential inputs) under the coexistence form title', async () => {
    const wrapper = mountWizard();
    await startCoexistence(wrapper);
    const inputs = wrapper.findAll('input');
    expect(inputs).toHaveLength(2);
    expect(
      wrapper.find('[data-testid="bloomwire-wa-inbox-name"]').exists()
    ).toBe(true);
    expect(
      wrapper.find('[data-testid="bloomwire-wa-phone-number"]').exists()
    ).toBe(true);
    // the form heading makes it clear this connects an EXISTING WhatsApp Business App number
    expect(wrapper.find('[data-testid="bloomwire-wa-form-title"]').text()).toBe(
      `${B}.CHOOSE.COEXISTENCE.FORM_TITLE`
    );
    const html = wrapper.html().toLowerCase();
    expect(html).not.toContain('app_secret');
    expect(html).not.toContain('verify_token');
    expect(html).not.toContain('webhook');
    expect(html).not.toContain('api_key');
    expect(html).not.toContain('provider_config');
  });

  it('uses the "Connect existing number" wording on the primary action', async () => {
    const wrapper = mountWizard();
    await startCoexistence(wrapper);
    expect(wrapper.find('[data-testid="bloomwire-wa-register"]').text()).toBe(
      `${B}.CHOOSE.COEXISTENCE.CONNECT_BUTTON`
    );
  });

  it('runs Meta embedded signup and posts ONLY the signup credentials to the COEXISTENCE endpoint (never the Standard one)', async () => {
    runEmbeddedSignup.mockResolvedValue(CREDS);
    dispatch.mockResolvedValue(DTO);
    const wrapper = mountWizard();
    await startCoexistence(wrapper);
    await submit(wrapper);
    expect(runEmbeddedSignup).toHaveBeenCalledTimes(1);
    expect(dispatch).toHaveBeenCalledWith(
      'inboxes/createBloomwireWhatsAppCoexistenceEmbeddedSignup',
      { ...CREDS, onboarding_attempt_id: 'att-wizard-abc123' }
    );
    expect(dispatch).not.toHaveBeenCalledWith(
      'inboxes/createBloomwireWhatsAppEmbeddedSignup',
      expect.anything()
    );
  });

  it('renders the safe success DTO on connect and exposes no signup secrets', async () => {
    runEmbeddedSignup.mockResolvedValue(CREDS);
    dispatch.mockResolvedValue(DTO);
    const wrapper = mountWizard();
    await startCoexistence(wrapper);
    await submit(wrapper);
    expect(wrapper.find('[data-testid="bloomwire-wa-success"]').exists()).toBe(
      true
    );
    const html = wrapper.html();
    expect(html).toContain('••••0001'); // masked number from the DTO (source of truth)
    expect(html).not.toContain('META-CODE');
    expect(html).not.toContain('WABA-1');
    expect(html).not.toContain('PNID-1');
  });

  it('shows the sanitized generic error on failure — never the raw server/Meta error', async () => {
    runEmbeddedSignup.mockResolvedValue(CREDS);
    dispatch.mockRejectedValue(new Error('RAW META 500: leaked-token-xyz'));
    const wrapper = mountWizard();
    await startCoexistence(wrapper);
    await submit(wrapper);
    const error = wrapper.find('[data-testid="bloomwire-wa-error"]');
    expect(error.text()).toBe(`${B}.ERROR`);
    expect(wrapper.html()).not.toContain('leaked-token');
    expect(wrapper.find('[data-testid="bloomwire-wa-success"]').exists()).toBe(
      false
    );
  });

  // Stage-B incident coverage: when the embedded-signup run fails/aborts (e.g.
  // the bounded timeout because one Meta signal never arrived), the wizard must
  // surface a safe recoverable error and NEVER dispatch the create request — no
  // infinite spinner, no partial Inbox/Channel/Setup POST.
  it('shows a safe error and never dispatches the create request when embedded signup rejects (timeout/incomplete)', async () => {
    runEmbeddedSignup.mockRejectedValue(new Error('Embedded signup timed out'));
    const wrapper = mountWizard();
    await startCoexistence(wrapper);
    await submit(wrapper);

    expect(runEmbeddedSignup).toHaveBeenCalledTimes(1);
    // no create POST of any kind reached the store (matches the incident: zero backend create requests)
    expect(dispatch).not.toHaveBeenCalledWith(
      'inboxes/createBloomwireWhatsAppCoexistenceEmbeddedSignup',
      expect.anything()
    );
    expect(dispatch).not.toHaveBeenCalledWith(
      'inboxes/createBloomwireWhatsAppEmbeddedSignup',
      expect.anything()
    );
    // spinner ended with a safe, recoverable error (form still shown → retryable); raw error never leaked
    const error = wrapper.find('[data-testid="bloomwire-wa-error"]');
    expect(error.text()).toBe(`${B}.ERROR`);
    expect(wrapper.html()).not.toContain('timed out');
    expect(wrapper.find('[data-testid="bloomwire-wa-register"]').exists()).toBe(
      true
    );
    expect(wrapper.find('[data-testid="bloomwire-wa-success"]').exists()).toBe(
      false
    );
  });
});

// Bounded backend create, lifecycle cleanup, retry + trace correlation (onboarding hardening).
describe('BloomwireWhatsapp.vue — bounded create, cleanup, retry + trace', () => {
  const events = () => trace.mock.calls.map(call => call[0]);

  // (8): a create POST that stays pending is bounded and fails closed with a safe error + support reference.
  it('bounds a pending create request and fails closed with a safe error + support reference', async () => {
    runEmbeddedSignup.mockResolvedValue(CREDS);
    dispatch.mockReturnValue(new Promise(() => {})); // never resolves — POST stays pending
    const wrapper = mountWizard();
    await startCoexistence(wrapper);
    vi.useFakeTimers();
    wrapper.find('form').trigger('submit');
    await vi.advanceTimersByTimeAsync(45000); // CREATE_REQUEST_TIMEOUT_MS
    vi.useRealTimers();
    await flushPromises();

    expect(wrapper.find('[data-testid="bloomwire-wa-error"]').text()).toBe(
      `${B}.ERROR`
    );
    expect(
      wrapper.find('[data-testid="bloomwire-wa-attempt-ref"]').exists()
    ).toBe(true);
    expect(events()).toContain('create_request_timeout');
    expect(wrapper.find('[data-testid="bloomwire-wa-success"]').exists()).toBe(
      false
    );
  });

  // (9): a 4xx create fails closed with the sanitized message (no raw status/error leaked to the user).
  it('shows the sanitized error when the create returns 4xx', async () => {
    runEmbeddedSignup.mockResolvedValue(CREDS);
    dispatch.mockRejectedValue({ response: { status: 422 } });
    const wrapper = mountWizard();
    await startCoexistence(wrapper);
    await submit(wrapper);

    expect(wrapper.find('[data-testid="bloomwire-wa-error"]').text()).toBe(
      `${B}.ERROR`
    );
    expect(wrapper.html()).not.toContain('422');
    expect(events()).toContain('create_request_failed');
  });

  // (10): a 5xx create fails closed the same way.
  it('shows the sanitized error when the create returns 5xx', async () => {
    runEmbeddedSignup.mockResolvedValue(CREDS);
    dispatch.mockRejectedValue({ response: { status: 500 } });
    const wrapper = mountWizard();
    await startCoexistence(wrapper);
    await submit(wrapper);

    expect(wrapper.find('[data-testid="bloomwire-wa-error"]').exists()).toBe(
      true
    );
    expect(events()).toContain('create_request_failed');
    expect(events()).toContain('frontend_error_transition');
  });

  // (11): a successful create transitions to success and traces the success path end-to-end.
  it('transitions to success and traces the create success + finish', async () => {
    runEmbeddedSignup.mockResolvedValue(CREDS);
    dispatch.mockResolvedValue(DTO);
    const wrapper = mountWizard();
    await startCoexistence(wrapper);
    await submit(wrapper);

    expect(wrapper.find('[data-testid="bloomwire-wa-success"]').exists()).toBe(
      true
    );
    expect(events()).toEqual(
      expect.arrayContaining([
        'create_request_started',
        'create_request_succeeded',
        'frontend_success_transition',
        'attempt_finished',
      ])
    );
  });

  // (12): after a failure, loading is cleared (the register button is usable again).
  it('clears the loading state after a failure so the user can retry', async () => {
    runEmbeddedSignup.mockResolvedValue(CREDS);
    dispatch.mockRejectedValue({ response: { status: 500 } });
    const wrapper = mountWizard();
    await startCoexistence(wrapper);
    await submit(wrapper);

    expect(wrapper.find('.loading-state').exists()).toBe(false);
    expect(
      wrapper
        .find('[data-testid="bloomwire-wa-register"]')
        .attributes('disabled')
    ).toBeFalsy();
  });

  // (13): component unmount cancels any in-flight signup (clears listeners/timers via the composable).
  it('cancels the in-flight signup on component unmount', () => {
    const wrapper = mountWizard();
    wrapper.unmount();
    expect(cancelEmbeddedSignup).toHaveBeenCalled();
  });

  // (14): a route change (onBeforeRouteLeave) cancels the in-flight signup.
  it('cancels the in-flight signup on route change', () => {
    mountWizard();
    const guard = routeLeaveGuard.mock.calls.at(-1)[0];
    expect(typeof guard).toBe('function');
    guard();
    expect(cancelEmbeddedSignup).toHaveBeenCalled();
  });

  // (15): a repeated attempt after a failure starts cleanly (prior error cleared, success renders).
  it('starts cleanly on a repeated attempt after a failure', async () => {
    runEmbeddedSignup.mockResolvedValue(CREDS);
    dispatch
      .mockRejectedValueOnce({ response: { status: 500 } })
      .mockResolvedValueOnce(DTO);
    const wrapper = mountWizard();
    await startCoexistence(wrapper);
    await submit(wrapper); // first attempt fails
    expect(wrapper.find('[data-testid="bloomwire-wa-error"]').exists()).toBe(
      true
    );
    await submit(wrapper); // retry
    expect(wrapper.find('[data-testid="bloomwire-wa-error"]').exists()).toBe(
      false
    );
    expect(wrapper.find('[data-testid="bloomwire-wa-success"]').exists()).toBe(
      true
    );
  });

  // (16): a double-submit does not fan out into parallel create requests. The composable's in-flight guard
  // returns null for the second, concurrent runEmbeddedSignup() call (see the composable spec) — so only the
  // first attempt reaches the create dispatch.
  it('does not create parallel attempts on double submit', async () => {
    runEmbeddedSignup.mockResolvedValueOnce(CREDS).mockResolvedValue(null);
    dispatch.mockResolvedValue(DTO);
    const wrapper = mountWizard();
    await startCoexistence(wrapper);
    wrapper.find('form').trigger('submit');
    wrapper.find('form').trigger('submit');
    await flushPromises();
    const creates = dispatch.mock.calls.filter(call =>
      String(call[0]).includes(
        'createBloomwireWhatsAppCoexistenceEmbeddedSignup'
      )
    );
    expect(creates).toHaveLength(1);
  });
});
