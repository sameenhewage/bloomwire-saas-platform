import {
  useAsyncWhatsappOnboarding,
  ONBOARDING_STATES,
  ATTEMPT_STORAGE_PREFIX,
} from '../useAsyncWhatsappOnboarding';
import WhatsappChannel from 'dashboard/api/channel/whatsappChannel';

vi.mock('dashboard/api/channel/whatsappChannel', () => ({
  default: {
    createBloomwireOnboardingAttempt: vi.fn(),
    submitBloomwireOnboardingAttempt: vi.fn(),
    fetchBloomwireOnboardingAttempt: vi.fn(),
  },
}));

let runEmbeddedSignupMock;
let cancelPopupMock;
vi.mock('../useWhatsappEmbeddedSignup', () => ({
  useWhatsappEmbeddedSignup: () => ({
    runEmbeddedSignup: runEmbeddedSignupMock,
    cancel: cancelPopupMock,
  }),
}));

const flush = () =>
  new Promise(resolve => {
    setTimeout(resolve, 0);
  });

const CREDS = {
  code: 'META-CODE',
  business_id: 'BIZ-1',
  waba_id: 'WABA-1',
  phone_number_id: 'PNID-1',
};

// Large poll interval so the poller does not auto-fire again during the fast tests; each test cancels to clean up.
const build = (overrides = {}) =>
  useAsyncWhatsappOnboarding({
    accountId: 7,
    pollIntervalMs: 100000,
    longerThanUsualMs: 100000,
    ...overrides,
  });

describe('useAsyncWhatsappOnboarding', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    window.localStorage.clear();
    runEmbeddedSignupMock = vi.fn().mockResolvedValue(CREDS);
    cancelPopupMock = vi.fn();
    WhatsappChannel.createBloomwireOnboardingAttempt.mockResolvedValue({
      data: { attempt_id: 'ATT-1', status: 'waiting_meta' },
    });
    WhatsappChannel.submitBloomwireOnboardingAttempt.mockResolvedValue({
      data: { attempt_id: 'ATT-1', status: 'queued' },
    });
    WhatsappChannel.fetchBloomwireOnboardingAttempt.mockResolvedValue({
      data: { attempt_id: 'ATT-1', status: 'processing' },
    });
  });

  it('start(): creates + persists the attempt (account-scoped), launches the popup with NO 180s watchdog, submits, then polls', async () => {
    const flow = build();
    await flow.start();
    await flush();
    try {
      expect(
        WhatsappChannel.createBloomwireOnboardingAttempt
      ).toHaveBeenCalled();
      expect(window.localStorage.getItem(`${ATTEMPT_STORAGE_PREFIX}:7`)).toBe(
        'ATT-1'
      );
      expect(runEmbeddedSignupMock).toHaveBeenCalledWith({
        overallTimeoutMs: null,
      });
      expect(
        WhatsappChannel.submitBloomwireOnboardingAttempt
      ).toHaveBeenCalledWith('ATT-1', CREDS);
      expect(
        WhatsappChannel.fetchBloomwireOnboardingAttempt
      ).toHaveBeenCalledWith('ATT-1');
      expect(flow.state.value).toBe(ONBOARDING_STATES.PROCESSING);
    } finally {
      flow.cancel();
    }
  });

  it('reaches a terminal outcome and clears the persisted attempt id', async () => {
    WhatsappChannel.fetchBloomwireOnboardingAttempt.mockResolvedValue({
      data: { attempt_id: 'ATT-1', status: 'completed', channel_id: 42 },
    });
    const flow = build();
    await flow.start();
    await flush();
    expect(flow.state.value).toBe(ONBOARDING_STATES.COMPLETED);
    expect(
      window.localStorage.getItem(`${ATTEMPT_STORAGE_PREFIX}:7`)
    ).toBeNull();
  });

  it('maps action_required and surfaces the safe error code', async () => {
    WhatsappChannel.fetchBloomwireOnboardingAttempt.mockResolvedValue({
      data: {
        attempt_id: 'ATT-1',
        status: 'action_required',
        error_code: 'outbound_messaging_permission_required',
      },
    });
    const flow = build();
    await flow.start();
    await flush();
    expect(flow.state.value).toBe(ONBOARDING_STATES.ACTION_REQUIRED);
    expect(flow.errorCode.value).toBe('outbound_messaging_permission_required');
  });

  it('a dismissed Meta popup cancels the flow without submitting', async () => {
    runEmbeddedSignupMock.mockResolvedValue(null);
    const flow = build();
    await flow.start();
    expect(
      WhatsappChannel.submitBloomwireOnboardingAttempt
    ).not.toHaveBeenCalled();
    expect(flow.state.value).toBe(ONBOARDING_STATES.CANCELLED);
    expect(cancelPopupMock).toHaveBeenCalled();
    expect(
      window.localStorage.getItem(`${ATTEMPT_STORAGE_PREFIX}:7`)
    ).toBeNull();
  });

  it('resume(): resumes polling a persisted in-flight attempt for this account', async () => {
    window.localStorage.setItem(`${ATTEMPT_STORAGE_PREFIX}:7`, 'ATT-STORED');
    const flow = build();
    const resumed = flow.resume();
    await flush();
    try {
      expect(resumed).toBe(true);
      expect(
        WhatsappChannel.fetchBloomwireOnboardingAttempt
      ).toHaveBeenCalledWith('ATT-STORED');
      expect(flow.state.value).toBe(ONBOARDING_STATES.PROCESSING);
    } finally {
      flow.cancel();
    }
  });

  it('resume(): returns false when there is no persisted attempt', () => {
    expect(build().resume()).toBe(false);
  });

  it('a 404 while polling stops and surfaces expired (attempt gone / foreign)', async () => {
    WhatsappChannel.fetchBloomwireOnboardingAttempt.mockRejectedValue({
      response: { status: 404 },
    });
    window.localStorage.setItem(`${ATTEMPT_STORAGE_PREFIX}:7`, 'ATT-GONE');
    const flow = build();
    flow.resume();
    await flush();
    expect(flow.state.value).toBe(ONBOARDING_STATES.EXPIRED);
    expect(
      window.localStorage.getItem(`${ATTEMPT_STORAGE_PREFIX}:7`)
    ).toBeNull();
  });

  it('flags "taking longer than usual" once the threshold passes', async () => {
    const flow = build({ longerThanUsualMs: 10 });
    await flow.start();
    await new Promise(resolve => {
      setTimeout(resolve, 30);
    });
    try {
      expect(flow.takingLongerThanUsual.value).toBe(true);
    } finally {
      flow.cancel();
    }
  });

  it('cancel(): stops polling, clears state + persisted id, and cancels the popup', async () => {
    const flow = build();
    await flow.start();
    await flush();
    flow.cancel();
    expect(flow.state.value).toBe(ONBOARDING_STATES.CANCELLED);
    expect(flow.attemptId.value).toBeNull();
    expect(
      window.localStorage.getItem(`${ATTEMPT_STORAGE_PREFIX}:7`)
    ).toBeNull();
    expect(cancelPopupMock).toHaveBeenCalled();
  });

  it('restart(): cancels the current attempt and opens a fresh one', async () => {
    const flow = build();
    await flow.start();
    await flush();
    await flow.restart();
    await flush();
    try {
      expect(
        WhatsappChannel.createBloomwireOnboardingAttempt
      ).toHaveBeenCalledTimes(2);
    } finally {
      flow.cancel();
    }
  });
});
