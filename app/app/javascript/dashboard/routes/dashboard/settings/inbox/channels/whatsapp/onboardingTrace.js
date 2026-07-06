import WhatsappChannelApi from 'dashboard/api/channel/whatsappChannel';

// The complete, closed set of managed-WhatsApp (Coexistence) onboarding trace events. Anything outside this
// list is dropped client-side (defence in depth; the server also rejects unknown events).
export const ONBOARDING_TRACE_EVENTS = [
  'onboarding_started',
  'sdk_initialization_started',
  'sdk_initialization_succeeded',
  'sdk_initialization_failed',
  'meta_popup_opened',
  'auth_callback_received',
  'auth_callback_cancelled',
  'auth_callback_failed',
  'business_message_received',
  'business_message_rejected',
  'first_signal_received',
  'both_signals_received',
  'signal_completion_timeout',
  'overall_signup_timeout',
  'create_request_started',
  'create_request_succeeded',
  'create_request_failed',
  'create_request_timeout',
  'frontend_success_transition',
  'frontend_error_transition',
  'attempt_cancelled',
  'attempt_finished',
];

const randomAttemptId = () => {
  try {
    if (typeof crypto !== 'undefined' && crypto.randomUUID)
      return crypto.randomUUID();
  } catch (_) {
    // fall through to the non-crypto fallback
  }
  return `att-${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 10)}`;
};

// A short, non-sensitive reference the user can quote to support (first segment of the opaque attempt id).
export const shortAttemptRef = attemptId => String(attemptId || '').slice(0, 8);

// Creates a tracer bound to one onboarding attempt. `trace(event, meta)` fires an allow-listed, sanitized event
// to the account-scoped admin endpoint. It is strictly fire-and-forget: it NEVER throws and NEVER rejects, so a
// tracing/network failure can never break the onboarding flow. Only non-sensitive scalars are ever sent.
export function createOnboardingTracer({ attemptId = randomAttemptId() } = {}) {
  const startedAt = Date.now();

  const trace = (event, meta = {}) => {
    // Client-side allow-list: silently ignore anything not in the closed set.
    if (!ONBOARDING_TRACE_EVENTS.includes(event)) return undefined;

    const payload = {
      onboarding_attempt_id: attemptId,
      event,
      result: meta.result,
      elapsed_ms:
        meta.elapsedMs != null ? meta.elapsedMs : Date.now() - startedAt,
      http_status: meta.httpStatus,
      error_code: meta.errorCode,
    };
    Object.keys(payload).forEach(key => {
      if (payload[key] === undefined || payload[key] === null)
        delete payload[key];
    });

    try {
      const req = WhatsappChannelApi.sendOnboardingTrace(payload);
      if (req && typeof req.catch === 'function') req.catch(() => {});
    } catch (_) {
      // never throw
    }
    return payload;
  };

  return { attemptId, shortRef: shortAttemptRef(attemptId), trace };
}

// A tracer that records nothing — used by the non-managed (Standard/native) embedded-signup callers so they are
// completely unaffected by the Coexistence onboarding trace (no attempt id, no network calls).
export function createNoopTracer() {
  return { attemptId: undefined, shortRef: '', trace: () => undefined };
}
