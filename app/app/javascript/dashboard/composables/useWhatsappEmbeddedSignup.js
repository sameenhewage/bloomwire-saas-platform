import { ref } from 'vue';
import {
  setupFacebookSdk,
  initWhatsAppEmbeddedSignup,
  createMessageHandler,
  isValidBusinessData,
} from 'dashboard/routes/dashboard/settings/inbox/channels/whatsapp/utils';
import { createNoopTracer } from 'dashboard/routes/dashboard/settings/inbox/channels/whatsapp/onboardingTrace';

// How long to wait for the SECOND Meta signal once the FIRST has arrived (auth code via FB.login + business
// data via postMessage are emitted together at popup completion, so the second should follow within seconds).
export const SIGNUP_COMPLETION_TIMEOUT_MS = 60000;

// OVERALL watchdog, armed the moment the signup launches — BEFORE any signal. This is the guarantee the
// second-signal timer cannot give: it bounds the zero-signal path and the never-settling SDK/FB.login promise
// (the classes where NO signal ever arrives to arm the second-signal timer). Long enough for a real customer to
// scan the QR and finish the Meta popup, but the UI can never wait forever. Overridable/config-driven for tests.
export const OVERALL_SIGNUP_TIMEOUT_MS = 180000;

// Explicit finite states for the signal-acquisition phase (the caller owns creating_inbox/succeeded/failed).
export const SIGNUP_STATES = Object.freeze({
  IDLE: 'idle',
  LAUNCHING: 'launching',
  WAITING_FOR_META: 'waiting_for_meta',
  WAITING_FOR_SECOND_SIGNAL: 'waiting_for_second_signal',
});

