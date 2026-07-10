import { ref } from 'vue';
import { mount, RouterLinkStub } from '@vue/test-utils';
import BloomwireWhatsappAsync from '../BloomwireWhatsappAsync.vue';
import { ONBOARDING_STATES } from 'dashboard/composables/useAsyncWhatsappOnboarding';

// Keep the real ONBOARDING_STATES; only override the composable factory so we can drive the component's state.
let flow;
vi.mock(
  'dashboard/composables/useAsyncWhatsappOnboarding',
  async importOriginal => {
    const actual = await importOriginal();
    return { ...actual, useAsyncWhatsappOnboarding: () => flow };
  }
);
vi.mock('dashboard/composables/store', () => ({
  useStoreGetters: () => ({ getCurrentAccountId: ref(7) }),
}));
vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));

const makeFlow = (overrides = {}) => ({
  state: ref(ONBOARDING_STATES.IDLE),
  attempt: ref(null),
  errorCode: ref(null),
  takingLongerThanUsual: ref(false),
  start: vi.fn(),
  resume: vi.fn(),
  relaunch: vi.fn(),
  cancel: vi.fn(),
  checkStatus: vi.fn(),
  restart: vi.fn(),
  stopPolling: vi.fn(),
  ...overrides,
});

const mountAsync = (props = {}) =>
  mount(BloomwireWhatsappAsync, {
    props,
    global: {
      mocks: { $t: key => key },
      stubs: {
        RouterLink: RouterLinkStub,
        NextButton: {
          inheritAttrs: false,
          template:
            '<button :data-testid="$attrs[\'data-testid\']" @click="$emit(\'click\')">{{ label }}</button>',
          props: ['label'],
        },
        Icon: true,
        LoadingState: true,
      },
    },
  });

const has = (wrapper, testid) =>
  wrapper.find(`[data-testid="${testid}"]`).exists();

