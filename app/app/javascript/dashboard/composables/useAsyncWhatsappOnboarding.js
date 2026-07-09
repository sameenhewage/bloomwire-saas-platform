import { ref } from 'vue';
import WhatsappChannel from 'dashboard/api/channel/whatsappChannel';
import { useWhatsappEmbeddedSignup } from './useWhatsappEmbeddedSignup';

// ADR-0010 v3 (async managed WhatsApp onboarding, frontend). Drives: open a server-side attempt -> Meta popup ->
// submit the code -> POLL the attempt status until terminal. There is NO 180s client watchdog around the popup:
// the attempt exists server-side and is polled, so the flow relies on Meta's own SDK signals plus the server-side
// attempt TTL. The in-flight attempt id is persisted per-account so a refresh/nav resumes polling, and is cleared
// on any terminal outcome. Cancel/Restart are first-class. No secret is ever handled by the browser.
export const POLL_INTERVAL_MS = 3000;
export const LONGER_THAN_USUAL_MS = 30000;
export const ATTEMPT_STORAGE_PREFIX = 'bloomwire_wa_onboarding_attempt';

export const ONBOARDING_STATES = Object.freeze({
  IDLE: 'idle',
  CREATING: 'creating',
  AWAITING_META: 'awaiting_meta',
  SUBMITTING: 'submitting',
  PROCESSING: 'processing',
  COMPLETED: 'completed',
  ACTION_REQUIRED: 'action_required',
  EXPIRED: 'expired',
  FAILED: 'failed',
  CANCELLED: 'cancelled',
});

const TERMINAL_STATES = [
  ONBOARDING_STATES.COMPLETED,
  ONBOARDING_STATES.ACTION_REQUIRED,
  ONBOARDING_STATES.EXPIRED,
  ONBOARDING_STATES.FAILED,
  ONBOARDING_STATES.CANCELLED,
];

// Server attempt status -> UI state. Any in-progress status collapses to PROCESSING for the poller.
const STATUS_TO_STATE = {
  completed: ONBOARDING_STATES.COMPLETED,
  action_required: ONBOARDING_STATES.ACTION_REQUIRED,
  expired: ONBOARDING_STATES.EXPIRED,
  failed: ONBOARDING_STATES.FAILED,
  cancelled: ONBOARDING_STATES.CANCELLED,
};

export function useAsyncWhatsappOnboarding({
  accountId,
  pollIntervalMs = POLL_INTERVAL_MS,
  longerThanUsualMs = LONGER_THAN_USUAL_MS,
} = {}) {
  const state = ref(ONBOARDING_STATES.IDLE);
  const attempt = ref(null);
  const attemptId = ref(null);
  const errorCode = ref(null);
  const takingLongerThanUsual = ref(false);
  const { runEmbeddedSignup, cancel: cancelPopup } =
    useWhatsappEmbeddedSignup();

  let pollTimer = null;
  let longerTimer = null;

  const storageKey = () =>
    `${ATTEMPT_STORAGE_PREFIX}:${accountId ?? 'unknown'}`;
  const readStored = () => {
    try {
      return window.localStorage?.getItem(storageKey());
    } catch {
      return null;
    }
  };
  const writeStored = id => {
    try {
      window.localStorage?.setItem(storageKey(), id);
    } catch {
      // storage unavailable (private mode): resume-on-reload degrades, the flow still works in-session.
    }
  };
  const clearStored = () => {
    try {
      window.localStorage?.removeItem(storageKey());
    } catch {
      // ignore
    }
  };

  const clearTimers = () => {
    if (pollTimer) clearTimeout(pollTimer);
    if (longerTimer) clearTimeout(longerTimer);
    pollTimer = null;
    longerTimer = null;
  };

  const isTerminal = () => TERMINAL_STATES.includes(state.value);

  const applyDto = dto => {
    attempt.value = dto;
    errorCode.value = dto?.error_code ?? null;
    state.value = STATUS_TO_STATE[dto?.status] || ONBOARDING_STATES.PROCESSING;
    if (isTerminal()) {
      clearTimers();
      clearStored();
    }
  };

  const poll = async () => {
    try {
      const { data } = await WhatsappChannel.fetchBloomwireOnboardingAttempt(
        attemptId.value
      );
      applyDto(data);
    } catch (error) {
      // A 404 means the attempt is gone for this account (swept/foreign) — stop and surface expired.
      if (error?.response?.status === 404) {
        clearTimers();
        clearStored();
        state.value = ONBOARDING_STATES.EXPIRED;
        return;
      }
      // Transient error: keep polling (the backend is resumable).
    }
    if (!isTerminal()) {
      pollTimer = setTimeout(poll, pollIntervalMs);
    }
  };

  const beginPolling = () => {
    clearTimers();
    state.value = ONBOARDING_STATES.PROCESSING;
    takingLongerThanUsual.value = false;
    longerTimer = setTimeout(() => {
      takingLongerThanUsual.value = true;
    }, longerThanUsualMs);
    poll();
  };

  const cancel = () => {
    cancelPopup();
    clearTimers();
    clearStored();
    attemptId.value = null;
    attempt.value = null;
    takingLongerThanUsual.value = false;
    state.value = ONBOARDING_STATES.CANCELLED;
  };

  const start = async () => {
    clearTimers();
    state.value = ONBOARDING_STATES.CREATING;
    const { data: created } =
      await WhatsappChannel.createBloomwireOnboardingAttempt();
    attemptId.value = created.attempt_id;
    attempt.value = created;
    writeStored(attemptId.value);

    state.value = ONBOARDING_STATES.AWAITING_META;
    // overallTimeoutMs: null DISABLES the 180s popup watchdog — rely on SDK signals + the server-side TTL.
    const credentials = await runEmbeddedSignup({ overallTimeoutMs: null });
    if (!credentials) {
      cancel(); // user dismissed the Meta popup
      return null;
    }

    state.value = ONBOARDING_STATES.SUBMITTING;
    await WhatsappChannel.submitBloomwireOnboardingAttempt(
      attemptId.value,
      credentials
    );
    beginPolling();
    return attemptId.value;
  };

  // On mount/reload: resume polling a persisted, still-in-flight attempt for THIS account. Returns false when none.
  const resume = () => {
    const stored = readStored();
    if (!stored) return false;
    attemptId.value = stored;
    beginPolling();
    return true;
  };

  const restart = () => {
    cancel();
    return start();
  };

  return {
    state,
    attempt,
    attemptId,
    errorCode,
    takingLongerThanUsual,
    start,
    resume,
    cancel,
    restart,
    ONBOARDING_STATES,
  };
}
