import { ref } from 'vue';
import { mount, RouterLinkStub, flushPromises } from '@vue/test-utils';
import BloomwireWhatsapp from '../BloomwireWhatsapp.vue';
import BloomwireWhatsappAsync from '../BloomwireWhatsappAsync.vue';
import { useWhatsappEmbeddedSignup } from 'dashboard/composables/useWhatsappEmbeddedSignup';
import { useBloomwireWhatsappOnboarding } from 'dashboard/composables/useBloomwireWhatsappOnboarding';
import inboxMgmt from 'dashboard/i18n/locale/en/inboxMgmt.json';

// Phase 17C.3 / 17D.3: customer WhatsApp connection wizard. All Meta + store calls are mocked (no real Meta, no
// HTTP). The wizard opens on a connection-choice screen with two ENABLED options: Coexistence (Connect Existing
// WhatsApp Business App — 17D.3) and Register New Number (Standard). Both reuse the same credential-free form +
// Meta Embedded Signup; each posts ONLY the non-secret signup credentials to its OWN store action (coexistence →
// createBloomwireWhatsAppCoexistenceEmbeddedSignup; standard → createBloomwireWhatsAppEmbeddedSignup). Success
// renders a safe DTO with Open inbox + Inbox settings (NEVER an Add Agents step); failures show one sanitized
// generic message.
const dispatch = vi.fn();
const routeLeaveGuard = vi.fn();
// `trace` = the Coexistence tracer's trace spy; `noopTrace` = the Standard (no-op) tracer's trace spy.
const trace = vi.fn();
const noopTrace = vi.fn();
let tracerSeq = 0;
// Fresh, distinct attempt id every time the wizard creates a Coexistence tracer (Finding 2). Spied so tests can
// assert whether a real tracer was created at all (Finding 1: Standard must NOT create one).
const createOnboardingTracer = vi.fn(() => {
  tracerSeq += 1;
  return {
    attemptId: `att-coex-${tracerSeq}`,
    shortRef: `coex-${tracerSeq}`,
    trace,
  };
});
const createNoopTracer = vi.fn(() => ({
  attemptId: undefined,
  shortRef: '',
  trace: noopTrace,
}));

vi.mock('vuex', () => ({ useStore: () => ({ dispatch }) }));
vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));
vi.mock('vue-router', () => ({
  onBeforeRouteLeave: fn => routeLeaveGuard(fn),
}));
vi.mock('dashboard/composables/useWhatsappEmbeddedSignup');
vi.mock('dashboard/composables/useBloomwireWhatsappOnboarding');
vi.mock('dashboard/composables/store', () => ({
  useStoreGetters: () => ({ getCurrentAccountId: ref(7) }),
}));
// Factories are lazily evaluated on first import, so referencing the outer spies is safe.
vi.mock(
  'dashboard/routes/dashboard/settings/inbox/channels/whatsapp/onboardingTrace',
  () => ({
    createOnboardingTracer: (...args) => createOnboardingTracer(...args),
    createNoopTracer: (...args) => createNoopTracer(...args),
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

const mountWizard = ({ asyncStandard = false } = {}) => {
  const asyncStandardRef =
    typeof asyncStandard === 'object' ? asyncStandard : ref(asyncStandard);
  useWhatsappEmbeddedSignup.mockReturnValue({
    isAuthenticating: ref(false),
    runEmbeddedSignup,
    cancel: cancelEmbeddedSignup,
  });
  useBloomwireWhatsappOnboarding.mockReturnValue({
    usesAsyncStandard: asyncStandardRef,
    usesSyncStandard: ref(!asyncStandardRef.value),
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
        BloomwireWhatsappAsync: {
          props: ['canStartNewAsync', 'autoStart'],
          template:
            '<div data-testid="bloomwire-wa-async-standard" :data-can-start-new="canStartNewAsync" :data-auto-start="autoStart" />',
        },
        Icon: true,
      },
    },
  });
};

const startMigration = async wrapper => {
  await wrapper
    .find('[data-testid="bloomwire-wa-migration-cta"]')
    .trigger('click');
  await flushPromises();
};

// The migration confirm is gated on acknowledging the prerequisites (two-step verification, eligibility, etc.).
const acknowledgeMigration = async wrapper => {
  await wrapper
    .find('[data-testid="bloomwire-wa-migration-ack"]')
    .setValue(true);
  await flushPromises();
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
  window.localStorage.clear();
  dispatch.mockReset();
  runEmbeddedSignup.mockReset();
  cancelEmbeddedSignup.mockReset();
  trace.mockReset();
  noopTrace.mockReset();
  routeLeaveGuard.mockReset();
  createOnboardingTracer.mockClear();
  createNoopTracer.mockClear();
  tracerSeq = 0;
});