describe('BloomwireWhatsappAsync.vue (async onboarding wizard UI)', () => {
  beforeEach(() => {
    flow = makeFlow();
  });

  it('resumes any in-flight attempt on mount and stops polling (without clearing it) on unmount', () => {
    const wrapper = mountAsync();
    expect(flow.resume).toHaveBeenCalledTimes(1);
    wrapper.unmount();
    expect(flow.stopPolling).toHaveBeenCalledTimes(1);
  });

  it('shows the start screen when idle and can return to the shared chooser', async () => {
    const wrapper = mountAsync();
    expect(has(wrapper, 'bloomwire-wa-async-start')).toBe(true);
    expect(has(wrapper, 'bloomwire-wa-async-processing')).toBe(false);

    await wrapper
      .find('[data-testid="bloomwire-wa-async-back"]')
      .trigger('click');
    expect(wrapper.emitted('back')).toHaveLength(1);
  });

  it('shows a distinct waiting-for-Meta screen with relaunch and server cancellation', async () => {
    flow = makeFlow({ state: ref(ONBOARDING_STATES.WAITING_META) });
    const wrapper = mountAsync();

    expect(has(wrapper, 'bloomwire-wa-async-waiting-meta')).toBe(true);
    expect(has(wrapper, 'bloomwire-wa-async-relaunch')).toBe(true);
    expect(has(wrapper, 'bloomwire-wa-async-cancel')).toBe(true);
    expect(has(wrapper, 'bloomwire-wa-async-processing')).toBe(false);

    await wrapper
      .find('[data-testid="bloomwire-wa-async-relaunch"]')
      .trigger('click');
    await wrapper
      .find('[data-testid="bloomwire-wa-async-cancel"]')
      .trigger('click');

    expect(flow.relaunch).toHaveBeenCalledTimes(1);
    expect(flow.cancel).toHaveBeenCalledTimes(1);
  });

  it('labels waiting recovery as Standard and shows its sanitized error reference', () => {
    flow = makeFlow({
      state: ref(ONBOARDING_STATES.WAITING_META),
      errorCode: ref('meta_popup_failed'),
    });
    const wrapper = mountAsync();

    expect(has(wrapper, 'bloomwire-wa-async-flow-label')).toBe(true);
    expect(
      wrapper.find('[data-testid="bloomwire-wa-async-flow-label"]').text()
    ).toBe(
      'INBOX_MGMT.ADD.WHATSAPP.BLOOMWIRE_MANAGED.ASYNC.STANDARD_FLOW_LABEL'
    );
    expect(
      wrapper.find('[data-testid="bloomwire-wa-async-error-code"]').text()
    ).toContain('meta_popup_failed');
  });

  it('shows active processing without offering waiting_meta cancellation', () => {
    flow = makeFlow({ state: ref(ONBOARDING_STATES.PROCESSING) });
    const wrapper = mountAsync();
    expect(has(wrapper, 'bloomwire-wa-async-processing')).toBe(true);
    expect(has(wrapper, 'bloomwire-wa-async-cancel')).toBe(false);
    expect(has(wrapper, 'bloomwire-wa-async-longer')).toBe(false);
  });

  it('surfaces the "taking longer than usual" note while processing past the threshold', () => {
    flow = makeFlow({
      state: ref(ONBOARDING_STATES.PROCESSING),
      takingLongerThanUsual: ref(true),
    });
    expect(has(mountAsync(), 'bloomwire-wa-async-longer')).toBe(true);
  });

  it('shows the success screen with an open-inbox link when completed', () => {
    flow = makeFlow({
      state: ref(ONBOARDING_STATES.COMPLETED),
      attempt: ref({ inbox_id: 42, phone: '****1234' }),
    });
    const wrapper = mountAsync();
    expect(has(wrapper, 'bloomwire-wa-async-success')).toBe(true);
    expect(has(wrapper, 'bloomwire-wa-async-open-inbox')).toBe(true);
  });

  it('shows the Meta-session-expired screen only for a server-reported expired status', () => {
    flow = makeFlow({ state: ref(ONBOARDING_STATES.EXPIRED) });
    const wrapper = mountAsync();
    expect(has(wrapper, 'bloomwire-wa-async-expired')).toBe(true);
    expect(has(wrapper, 'bloomwire-wa-async-attempt-not-found')).toBe(false);
    expect(has(wrapper, 'bloomwire-wa-async-restart')).toBe(true);
  });

  it('labels a terminal failure as Standard and shows its sanitized error reference', () => {
    flow = makeFlow({
      state: ref(ONBOARDING_STATES.FAILED),
      errorCode: ref('missing_code'),
    });
    const wrapper = mountAsync();

    expect(
      wrapper.find('[data-testid="bloomwire-wa-async-failed-title"]').text()
    ).toBe('INBOX_MGMT.ADD.WHATSAPP.BLOOMWIRE_MANAGED.ASYNC.FAILED.TITLE');
    expect(
      wrapper.find('[data-testid="bloomwire-wa-async-flow-label"]').text()
    ).toBe(
      'INBOX_MGMT.ADD.WHATSAPP.BLOOMWIRE_MANAGED.ASYNC.STANDARD_FLOW_LABEL'
    );
    expect(
      wrapper.find('[data-testid="bloomwire-wa-async-error-code"]').text()
    ).toContain('missing_code');
  });

  it('shows a distinct recoverable attempt-not-found screen with Check status and Restart', async () => {
    flow = makeFlow({ state: ref(ONBOARDING_STATES.ATTEMPT_NOT_FOUND) });
    const wrapper = mountAsync();
    expect(has(wrapper, 'bloomwire-wa-async-attempt-not-found')).toBe(true);
    expect(has(wrapper, 'bloomwire-wa-async-expired')).toBe(false);
    expect(has(wrapper, 'bloomwire-wa-async-check-status')).toBe(true);
    expect(has(wrapper, 'bloomwire-wa-async-restart')).toBe(true);

    await wrapper
      .find('[data-testid="bloomwire-wa-async-check-status"]')
      .trigger('click');
    expect(flow.checkStatus).toHaveBeenCalledTimes(1);
  });

  it('routes Restart to the synchronous Standard fallback when new async work is emergency-disabled', async () => {
    flow = makeFlow({ state: ref(ONBOARDING_STATES.ATTEMPT_NOT_FOUND) });
    const wrapper = mountAsync({ canStartNewAsync: false });

    await wrapper
      .find('[data-testid="bloomwire-wa-async-restart"]')
      .trigger('click');

    expect(flow.cancel).toHaveBeenCalledTimes(1);
    expect(flow.restart).not.toHaveBeenCalled();
    expect(wrapper.emitted('useSyncFallback')).toHaveLength(1);
  });
});
