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

  it('submits the already-created attempt when its delayed Meta popup result arrives', async () => {
    let resolvePopup;
    runEmbeddedSignupMock.mockReturnValue(
      new Promise(resolve => {
        resolvePopup = resolve;
      })
    );
    const flow = build();
    const startPromise = flow.start();
    await flush();

    expect(
      WhatsappChannel.createBloomwireOnboardingAttempt
    ).toHaveBeenCalledTimes(1);
    expect(window.localStorage.getItem(`${ATTEMPT_STORAGE_PREFIX}:7`)).toBe(
      'ATT-1'
    );

    resolvePopup(CREDS);
    await startPromise;
    await flush();
    try {
      expect(
        WhatsappChannel.submitBloomwireOnboardingAttempt
      ).toHaveBeenCalledWith('ATT-1', CREDS);
      expect(
        WhatsappChannel.createBloomwireOnboardingAttempt
      ).toHaveBeenCalledTimes(1);
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

  it('maps an explicit server expired status to the expired state', async () => {
    WhatsappChannel.fetchBloomwireOnboardingAttempt.mockResolvedValue({
      data: { attempt_id: 'ATT-1', status: 'expired' },
    });
    const flow = build();
    await flow.start();
    await flush();
    expect(flow.state.value).toBe(ONBOARDING_STATES.EXPIRED);
    expect(flow.state.value).not.toBe(ONBOARDING_STATES.ATTEMPT_NOT_FOUND);
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

  it('maps a generic polling 404 to attempt_not_found, never expired or a sync fallback, and clears stale storage', async () => {
    WhatsappChannel.fetchBloomwireOnboardingAttempt.mockRejectedValue({
      response: { status: 404 },
    });
    window.localStorage.setItem(`${ATTEMPT_STORAGE_PREFIX}:7`, 'ATT-GONE');
    const flow = build();
    flow.resume();
    await flush();
    expect(flow.state.value).toBe(ONBOARDING_STATES.ATTEMPT_NOT_FOUND);
    expect(flow.state.value).not.toBe(ONBOARDING_STATES.EXPIRED);
    expect(flow.state.value).not.toBe('sync');
    expect(flow.errorCode.value).toBe('attempt_not_found');
    expect(
      window.localStorage.getItem(`${ATTEMPT_STORAGE_PREFIX}:7`)
    ).toBeNull();
  });

  it('checkStatus(): retries the same in-memory UUID and restores resumability when the server confirms it is processing', async () => {
    WhatsappChannel.fetchBloomwireOnboardingAttempt
      .mockRejectedValueOnce({ response: { status: 404 } })
      .mockResolvedValueOnce({
        data: { attempt_id: 'ATT-GONE', status: 'processing' },
      });
    window.localStorage.setItem(`${ATTEMPT_STORAGE_PREFIX}:7`, 'ATT-GONE');
    const flow = build();
    flow.resume();
    await flush();

    await flow.checkStatus();

    expect(
      WhatsappChannel.fetchBloomwireOnboardingAttempt
    ).toHaveBeenNthCalledWith(2, 'ATT-GONE');
    expect(flow.state.value).toBe(ONBOARDING_STATES.PROCESSING);
    expect(window.localStorage.getItem(`${ATTEMPT_STORAGE_PREFIX}:7`)).toBe(
      'ATT-GONE'
    );
    flow.cancel();
  });

  // Requirement #4: an in-flight attempt stays visible and reaches its final state while polling keeps returning
  // 200 (the backend keeps show available through an emergency rollback — proven server-side). The poller never
  // switches paths or drops to expired on a legitimate 200 sequence.
  it('keeps an in-flight attempt visible and drives it to its final (completed) state across polls', async () => {
    WhatsappChannel.fetchBloomwireOnboardingAttempt
      .mockResolvedValueOnce({
        data: { attempt_id: 'ATT-1', status: 'processing' },
      })
      .mockResolvedValue({
        data: { attempt_id: 'ATT-1', status: 'completed', channel_id: 42 },
      });
    const flow = build({ pollIntervalMs: 5, longerThanUsualMs: 100000 });
    await flow.start();
    await flush();
    expect(flow.state.value).toBe(ONBOARDING_STATES.PROCESSING); // still visible mid-flight
    await new Promise(resolve => {
      setTimeout(resolve, 30);
    });
    expect(flow.state.value).toBe(ONBOARDING_STATES.COMPLETED); // reaches its final state
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

  it('ignores an in-flight poll response that resolves after cancellation', async () => {
    let resolvePoll;
    WhatsappChannel.fetchBloomwireOnboardingAttempt.mockReturnValue(
      new Promise(resolve => {
        resolvePoll = resolve;
      })
    );
    window.localStorage.setItem(`${ATTEMPT_STORAGE_PREFIX}:7`, 'ATT-STALE');
    const flow = build();
    flow.resume();
    await flush();

    flow.cancel();
    resolvePoll({
      data: { attempt_id: 'ATT-STALE', status: 'completed', channel_id: 42 },
    });
    await flush();

    expect(flow.state.value).toBe(ONBOARDING_STATES.CANCELLED);
    expect(flow.attempt.value).toBeNull();
    expect(flow.attemptId.value).toBeNull();
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