// Drives Meta's WhatsApp embedded-signup popup (Facebook JS SDK). FB.login() resolves an auth `code` while the
// WABA identifiers arrive separately over a postMessage event — order isn't guaranteed, so we hold both and
// resolve once both are present. Every asynchronous stage is bounded (overall watchdog + second-signal timer)
// so the run ALWAYS settles: no path can leave the UI on an infinite "Registering..." spinner. Resolves `null`
// on cancel; rejects on SDK/signup error, one-signal timeout, or the overall watchdog. Timers + the window
// listener are scoped to a single run and torn down on every settle, so this is safe to call without lifecycle
// wiring; `cancel()` is additionally provided for component unmount / route change.
export function useWhatsappEmbeddedSignup() {
  const isAuthenticating = ref(false);
  const state = ref(SIGNUP_STATES.IDLE);
  // Set to the current run's cancel-cleanup while a run is in flight; cleared on settle. Used by `cancel()`.
  let cancelActiveRun = null;

  // The tracer is supplied PER RUN (not at construction) so the caller can mint a fresh attempt id for every
  // attempt, and so non-traced callers (Standard/native) simply pass nothing → a no-op tracer (no attempt id,
  // no trace calls, no Coexistence endpoint hit).
  const runEmbeddedSignup = ({
    tracer,
    timeoutMs = SIGNUP_COMPLETION_TIMEOUT_MS,
    overallTimeoutMs = OVERALL_SIGNUP_TIMEOUT_MS,
  } = {}) => {
    const activeTracer = tracer || createNoopTracer();
    // In-flight guard: a second call (e.g. double click) never starts a parallel attempt.
    if (isAuthenticating.value) return Promise.resolve(null);
    isAuthenticating.value = true;
    state.value = SIGNUP_STATES.LAUNCHING;
    activeTracer.trace('onboarding_started', { result: 'started' });

    return new Promise((resolve, reject) => {
      let authCode = null;
      let businessData = null;
      let settled = false;
      let firstSignalSeen = false;
      let messageHandler;
      let completionTimer = null;
      let overallTimer = null;

      // Guaranteed teardown — clears BOTH timers, the window listener and all pending/loading state.
      const cleanup = () => {
        if (completionTimer) clearTimeout(completionTimer);
        if (overallTimer) clearTimeout(overallTimer);
        completionTimer = null;
        overallTimer = null;
        window.removeEventListener('message', messageHandler);
        isAuthenticating.value = false;
        state.value = SIGNUP_STATES.IDLE;
        cancelActiveRun = null;
      };

      const settle = (fn, value) => {
        if (settled) return;
        settled = true;
        cleanup();
        fn(value);
      };

      // cancel()/unmount/route-change → trace + resolve as a (null) cancellation after full teardown.
      cancelActiveRun = () => {
        activeTracer.trace('attempt_cancelled', { result: 'cancelled' });
        settle(resolve, null);
      };

      const markFirstSignal = () => {
        if (firstSignalSeen) return;
        firstSignalSeen = true;
        state.value = SIGNUP_STATES.WAITING_FOR_SECOND_SIGNAL;
        activeTracer.trace('first_signal_received', { result: 'pending' });
      };

      const resolveIfReady = () => {
        if (authCode && businessData) {
          activeTracer.trace('both_signals_received', { result: 'ok' });
          settle(resolve, {
            code: authCode,
            business_id: businessData.business_id,
            waba_id: businessData.waba_id,
            phone_number_id: businessData.phone_number_id || '',
          });
          return;
        }
        if (authCode || businessData) {
          markFirstSignal();
          if (!completionTimer) {
            completionTimer = setTimeout(() => {
              activeTracer.trace('signal_completion_timeout', {
                result: 'timeout',
              });
              settle(reject, new Error('Embedded signup timed out'));
            }, timeoutMs);
          }
        }
      };

      messageHandler = createMessageHandler(data => {
        if (
          data.event === 'FINISH' ||
          data.event === 'FINISH_WHATSAPP_BUSINESS_APP_ONBOARDING'
        ) {
          if (!isValidBusinessData(data.data)) {
            activeTracer.trace('business_message_rejected', {
              result: 'rejected',
              errorCode: 'invalid_business_data',
            });
            settle(reject, new Error('Invalid business data'));
            return;
          }
          activeTracer.trace('business_message_received', { result: 'ok' });
          businessData = data.data;
          resolveIfReady();
        } else if (data.event === 'CANCEL') {
          activeTracer.trace('auth_callback_cancelled', {
            result: 'cancelled',
          });
          settle(resolve, null);
        } else if (data.event === 'error') {
          activeTracer.trace('auth_callback_failed', {
            result: 'error',
            errorCode: 'meta_signup_error',
          });
          settle(reject, new Error(data.error_message || 'Signup error'));
        }
      });

      window.addEventListener('message', messageHandler);

      // Overall watchdog FIRST, so even a synchronous never-settling SDK path is bounded.
      overallTimer = setTimeout(() => {
        activeTracer.trace('overall_signup_timeout', { result: 'timeout' });
        settle(reject, new Error('Embedded signup overall timeout'));
      }, overallTimeoutMs);

      (async () => {
        try {
          activeTracer.trace('sdk_initialization_started', {
            result: 'started',
          });
          await setupFacebookSdk(
            window.chatwootConfig?.whatsappAppId,
            window.chatwootConfig?.whatsappApiVersion
          );
          if (settled) return;
          activeTracer.trace('sdk_initialization_succeeded', { result: 'ok' });
        } catch (error) {
          activeTracer.trace('sdk_initialization_failed', {
            result: 'failure',
            errorCode: 'sdk_error',
          });
          settle(reject, error);
          return;
        }

        state.value = SIGNUP_STATES.WAITING_FOR_META;
        activeTracer.trace('meta_popup_opened', { result: 'ok' });

        try {
          authCode = await initWhatsAppEmbeddedSignup(
            window.chatwootConfig?.whatsappConfigurationId
          );
          if (settled) return;
          activeTracer.trace('auth_callback_received', { result: 'ok' });
          resolveIfReady();
        } catch (error) {
          // FB.login() rejects with 'Login cancelled' when the user dismisses the popup.
          if (error.message === 'Login cancelled') {
            activeTracer.trace('auth_callback_cancelled', {
              result: 'cancelled',
            });
            settle(resolve, null);
          } else {
            activeTracer.trace('auth_callback_failed', {
              result: 'error',
              errorCode: 'fb_login_error',
            });
            settle(reject, error);
          }
        }
      })();
    });
  };

  // Guaranteed cleanup for component unmount / route change: if a run is in flight, settle it as a cancellation
  // and tear down timers + listeners + pending state. A no-op when idle.
  const cancel = () => {
    if (cancelActiveRun) cancelActiveRun();
  };

  return {
    isAuthenticating,
    state,
    runEmbeddedSignup,
    cancel,
  };
}