describe('BloomwireWhatsapp.vue — connection-choice screen', () => {
  it('opens with exactly three options in migration, Coexistence, Standard order and marks migration recommended', () => {
    const wrapper = mountWizard();
    expect(wrapper.find('[data-testid="bloomwire-wa-choose"]').exists()).toBe(
      true
    );
    expect(
      wrapper
        .findAll('[data-bloomwire-wa-option]')
        .map(option => option.attributes('data-bloomwire-wa-option'))
    ).toEqual(['migration', 'coexistence', 'standard']);
    expect(
      wrapper.find('[data-testid="bloomwire-wa-migration-recommended"]').text()
    ).toBe(`${B}.CHOOSE.MIGRATION.RECOMMENDED`);
    expect(wrapper.findAll('input')).toHaveLength(0);
  });

  it('uses truthful migration confirmation copy for approval, provider access, history, cancellation, and asset retention', () => {
    const copy =
      inboxMgmt.INBOX_MGMT.ADD.WHATSAPP.BLOOMWIRE_MANAGED.CHOOSE.MIGRATION;
    expect(copy.TITLE).toBe('Move Existing Cloud API Number');
    expect(copy.CONFIRM.APPROVAL).toMatch(/Meta.*approve.*migration/i);
    expect(copy.CONFIRM.PREVIOUS_PROVIDER).toMatch(
      /previous provider.*loses messaging access/i
    );
    expect(copy.CONFIRM.HISTORY).toMatch(/history.*not transferred/i);
    expect(copy.CONFIRM.CANCEL).toMatch(
      /cancell|reject.*existing provider.*Bloomwire/i
    );
    expect(copy.CONFIRM.ASSET).toMatch(/not delete.*phone-number asset.*WABA/i);
  });

  it('surfaces truthful migration prerequisites (two-step verification first), splits manager vs Bloomwire ownership, and does not advertise general availability', () => {
    const copy =
      inboxMgmt.INBOX_MGMT.ADD.WHATSAPP.BLOOMWIRE_MANAGED.CHOOSE.MIGRATION;
    // Meta's migration guide starts with disabling two-step verification.
    expect(copy.CONFIRM.PREREQ.TWO_STEP).toMatch(/two-step verification/i);
    // Source eligibility + verified business/WABA. Meta requires the payment method on the SOURCE (existing) WABA
    // being moved — NOT the destination.
    expect(copy.CONFIRM.PREREQ.SOURCE_ELIGIBLE).toMatch(/Cloud API/i);
    expect(copy.CONFIRM.PREREQ.VERIFIED_BUSINESS).toMatch(
      /verified.*business|WABA/i
    );
    expect(copy.CONFIRM.PREREQ.PAYMENT).toMatch(/payment/i);
    expect(copy.CONFIRM.PREREQ.PAYMENT).toMatch(/existing|source/i);
    expect(copy.CONFIRM.PREREQ.PAYMENT).not.toMatch(/destination/i);
    // Partner / destination credit-line sharing is surfaced only as conditional ("when applicable").
    expect(copy.CONFIRM.PREREQ.PARTNER).toMatch(
      /Solution Partner|credit-line/i
    );
    expect(copy.CONFIRM.PREREQ.PARTNER).toMatch(/when applicable/i);
    // Ownership is split: manager-owned prerequisites vs what the Bloomwire application does.
    expect(copy.CONFIRM.PREREQ_TITLE).toMatch(/manager|before you start/i);
    expect(copy.CONFIRM.BLOOMWIRE_TITLE).toMatch(/Bloomwire/i);
    // Availability copy is ENVIRONMENT-INDEPENDENT: Bloomwire-assisted / manager-confirmed, never the transient
    // Meta app state ("Development mode / Standard access") which goes stale when the app changes.
    expect(copy.STATUS).not.toMatch(/available now/i);
    expect(copy.CONFIRM.AVAILABILITY_NOTE).toMatch(
      /Bloomwire-assisted|manager/i
    );
    expect(copy.CONFIRM.AVAILABILITY_NOTE).not.toMatch(
      /Development mode|Standard access/i
    );
  });

  it('gates the migration confirm on acknowledging the prerequisites (no Meta or store call until acknowledged)', async () => {
    runEmbeddedSignup.mockResolvedValue(CREDS);
    dispatch.mockResolvedValue(DTO);
    const wrapper = mountWizard({ asyncStandard: false });
    await startMigration(wrapper);

    const confirmBtn = wrapper.find(
      '[data-testid="bloomwire-wa-migration-confirm-button"]'
    );
    expect(confirmBtn.attributes('disabled')).toBeDefined();
    await confirmBtn.trigger('click');
    await flushPromises();
    expect(runEmbeddedSignup).not.toHaveBeenCalled();
    expect(dispatch).not.toHaveBeenCalled();

    await acknowledgeMigration(wrapper);
    await wrapper
      .find('[data-testid="bloomwire-wa-migration-confirm-button"]')
      .trigger('click');
    await flushPromises();
    expect(runEmbeddedSignup).toHaveBeenCalledWith(
      expect.objectContaining({ coexistence: false })
    );
  });

  it('opens migration confirmation without any Meta or store call, and cancel returns with no success state', async () => {
    const wrapper = mountWizard();
    await startMigration(wrapper);

    expect(
      wrapper.find('[data-testid="bloomwire-wa-migration-confirm"]').exists()
    ).toBe(true);
    expect(runEmbeddedSignup).not.toHaveBeenCalled();
    expect(dispatch).not.toHaveBeenCalled();

    await wrapper
      .find('[data-testid="bloomwire-wa-migration-cancel"]')
      .trigger('click');
    await flushPromises();

    expect(wrapper.find('[data-testid="bloomwire-wa-choose"]').exists()).toBe(
      true
    );
    expect(wrapper.find('[data-testid="bloomwire-wa-success"]').exists()).toBe(
      false
    );
    expect(runEmbeddedSignup).not.toHaveBeenCalled();
    expect(dispatch).not.toHaveBeenCalled();
  });

  it('confirmed migration uses coexistence false and only the synchronous Standard backend action', async () => {
    runEmbeddedSignup.mockResolvedValue(CREDS);
    dispatch.mockResolvedValue(DTO);
    const wrapper = mountWizard({ asyncStandard: false });
    await startMigration(wrapper);

    expect(runEmbeddedSignup).not.toHaveBeenCalled();
    await acknowledgeMigration(wrapper);
    await wrapper
      .find('[data-testid="bloomwire-wa-migration-confirm-button"]')
      .trigger('click');
    await flushPromises();

    expect(runEmbeddedSignup).toHaveBeenCalledWith(
      expect.objectContaining({ coexistence: false })
    );
    expect(dispatch).toHaveBeenCalledWith(
      'inboxes/createBloomwireWhatsAppEmbeddedSignup',
      expect.objectContaining(CREDS)
    );
    expect(dispatch).not.toHaveBeenCalledWith(
      'inboxes/createBloomwireWhatsAppCoexistenceEmbeddedSignup',
      expect.anything()
    );
  });

  it('confirmed migration reuses and auto-starts the async Standard lifecycle when available', async () => {
    const wrapper = mountWizard({ asyncStandard: true });
    await startMigration(wrapper);
    await acknowledgeMigration(wrapper);
    await wrapper
      .find('[data-testid="bloomwire-wa-migration-confirm-button"]')
      .trigger('click');
    await flushPromises();

    const asyncFlow = wrapper.find(
      '[data-testid="bloomwire-wa-async-standard"]'
    );
    expect(asyncFlow.exists()).toBe(true);
    expect(asyncFlow.attributes('data-auto-start')).toBe('true');
    expect(runEmbeddedSignup).not.toHaveBeenCalled();
    expect(dispatch).not.toHaveBeenCalled();
  });

  it('cancelled or failed migration never creates a success state', async () => {
    runEmbeddedSignup.mockResolvedValueOnce(null).mockResolvedValueOnce(CREDS);
    dispatch.mockRejectedValueOnce(new Error('RAW META failure'));
    const wrapper = mountWizard({ asyncStandard: false });

    await startMigration(wrapper);
    await acknowledgeMigration(wrapper);
    await wrapper
      .find('[data-testid="bloomwire-wa-migration-confirm-button"]')
      .trigger('click');
    await flushPromises();
    expect(dispatch).not.toHaveBeenCalled();
    expect(wrapper.find('[data-testid="bloomwire-wa-success"]').exists()).toBe(
      false
    );

    await wrapper.find('[data-testid="bloomwire-wa-back"]').trigger('click');
    await startMigration(wrapper);
    await acknowledgeMigration(wrapper);
    await wrapper
      .find('[data-testid="bloomwire-wa-migration-confirm-button"]')
      .trigger('click');
    await flushPromises();
    expect(wrapper.find('[data-testid="bloomwire-wa-success"]').exists()).toBe(
      false
    );
    expect(wrapper.html()).not.toContain('RAW META');
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

  it('keeps both choices visible in normal async mode, then routes only Standard to the async flow', async () => {
    const wrapper = mountWizard({ asyncStandard: true });
    expect(
      wrapper.find('[data-testid="bloomwire-wa-choice-standard"]').exists()
    ).toBe(true);
    expect(
      wrapper.find('[data-testid="bloomwire-wa-choice-coexistence"]').exists()
    ).toBe(true);

    await startRegister(wrapper);

    expect(
      wrapper.find('[data-testid="bloomwire-wa-async-standard"]').exists()
    ).toBe(true);
    expect(wrapper.find('[data-testid="bloomwire-wa-register"]').exists()).toBe(
      false
    );
  });

  it('keeps Coexistence on its existing flow when async Standard onboarding is enabled', async () => {
    const wrapper = mountWizard({ asyncStandard: true });

    await startCoexistence(wrapper);

    expect(wrapper.find('[data-testid="bloomwire-wa-register"]').exists()).toBe(
      true
    );
    expect(
      wrapper.find('[data-testid="bloomwire-wa-async-standard"]').exists()
    ).toBe(false);
  });

  it('uses the synchronous Standard fallback without removing Coexistence when the emergency switch is on', async () => {
    const wrapper = mountWizard({ asyncStandard: false });
    expect(
      wrapper.find('[data-testid="bloomwire-wa-choice-coexistence"]').exists()
    ).toBe(true);

    await startRegister(wrapper);

    expect(wrapper.find('[data-testid="bloomwire-wa-register"]').exists()).toBe(
      true
    );
    expect(
      wrapper.find('[data-testid="bloomwire-wa-async-standard"]').exists()
    ).toBe(false);
  });

  it('keeps an entered async Standard attempt mounted when the switch flips and disables only future new work', async () => {
    const asyncStandard = ref(true);
    const wrapper = mountWizard({ asyncStandard });
    await startRegister(wrapper);

    asyncStandard.value = false;
    await flushPromises();

    const asyncFlow = wrapper.find(
      '[data-testid="bloomwire-wa-async-standard"]'
    );
    expect(asyncFlow.exists()).toBe(true);
    expect(asyncFlow.attributes('data-can-start-new')).toBe('false');
    expect(wrapper.find('[data-testid="bloomwire-wa-register"]').exists()).toBe(
      false
    );
  });

  it('resumes a persisted in-flight async Standard attempt after the emergency switch turns on', () => {
    window.localStorage.setItem(
      'bloomwire_wa_onboarding_attempt:7',
      'ATT-IN-FLIGHT'
    );

    const wrapper = mountWizard({ asyncStandard: false });

    expect(
      wrapper.find('[data-testid="bloomwire-wa-async-standard"]').exists()
    ).toBe(true);
    expect(wrapper.find('[data-testid="bloomwire-wa-choose"]').exists()).toBe(
      false
    );
  });

  it('enters the synchronous Standard fallback when a resumed async child requests new work after rollback', async () => {
    window.localStorage.setItem(
      'bloomwire_wa_onboarding_attempt:7',
      'ATT-IN-FLIGHT'
    );
    const wrapper = mountWizard({ asyncStandard: false });

    wrapper.findComponent(BloomwireWhatsappAsync).vm.$emit('useSyncFallback');
    await flushPromises();

    expect(wrapper.find('[data-testid="bloomwire-wa-register"]').exists()).toBe(
      true
    );
    expect(
      wrapper.find('[data-testid="bloomwire-wa-async-standard"]').exists()
    ).toBe(false);
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

  it('runs Meta embedded signup and posts ONLY the signup credentials to the Bloomwire endpoint (Standard: NO attempt id, NO tracer)', async () => {
    runEmbeddedSignup.mockResolvedValue(CREDS);
    dispatch.mockResolvedValue(DTO);
    const wrapper = mountWizard();
    await startRegister(wrapper);
    await submit(wrapper);
    expect(runEmbeddedSignup).toHaveBeenCalledTimes(1);
    // Finding 1: Standard sends the non-secret credentials only — NO onboarding_attempt_id.
    const [, payload] = dispatch.mock.calls.find(
      c => c[0] === 'inboxes/createBloomwireWhatsAppEmbeddedSignup'
    );
    expect(payload).toMatchObject(CREDS);
    expect(payload).not.toHaveProperty('onboarding_attempt_id');
    // Finding 1: Standard never creates a real tracer nor emits browser trace events.
    expect(createOnboardingTracer).not.toHaveBeenCalled();
    expect(trace).not.toHaveBeenCalled();
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

  // Regression (post-onboarding navigation): the success screen's two links must use each route's OWN param name.
  // `inbox_dashboard` path is `accounts/:accountId/inbox/:inbox_id` → needs snake_case `inbox_id`; passing `inboxId`
  // threw "Missing required param inbox_id" right after a successful create. `settings_inbox_show` path is
  // `:inboxId/:tab?` → keeps camelCase `inboxId`.
  it('links Open inbox via inbox_dashboard with param inbox_id and Inbox settings via settings_inbox_show with param inboxId', async () => {
    runEmbeddedSignup.mockResolvedValue(CREDS);
    dispatch.mockResolvedValue(DTO);
    const wrapper = mountWizard();
    await startRegister(wrapper);
    await submit(wrapper);

    const links = wrapper.findAllComponents(RouterLinkStub);
    const openInbox = links.find(l => l.props('to').name === 'inbox_dashboard');
    const inboxSettings = links.find(
      l => l.props('to').name === 'settings_inbox_show'
    );
    expect(openInbox.props('to').params).toEqual({ inbox_id: 42 });
    expect(inboxSettings.props('to').params).toEqual({ inboxId: 42 });
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
    // Coexistence creates a real tracer and sends its opaque attempt id (+ the abort signal, stripped server-side).
    expect(createOnboardingTracer).toHaveBeenCalledTimes(1);
    expect(dispatch).toHaveBeenCalledWith(
      'inboxes/createBloomwireWhatsAppCoexistenceEmbeddedSignup',
      expect.objectContaining({ ...CREDS, onboarding_attempt_id: 'att-coex-1' })
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

  // (8): a create POST that stays pending is bounded — the timer aborts the request (real axios rejects on the
  // abort signal), and the UI fails closed with a safe error + support reference.
  it('bounds a pending create request via the abort signal and fails closed with a safe error + support reference', async () => {
    runEmbeddedSignup.mockResolvedValue(CREDS);
    // Simulate axios: the request stays pending until its abort signal fires, then it rejects (CanceledError).
    dispatch.mockImplementation(
      (_action, payload) =>
        new Promise((_resolve, reject) => {
          payload.signal?.addEventListener('abort', () =>
            reject(
              Object.assign(new Error('canceled'), { name: 'CanceledError' })
            )
          );
        })
    );
    const wrapper = mountWizard();
    await startCoexistence(wrapper);
    vi.useFakeTimers();
    wrapper.find('form').trigger('submit');
    await vi.advanceTimersByTimeAsync(45000); // CREATE_REQUEST_TIMEOUT_MS -> abort -> reject
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
});

// GPT-5.5 CHANGES REQUIRED (remaining blocker) — double-submit attempt ownership. The wizard-level active-attempt
// guard makes a second submit a pure no-op while a signup OR create is in flight, so the first attempt stays
// authoritative (one tracer, one id, one signup launch, one POST; no supersede, no abort, no support-ref change).
describe('BloomwireWhatsapp.vue — double-submit attempt ownership (active-attempt guard)', () => {
  const coexCreates = () =>
    dispatch.mock.calls.filter(call =>
      String(call[0]).includes(
        'createBloomwireWhatsAppCoexistenceEmbeddedSignup'
      )
    );

  // A signup that stays pending until we resolve it — lets the second click land WHILE the first is authenticating.
  const pendingSignup = () => {
    let resolveSignup;
    runEmbeddedSignup.mockReturnValue(
      new Promise(resolve => {
        resolveSignup = resolve;
      })
    );
    return () => resolveSignup(CREDS);
  };

  // (1)(2)(5)(7) double-submit DURING Meta signup → one tracer, one attempt id, one signup launch, no abort.
  it('is a pure no-op on a second submit during Meta signup (one tracer, one id, one signup, no abort)', async () => {
    const finishSignup = pendingSignup();
    dispatch.mockResolvedValue(DTO);
    const wrapper = mountWizard();
    await startCoexistence(wrapper);

    wrapper.find('form').trigger('submit'); // first — starts the attempt, awaits signup
    await flushPromises();
    wrapper.find('form').trigger('submit'); // second — must be a pure no-op
    await flushPromises();

    expect(createOnboardingTracer).toHaveBeenCalledTimes(1); // one tracer / one attempt id
    expect(runEmbeddedSignup).toHaveBeenCalledTimes(1); // one Meta signup launch
    expect(cancelEmbeddedSignup).not.toHaveBeenCalled(); // active attempt not aborted by the 2nd click

    finishSignup();
    await flushPromises();

    // (3)(6) first attempt remains authoritative: exactly one create POST, carrying the FIRST attempt id.
    expect(coexCreates()).toHaveLength(1);
    expect(coexCreates()[0][1].onboarding_attempt_id).toBe('att-coex-1');
    expect(wrapper.find('[data-testid="bloomwire-wa-success"]').exists()).toBe(
      true
    );
  });

  // (4) the support reference is not changed by a duplicate click (only one tracer is ever created).
  it('does not change the support reference on a duplicate click', async () => {
    const finishSignup = pendingSignup();
    dispatch.mockRejectedValue({ response: { status: 500 } }); // fail so the error + ref render
    const wrapper = mountWizard();
    await startCoexistence(wrapper);

    wrapper.find('form').trigger('submit');
    await flushPromises();
    wrapper.find('form').trigger('submit'); // no-op
    await flushPromises();
    finishSignup();
    await flushPromises();

    expect(createOnboardingTracer).toHaveBeenCalledTimes(1);
    const refEl = wrapper.find('[data-testid="bloomwire-wa-attempt-ref"]');
    expect(refEl.exists()).toBe(true);
  });

  // (8) during creating_inbox the loader replaces the form (real UI protection → no second submit is possible),
  // and the guard also blocks re-entry, so exactly one create POST is ever issued.
  it('is a pure no-op during creating_inbox: form hidden + exactly one create POST', async () => {
    runEmbeddedSignup.mockResolvedValue(CREDS);
    let resolveCreate;
    dispatch.mockReturnValue(
      new Promise(resolve => {
        resolveCreate = resolve;
      })
    );
    const wrapper = mountWizard();
    await startCoexistence(wrapper);

    wrapper.find('form').trigger('submit'); // signup resolves, create POST goes in flight (pending)
    await flushPromises();
    expect(coexCreates()).toHaveLength(1);

    // creating_inbox: the register form/submit is not rendered (loader shown), so the user cannot submit again.
    expect(wrapper.find('.loading-state').exists()).toBe(true);
    expect(wrapper.find('[data-testid="bloomwire-wa-register"]').exists()).toBe(
      false
    );
    expect(wrapper.find('form').exists()).toBe(false);

    resolveCreate(DTO);
    await flushPromises();
    expect(coexCreates()).toHaveLength(1); // still exactly one POST
    expect(createOnboardingTracer).toHaveBeenCalledTimes(1);
    expect(wrapper.find('[data-testid="bloomwire-wa-success"]').exists()).toBe(
      true
    );
  });

  // (9) after a terminal failure, a manual retry starts a FRESH attempt id.
  it('mints a different attempt id on manual retry after a terminal failure', async () => {
    runEmbeddedSignup.mockResolvedValue(CREDS);
    dispatch.mockRejectedValueOnce({ response: { status: 500 } });
    const wrapper = mountWizard();
    await startCoexistence(wrapper);

    await submit(wrapper); // attempt 1 → fails (terminal)
    const id1 = coexCreates().at(-1)[1].onboarding_attempt_id;

    dispatch.mockResolvedValueOnce(DTO);
    await submit(wrapper); // retry → attempt 2
    const id2 = coexCreates().at(-1)[1].onboarding_attempt_id;

    expect(id1).toBe('att-coex-1');
    expect(id2).toBe('att-coex-2');
    expect(id1).not.toBe(id2);
    expect(createOnboardingTracer).toHaveBeenCalledTimes(2);
  });
});

// GPT-5.5 CHANGES REQUIRED — Finding 2 (fresh attempt id per attempt) + Finding 3 (lifecycle-safe create / late
// response guard). All Meta/store calls mocked; no real Meta, no real HTTP.
describe('BloomwireWhatsapp.vue — fresh attempt id + lifecycle-safe create (findings 2 & 3)', () => {
  const events = () => trace.mock.calls.map(call => call[0]);
  const lastCoexPayload = () =>
    dispatch.mock.calls
      .filter(c =>
        String(c[0]).includes(
          'createBloomwireWhatsAppCoexistenceEmbeddedSignup'
        )
      )
      .at(-1)[1];

  // (2) attempt 1 and retry attempt 2 mint DIFFERENT ids; each id flows end-to-end into its own create POST.
  it('mints a fresh attempt id (new tracer) for every Coexistence attempt and retry', async () => {
    runEmbeddedSignup.mockResolvedValue(CREDS);
    dispatch.mockRejectedValue({ response: { status: 500 } }); // both attempts fail so we can retry
    const wrapper = mountWizard();
    await startCoexistence(wrapper);

    await submit(wrapper); // attempt 1
    const id1 = lastCoexPayload().onboarding_attempt_id;

    await submit(wrapper); // retry -> attempt 2
    const id2 = lastCoexPayload().onboarding_attempt_id;

    expect(createOnboardingTracer).toHaveBeenCalledTimes(2);
    expect(id1).toBe('att-coex-1');
    expect(id2).toBe('att-coex-2');
    expect(id1).not.toBe(id2);
  });

  // (3) a late create SUCCESS after leaving the flow (unmount) is ignored: no success trace, no finish trace.
  it('ignores a late create success after unmount (no late trace / transition)', async () => {
    runEmbeddedSignup.mockResolvedValue(CREDS);
    let resolveDispatch;
    dispatch.mockReturnValue(
      new Promise(resolve => {
        resolveDispatch = resolve;
      })
    );
    const wrapper = mountWizard();
    await startCoexistence(wrapper);
    wrapper.find('form').trigger('submit');
    await flushPromises(); // create in flight
    expect(events()).toContain('create_request_started');

    wrapper.unmount(); // leave the flow -> cancel + abort + mark left
    expect(cancelEmbeddedSignup).toHaveBeenCalled();
    const before = events().length;

    resolveDispatch(DTO); // late success arrives after leaving
    await flushPromises();

    const after = events().slice(before);
    expect(after).not.toContain('create_request_succeeded');
    expect(after).not.toContain('frontend_success_transition');
    expect(after).not.toContain('attempt_finished');
  });

  // (3) a late create FAILURE after leaving the flow is likewise ignored (no late error trace / transition).
  it('ignores a late create failure after unmount', async () => {
    runEmbeddedSignup.mockResolvedValue(CREDS);
    let rejectDispatch;
    dispatch.mockReturnValue(
      new Promise((_resolve, reject) => {
        rejectDispatch = reject;
      })
    );
    const wrapper = mountWizard();
    await startCoexistence(wrapper);
    wrapper.find('form').trigger('submit');
    await flushPromises();
    wrapper.unmount();
    const before = events().length;

    rejectDispatch({ response: { status: 500 } });
    await flushPromises();

    const after = events().slice(before);
    expect(after).not.toContain('create_request_failed');
    expect(after).not.toContain('frontend_error_transition');
  });

  // (3) a route change during a pending create cancels the run (cancel + guard prevents late mutation).
  it('cancels the in-flight run on route change during a pending create', async () => {
    runEmbeddedSignup.mockResolvedValue(CREDS);
    dispatch.mockReturnValue(new Promise(() => {}));
    const wrapper = mountWizard();
    await startCoexistence(wrapper);
    wrapper.find('form').trigger('submit');
    await flushPromises();
    const guard = routeLeaveGuard.mock.calls.at(-1)[0];
    guard(); // route leave
    expect(cancelEmbeddedSignup).toHaveBeenCalled();
  });
});

// Duplicate-number UX: advisory preflight (blocks the popup for an already-connected number) + backend error-code
// mapping to specific safe messages. All Meta/store calls mocked; no real Meta, no real HTTP.
describe('BloomwireWhatsapp.vue — duplicate-number preflight + error-code mapping', () => {
  const PREFLIGHT = 'inboxes/checkBloomwireWhatsAppPhoneAvailability';

  // Routes store.dispatch: the preflight action resolves the given availability; everything else (create) uses
  // `create` (defaults to resolving the DTO).
  const routeDispatch = ({
    availability = { status: 'available' },
    create,
  } = {}) => {
    dispatch.mockImplementation((action, payload) => {
      if (action === PREFLIGHT) return Promise.resolve(availability);
      return typeof create === 'function'
        ? create(action, payload)
        : Promise.resolve(DTO);
    });
  };

  const typeNumber = async (wrapper, value) => {
    await wrapper
      .find('[data-testid="bloomwire-wa-phone-number"]')
      .setValue(value);
  };

  const errorText = wrapper =>
    wrapper.find('[data-testid="bloomwire-wa-error"]').text();

  // (Fix 3) copy under the number field.
  it('shows the "use a number not already connected" note under the number field', async () => {
    const wrapper = mountWizard();
    await startRegister(wrapper);
    expect(
      wrapper.find('[data-testid="bloomwire-wa-phone-number-note"]').text()
    ).toBe(`${B}.PHONE_NUMBER.NOTE`);
  });

  // (1) preflight available → Meta popup opens.
  it('opens the Meta popup when the preflight reports the number is available', async () => {
    routeDispatch({ availability: { status: 'available' } });
    runEmbeddedSignup.mockResolvedValue(CREDS);
    const wrapper = mountWizard();
    await startRegister(wrapper);
    await typeNumber(wrapper, '+15551239999');
    await submit(wrapper);
    expect(dispatch).toHaveBeenCalledWith(
      PREFLIGHT,
      expect.objectContaining({ phoneNumber: '+15551239999' })
    );
    expect(runEmbeddedSignup).toHaveBeenCalledTimes(1); // popup opened
  });

  // (2) preflight already_connected → Meta popup does NOT open, no create POST.
  it('does NOT open the Meta popup when the preflight reports already_connected', async () => {
    routeDispatch({ availability: { status: 'already_connected' } });
    runEmbeddedSignup.mockResolvedValue(CREDS);
    const wrapper = mountWizard();
    await startRegister(wrapper);
    await typeNumber(wrapper, '+15551230001');
    await submit(wrapper);
    expect(runEmbeddedSignup).not.toHaveBeenCalled();
    const creates = dispatch.mock.calls.filter(c =>
      String(c[0]).includes('EmbeddedSignup')
    );
    expect(creates).toHaveLength(0);
  });

  // (3) preflight already_connected → duplicate warning displayed.
  it('shows the duplicate-number warning when the preflight reports already_connected', async () => {
    routeDispatch({ availability: { status: 'already_connected' } });
    const wrapper = mountWizard();
    await startRegister(wrapper);
    await typeNumber(wrapper, '+15551230001');
    await submit(wrapper);
    expect(errorText(wrapper)).toBe(`${B}.ERRORS.PHONE_NUMBER_TAKEN`);
  });

  // Advisory only: a preflight error fails OPEN (popup still opens).
  it('fails open (opens the popup) when the preflight request errors', async () => {
    dispatch.mockImplementation(action => {
      if (action === PREFLIGHT) return Promise.reject(new Error('network'));
      return Promise.resolve(DTO);
    });
    runEmbeddedSignup.mockResolvedValue(CREDS);
    const wrapper = mountWizard();
    await startRegister(wrapper);
    await typeNumber(wrapper, '+15551239999');
    await submit(wrapper);
    expect(runEmbeddedSignup).toHaveBeenCalledTimes(1);
  });

  // (5) Standard 422 phone_number_taken → specific message.
  it('maps a Standard 422 phone_number_taken to the specific message', async () => {
    runEmbeddedSignup.mockResolvedValue(CREDS);
    dispatch.mockRejectedValue({
      response: { status: 422, data: { code: 'phone_number_taken' } },
    });
    const wrapper = mountWizard();
    await startRegister(wrapper); // Standard
    await submit(wrapper);
    expect(errorText(wrapper)).toBe(`${B}.ERRORS.PHONE_NUMBER_TAKEN`);
  });

  // (6) Coexistence 422 phone_number_taken → specific message.
  it('maps a Coexistence 422 phone_number_taken to the specific message', async () => {
    runEmbeddedSignup.mockResolvedValue(CREDS);
    dispatch.mockRejectedValue({
      response: { status: 422, data: { code: 'phone_number_taken' } },
    });
    const wrapper = mountWizard();
    await startCoexistence(wrapper); // Coexistence
    await submit(wrapper);
    expect(errorText(wrapper)).toBe(`${B}.ERRORS.PHONE_NUMBER_TAKEN`);
  });

  // (7) phone_number_id_conflict → specific message.
  it('maps 422 phone_number_id_conflict to the specific message', async () => {
    runEmbeddedSignup.mockResolvedValue(CREDS);
    dispatch.mockRejectedValue({
      response: { status: 422, data: { code: 'phone_number_id_conflict' } },
    });
    const wrapper = mountWizard();
    await startRegister(wrapper);
    await submit(wrapper);
    expect(errorText(wrapper)).toBe(`${B}.ERRORS.PHONE_NUMBER_ID_CONFLICT`);
  });

  // (8) unknown/5xx → generic safe message.
  it('falls back to the generic message for an unknown 5xx (no known code)', async () => {
    runEmbeddedSignup.mockResolvedValue(CREDS);
    dispatch.mockRejectedValue({
      response: { status: 500, data: { code: 'meta_error' } },
    });
    const wrapper = mountWizard();
    await startRegister(wrapper);
    await submit(wrapper);
    expect(errorText(wrapper)).toBe(`${B}.ERROR`);
  });
});

// GPT-5.5 CHANGES REQUIRED (PR #131) — the advisory preflight must be lifecycle-safe: bounded (timeout aborts),
// abortable on unmount/route change, stale-checked after the await, and never opens Meta after the flow left.
describe('BloomwireWhatsapp.vue — lifecycle-safe bounded preflight', () => {
  const PREFLIGHT = 'inboxes/checkBloomwireWhatsAppPhoneAvailability';
  const typeNumber = async (wrapper, value) =>
    wrapper.find('[data-testid="bloomwire-wa-phone-number"]').setValue(value);

  // (timeout) A never-settling preflight is aborted by the timeout and fails OPEN → the Meta popup still opens.
  it('bounds the preflight with a timeout that aborts and fails open (popup opens)', async () => {
    dispatch.mockImplementation((action, payload) => {
      if (action === PREFLIGHT) {
        return new Promise((_resolve, reject) => {
          payload.signal?.addEventListener('abort', () =>
            reject(
              Object.assign(new Error('canceled'), { name: 'CanceledError' })
            )
          );
        });
      }
      return Promise.resolve(DTO);
    });
    runEmbeddedSignup.mockResolvedValue(CREDS);
    const wrapper = mountWizard();
    await startRegister(wrapper);
    await typeNumber(wrapper, '+15551239999');
    vi.useFakeTimers();
    wrapper.find('form').trigger('submit');
    await vi.advanceTimersByTimeAsync(8000); // PREFLIGHT_TIMEOUT_MS -> abort -> fail open
    vi.useRealTimers();
    await flushPromises();
    expect(runEmbeddedSignup).toHaveBeenCalledTimes(1);
  });

  // (unmount during pending preflight) a late preflight success must NOT open Meta after the flow left.
  it('does not open Meta when unmounted while the preflight is pending (late response ignored)', async () => {
    let resolvePreflight;
    dispatch.mockImplementation(action => {
      if (action === PREFLIGHT) {
        return new Promise(resolve => {
          resolvePreflight = resolve;
        });
      }
      return Promise.resolve(DTO);
    });
    runEmbeddedSignup.mockResolvedValue(CREDS);
    const wrapper = mountWizard();
    await startRegister(wrapper);
    await typeNumber(wrapper, '+15551239999');
    wrapper.find('form').trigger('submit');
    await flushPromises(); // preflight in flight
    expect(cancelEmbeddedSignup).not.toHaveBeenCalled();

    wrapper.unmount(); // leave the flow -> cleanup aborts the preflight
    resolvePreflight({ status: 'available' }); // late success arrives after leaving
    await flushPromises();

    expect(runEmbeddedSignup).not.toHaveBeenCalled(); // Meta popup never opened
  });

  // (route leave during pending preflight) same protection via onBeforeRouteLeave.
  it('does not open Meta when the route is left while the preflight is pending', async () => {
    let resolvePreflight;
    dispatch.mockImplementation(action => {
      if (action === PREFLIGHT) {
        return new Promise(resolve => {
          resolvePreflight = resolve;
        });
      }
      return Promise.resolve(DTO);
    });
    runEmbeddedSignup.mockResolvedValue(CREDS);
    const wrapper = mountWizard();
    await startRegister(wrapper);
    await typeNumber(wrapper, '+15551239999');
    wrapper.find('form').trigger('submit');
    await flushPromises();

    const guard = routeLeaveGuard.mock.calls.at(-1)[0];
    guard(); // route leave
    resolvePreflight({ status: 'available' });
    await flushPromises();

    expect(runEmbeddedSignup).not.toHaveBeenCalled();
  });

  // A manual retry after a preflight-blocked attempt starts cleanly (attemptActive released; a fresh attempt runs).
  it('allows a clean manual retry after a preflight already_connected block', async () => {
    dispatch
      .mockImplementationOnce(action =>
        action === PREFLIGHT
          ? Promise.resolve({ status: 'already_connected' })
          : Promise.resolve(DTO)
      )
      .mockImplementation(action =>
        action === PREFLIGHT
          ? Promise.resolve({ status: 'available' })
          : Promise.resolve(DTO)
      );
    runEmbeddedSignup.mockResolvedValue(CREDS);
    const wrapper = mountWizard();
    await startRegister(wrapper);
    await typeNumber(wrapper, '+15551230001');

    await submit(wrapper); // attempt 1: preflight blocks -> no popup
    expect(runEmbeddedSignup).not.toHaveBeenCalled();

    await submit(wrapper); // retry: preflight available -> popup opens
    expect(runEmbeddedSignup).toHaveBeenCalledTimes(1);
  });
});

// Phase 5 (resume) — Action-Required completion + Recheck permission. When the backend DTO marks the completed
// signup action_required (outbound-messaging permission not yet granted), the wizard shows the Action-Required
// panel (NOT the Ready success), with a Recheck permission action and its loading / success / failure states. No
// raw actor id / token / PIN / auth code / secret is ever rendered, and it never tells the user to "reconnect".
describe('BloomwireWhatsapp.vue — Action-Required + Recheck permission (Phase 5 resume)', () => {
  const CREATE = 'inboxes/createBloomwireWhatsAppEmbeddedSignup';
  const RECHECK = 'inboxes/recheckBloomwireWhatsAppCapability';
  const ACTION_DTO = {
    inbox: { id: 42, name: 'Acme WhatsApp' },
    channel: { id: 7, type: 'Channel::Whatsapp', source: 'bloomwire_managed' },
    setup: { id: 3, status: 'action_required', readiness: 'blocked' },
    phone: { display_phone_number: '••••0001' },
    action_required: {
      reason: 'outbound_messaging_permission_required',
      resolution: 'SAFE-RESOLUTION',
    },
  };
  const READY_DTO = {
    setup: { id: 3, status: 'ready_for_webhook' },
    inbox: { id: 42, name: 'Acme WhatsApp' },
    ready: true,
  };

  // Reach the Action-Required completion screen via a Standard signup whose create resolves an action_required DTO.
  const reachActionRequired = async recheck => {
    dispatch.mockImplementation(action => {
      if (action === CREATE) return Promise.resolve(ACTION_DTO);
      if (action === RECHECK && recheck) return recheck(action);
      return Promise.resolve({});
    });
    runEmbeddedSignup.mockResolvedValue(CREDS);
    const wrapper = mountWizard();
    await startRegister(wrapper);
    await submit(wrapper);
    return wrapper;
  };

  it('renders the Action-Required panel (not Ready) with a Recheck action and no secrets', async () => {
    const wrapper = await reachActionRequired();
    const html = wrapper.html();
    expect(
      wrapper.find('[data-testid="bloomwire-wa-action-required"]').exists()
    ).toBe(true);
    expect(wrapper.find('[data-testid="bloomwire-wa-success"]').exists()).toBe(
      false
    );
    expect(wrapper.find('[data-testid="bloomwire-wa-recheck"]').exists()).toBe(
      true
    );
    expect(html).not.toContain('META-CODE');
    expect(html).not.toContain('WABA-1');
    expect(html).not.toContain('PNID-1');
    expect(html.toLowerCase()).not.toContain('api_key');
    expect(html).not.toContain('SAFE-RESOLUTION');
  });

  it('promotes to the Ready panel when the recheck reports ready:true (no reconnect, no new inbox)', async () => {
    const wrapper = await reachActionRequired(() => Promise.resolve(READY_DTO));
    await wrapper.find('[data-testid="bloomwire-wa-recheck"]').trigger('click');
    await flushPromises();
    expect(dispatch).toHaveBeenCalledWith(RECHECK, { setupId: 3 });
    expect(wrapper.find('[data-testid="bloomwire-wa-success"]').exists()).toBe(
      true
    );
    expect(
      wrapper.find('[data-testid="bloomwire-wa-action-required"]').exists()
    ).toBe(false);
  });

  it('shows the still-pending message when the task is still not granted', async () => {
    const wrapper = await reachActionRequired(() =>
      Promise.resolve({ ...ACTION_DTO, ready: false })
    );
    await wrapper.find('[data-testid="bloomwire-wa-recheck"]').trigger('click');
    await flushPromises();
    expect(
      wrapper.find('[data-testid="bloomwire-wa-recheck-pending"]').exists()
    ).toBe(true);
    expect(
      wrapper.find('[data-testid="bloomwire-wa-action-required"]').exists()
    ).toBe(true);
  });

  it('shows a safe failure message when the recheck request errors (still retryable, no leak)', async () => {
    const wrapper = await reachActionRequired(() =>
      Promise.reject(new Error('RAW META 500: leaked-token'))
    );
    await wrapper.find('[data-testid="bloomwire-wa-recheck"]').trigger('click');
    await flushPromises();
    expect(
      wrapper.find('[data-testid="bloomwire-wa-recheck-failed"]').exists()
    ).toBe(true);
    expect(wrapper.html()).not.toContain('leaked-token');
    expect(
      wrapper.find('[data-testid="bloomwire-wa-action-required"]').exists()
    ).toBe(true);
  });
});
