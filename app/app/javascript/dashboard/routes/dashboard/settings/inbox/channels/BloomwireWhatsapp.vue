<script setup>
// Phase 17C.3: managed self-serve customer WhatsApp connection wizard (Bloomwire). Rendered by ChannelFactory in
// place of the native WhatsApp setup when `canSelfServeManagedWhatsapp` is true. It opens on a connection-choice
// screen with two options:
//   1. Connect Existing WhatsApp Business App (Coexistence) — Phase 17D.3: enabled. Reuses the same Meta Embedded
//      Signup + credential-free form as Standard, but posts to the dedicated coexistence endpoint (17D.1).
//   2. Register New Number (Standard) — the WhatsApp Cloud API number-registration flow (available now).
// The Standard flow is ONLY number registration — there is deliberately NO "Add Agents" step (Chatwoot's existing
// inbox-agent management owns that). It asks the customer for NO credentials (no App Secret / Verify Token /
// Webhook URL / API token / provider_config); it launches Meta Embedded Signup, sends only the non-secret signup
// credentials to the dedicated Bloomwire endpoint, and renders a safe DTO on success. The registered number shown
// is the backend/Meta source of truth (not the typed number). Failures show a single sanitized generic message.
import { ref, computed, onBeforeUnmount } from 'vue';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import { onBeforeRouteLeave } from 'vue-router';
import { useWhatsappEmbeddedSignup } from 'dashboard/composables/useWhatsappEmbeddedSignup';
import { useBloomwireWhatsappOnboarding } from 'dashboard/composables/useBloomwireWhatsappOnboarding';
import { useStoreGetters } from 'dashboard/composables/store';
import { getStoredAsyncWhatsappOnboardingAttemptId } from 'dashboard/composables/useAsyncWhatsappOnboarding';
import {
  createOnboardingTracer,
  createNoopTracer,
} from 'dashboard/routes/dashboard/settings/inbox/channels/whatsapp/onboardingTrace';
import Icon from 'next/icon/Icon.vue';
import NextButton from 'next/button/Button.vue';
import LoadingState from 'dashboard/components/widgets/LoadingState.vue';
import BloomwireWhatsappAsync from './BloomwireWhatsappAsync.vue';

// The backend create must never leave the UI pending forever (the "POST started and stayed pending" class).
// Bound it and fail closed with a safe recoverable error.
const CREATE_REQUEST_TIMEOUT_MS = 45000;
// The advisory duplicate preflight is a quick check — bound it tightly so a never-settling request can never hang
// the attempt (it fails OPEN on timeout, so the authoritative post-Meta guard still decides).
const PREFLIGHT_TIMEOUT_MS = 8000;

const store = useStore();
const { t } = useI18n();
const getters = useStoreGetters();
const accountId = getters.getCurrentAccountId?.value;
const {
  isAuthenticating,
  runEmbeddedSignup,
  cancel: cancelEmbeddedSignup,
} = useWhatsappEmbeddedSignup();
const { usesAsyncStandard: useAsyncStandardOnboarding } =
  useBloomwireWhatsappOnboarding();
// Short, non-sensitive support reference for the CURRENT attempt (set per attempt; changes on every retry).
const attemptRef = ref('');

// Lifecycle-scoped create-request control (Finding 3): a cancellable timer + an AbortController + a per-attempt
// sequence + a left-flow flag, so an in-flight create is aborted and any late response is ignored (no UI change,
// no navigation, no trace, no store refresh) on success/failure/retry/unmount/route change.
let createTimer = null;
let createAbort = null;
let attemptSeq = 0;
let leftFlow = false;
// Same lifecycle discipline for the advisory preflight request: a bounded timer + an AbortController, aborted on
// unmount/route change and cleared on settle, so it can never hang the attempt or open Meta after the flow left.
let preflightTimer = null;
let preflightAbort = null;
// Wizard-owned "an attempt is in flight" flag. Set the instant an attempt starts (before ANY attempt-state
// mutation) and cleared only on a terminal state, so a duplicate submit while signup OR create is active is a
// pure no-op — the first attempt stays authoritative and is never superseded/aborted by a second click.
let attemptActive = false;

const clearCreateTimer = () => {
  if (createTimer) {
    clearTimeout(createTimer);
    createTimer = null;
  }
};
const abortCreate = () => {
  if (createAbort) {
    try {
      createAbort.abort();
    } catch (_) {
      // AbortController is unavailable in some very old runtimes — safe to ignore.
    }
    createAbort = null;
  }
};
const clearPreflightTimer = () => {
  if (preflightTimer) {
    clearTimeout(preflightTimer);
    preflightTimer = null;
  }
};
const abortPreflight = () => {
  if (preflightAbort) {
    try {
      preflightAbort.abort();
    } catch (_) {
      // AbortController unavailable in some very old runtimes — safe to ignore.
    }
    preflightAbort = null;
  }
};
// True when this attempt no longer owns the flow — the component left, or a newer attempt superseded it.
const isStale = seq => leftFlow || seq !== attemptSeq;

// A persisted async Standard attempt takes precedence over the emergency switch so an in-flight attempt remains
// visible and pollable after a rollback. With no in-flight attempt, every owner starts at the two-mode chooser.
const mode = ref(
  getStoredAsyncWhatsappOnboardingAttemptId(accountId)
    ? 'async_standard'
    : 'choose'
);
// 'standard' = Register New Number (Cloud API); 'coexistence' = Connect Existing WhatsApp Business App (17D.3).
// Both reuse the same credential-free form + Meta Embedded Signup; only the target endpoint differs.
const flow = ref('standard');
// Set true ONLY after an explicit provider-migration confirmation that routes to the async Standard child, so it
// begins the SAME async Standard lifecycle once on mount. Never set for the normal "Register New Number" entry.
const autoStartAsync = ref(false);
const inboxName = ref('');
const expectedNumber = ref('');
const isProcessing = ref(false);
// True only while the advisory duplicate preflight request is in flight (drives the "checking" state + disables
// the submit action).
const isCheckingAvailability = ref(false);
const errorMessage = ref('');
const result = ref(null);

// Coexistence prerequisites shown on the disabled card (static i18n keys — no dynamic keys).
const coexistenceRequirements = computed(() => [
  t(
    'INBOX_MGMT.ADD.WHATSAPP.BLOOMWIRE_MANAGED.CHOOSE.COEXISTENCE.REQUIREMENTS.APP_VERSION'
  ),
  t(
    'INBOX_MGMT.ADD.WHATSAPP.BLOOMWIRE_MANAGED.CHOOSE.COEXISTENCE.REQUIREMENTS.APP_AGE'
  ),
  t(
    'INBOX_MGMT.ADD.WHATSAPP.BLOOMWIRE_MANAGED.CHOOSE.COEXISTENCE.REQUIREMENTS.COUNTRY'
  ),
  t(
    'INBOX_MGMT.ADD.WHATSAPP.BLOOMWIRE_MANAGED.CHOOSE.COEXISTENCE.REQUIREMENTS.META_BUSINESS'
  ),
  t(
    'INBOX_MGMT.ADD.WHATSAPP.BLOOMWIRE_MANAGED.CHOOSE.COEXISTENCE.REQUIREMENTS.QR'
  ),
  t(
    'INBOX_MGMT.ADD.WHATSAPP.BLOOMWIRE_MANAGED.CHOOSE.COEXISTENCE.REQUIREMENTS.HISTORY'
  ),
  t(
    'INBOX_MGMT.ADD.WHATSAPP.BLOOMWIRE_MANAGED.CHOOSE.COEXISTENCE.REQUIREMENTS.DEVICES'
  ),
  t(
    'INBOX_MGMT.ADD.WHATSAPP.BLOOMWIRE_MANAGED.CHOOSE.COEXISTENCE.REQUIREMENTS.BOTH'
  ),
]);

const startRegister = () => {
  errorMessage.value = '';
  autoStartAsync.value = false;
  flow.value = 'standard';
  mode.value = useAsyncStandardOnboarding.value ? 'async_standard' : 'register';
};

// Phase 17D.3: enter the same credential-free form for the Coexistence flow (existing WhatsApp Business App).
const startCoexistence = () => {
  errorMessage.value = '';
  autoStartAsync.value = false;
  flow.value = 'coexistence';
  mode.value = 'register';
};

// Provider migration ("Move Existing Cloud API Number") — the recommended path for a number already on the Cloud
// API with another provider. Show an EXPLICIT confirmation first; no Meta or store call happens until the owner
// confirms. Migration reuses the EXACT Standard lifecycle (there is no separate endpoint, table, or Meta flag).
const startMigration = () => {
  errorMessage.value = '';
  autoStartAsync.value = false;
  mode.value = 'migration_confirm';
};

const backToChoose = () => {
  errorMessage.value = '';
  autoStartAsync.value = false;
  mode.value = 'choose';
};

const useSyncStandardFallback = () => {
  errorMessage.value = '';
  autoStartAsync.value = false;
  flow.value = 'standard';
  mode.value = 'register';
};

const isCoexistence = computed(() => flow.value === 'coexistence');
// Flow-specific copy for the shared form: Coexistence makes it clear this connects an EXISTING number. Static
// i18n keys only (no dynamic keys) to satisfy @intlify/vue-i18n lint.
const formTitle = computed(() =>
  isCoexistence.value
    ? t(
        'INBOX_MGMT.ADD.WHATSAPP.BLOOMWIRE_MANAGED.CHOOSE.COEXISTENCE.FORM_TITLE'
      )
    : t('INBOX_MGMT.ADD.WHATSAPP.BLOOMWIRE_MANAGED.TITLE')
);
const formDesc = computed(() =>
  isCoexistence.value
    ? t(
        'INBOX_MGMT.ADD.WHATSAPP.BLOOMWIRE_MANAGED.CHOOSE.COEXISTENCE.FORM_DESC'
      )
    : t('INBOX_MGMT.ADD.WHATSAPP.BLOOMWIRE_MANAGED.DESC')
);
const formButtonLabel = computed(() =>
  isCoexistence.value
    ? t(
        'INBOX_MGMT.ADD.WHATSAPP.BLOOMWIRE_MANAGED.CHOOSE.COEXISTENCE.CONNECT_BUTTON'
      )
    : t('INBOX_MGMT.ADD.WHATSAPP.BLOOMWIRE_MANAGED.REGISTER_BUTTON')
);

const showLoader = computed(() => isAuthenticating.value || isProcessing.value);
const isComplete = computed(() => Boolean(result.value?.inbox?.id));
const inboxId = computed(() => result.value?.inbox?.id);
const displayInboxName = computed(() => result.value?.inbox?.name || '');
// Source of truth = backend/Meta masked value, never the typed number.
const registeredNumber = computed(
  () =>
    result.value?.phone?.display_phone_number ||
    result.value?.phone?.channel_phone_number ||
    ''
);

// Phase 5 (resume): a completed inbox may still need ONE Meta step before it can SEND. When the backend DTO
// marks it action_required (outbound-messaging permission not yet granted to the connected system user), the
// completion screen shows an explicit "action required" panel with a Recheck permission action — NOT the Ready
// state, and NOT a "reconnect" instruction (reconnecting cannot resume an already-connected number).
const isActionRequired = computed(
  () =>
    Boolean(result.value?.action_required) ||
    result.value?.setup?.status === 'action_required'
);
const setupId = computed(() => result.value?.setup?.id);
// BLOCKER 4: the Action-Required copy MUST differ by the sanitized reason. A verified-missing task shows the Meta
// grant step; an unverifiable / activation-incomplete state shows a neutral "couldn't verify, retry" and must NOT
// claim the permission is missing.
const actionReasonKey = computed(() => {
  switch (result.value?.action_required?.reason) {
    case 'outbound_messaging_permission_unverifiable':
      return 'UNVERIFIABLE';
    case 'outbound_messaging_activation_incomplete':
      return 'ACTIVATION_INCOMPLETE';
    default:
      return 'PERMISSION_REQUIRED';
  }
});
const showGrantStep = computed(
  () => actionReasonKey.value === 'PERMISSION_REQUIRED'
);
// 'idle' before any recheck; 'pending' while re-verifying; 'still_pending' when the task is still not granted;
// 'failed' when the recheck itself could not reach Meta. Drives the inline loading/success/failure states.
const recheckState = ref('idle');
const isRechecking = computed(() => recheckState.value === 'pending');

// Re-verify outbound capability for the Action-Required setup. On success the backend promotes the SAME setup to
// ready and returns ready:true → the panel flips to the Ready state (no new inbox, no reconnect, no secrets).
// A still-missing task or a verification failure fails closed to a safe, retryable inline message.
const recheckPermission = async () => {
  if (!setupId.value || recheckState.value === 'pending') return;
  recheckState.value = 'pending';
  try {
    const dto = await store.dispatch(
      'inboxes/recheckBloomwireWhatsAppCapability',
      { setupId: setupId.value }
    );
    // Set action_required explicitly (the ready DTO omits it) so a promotion clears the stale panel.
    result.value = {
      ...result.value,
      ...dto,
      action_required: dto?.action_required,
    };
    recheckState.value = dto?.ready ? 'idle' : 'still_pending';
  } catch (_) {
    recheckState.value = 'failed';
  }
};

// Best-effort: honor a customer-entered inbox name via the existing inbox update API (the inbox already exists
// with its Meta-derived name; a rename failure never blocks the completed registration).
const maybeRenameInbox = async () => {
  const name = inboxName.value.trim();
  if (!name || !result.value?.inbox?.id) return;
  try {
    await store.dispatch('inboxes/updateInbox', {
      id: result.value.inbox.id,
      formData: false,
      name,
    });
    result.value = {
      ...result.value,
      inbox: { ...result.value.inbox, name },
    };
  } catch (_) {
    // non-critical: keep the Meta-derived inbox name
  }
};

// Advisory duplicate-number preflight. Returns 'already_connected' | 'available'. BOUNDED (a short timeout aborts
// the request) and ABORTABLE (unmount/route change aborts it). Fails OPEN ('available') on a blank number, a
// timeout, an abort, a rate-limit (429), or ANY error — the authoritative post-Meta guard stays the source of
// truth. It never throws, so `register()` always makes progress to a terminal state.
const checkPhoneAvailability = async number => {
  const trimmed = (number || '').trim();
  if (!trimmed) return 'available';

  clearPreflightTimer();
  abortPreflight();
  preflightAbort =
    typeof AbortController !== 'undefined' ? new AbortController() : null;
  preflightTimer = setTimeout(abortPreflight, PREFLIGHT_TIMEOUT_MS);

  try {
    const data = await store.dispatch(
      'inboxes/checkBloomwireWhatsAppPhoneAvailability',
      { phoneNumber: trimmed, signal: preflightAbort?.signal }
    );
    return data?.status === 'already_connected'
      ? 'already_connected'
      : 'available';
  } catch (_) {
    return 'available';
  } finally {
    clearPreflightTimer();
  }
};

// Maps a known, SAFE backend error code (error.response.data.code) to a specific message. Anything else
// (meta_error / unknown / 5xx / timeout / no code) falls back to the generic safe message. Never surfaces a raw
// backend or Meta exception string. Shared by the Standard and Coexistence create flows.
const createErrorMessage = error => {
  const code = error?.response?.data?.code;
  if (code === 'phone_number_taken') {
    return t(
      'INBOX_MGMT.ADD.WHATSAPP.BLOOMWIRE_MANAGED.ERRORS.PHONE_NUMBER_TAKEN'
    );
  }
  if (code === 'phone_number_id_conflict') {
    return t(
      'INBOX_MGMT.ADD.WHATSAPP.BLOOMWIRE_MANAGED.ERRORS.PHONE_NUMBER_ID_CONFLICT'
    );
  }
  if (code === 'invalid_phone_number') {
    return t(
      'INBOX_MGMT.ADD.WHATSAPP.BLOOMWIRE_MANAGED.ERRORS.INVALID_PHONE_NUMBER'
    );
  }
  return t('INBOX_MGMT.ADD.WHATSAPP.BLOOMWIRE_MANAGED.ERROR');
};

const register = async () => {
  // Wizard-level active-attempt guard — MUST run before any attempt-state mutation (tracer / attempt id /
  // support reference / attemptSeq / AbortController / timer). While a signup OR create is already in flight, a
  // second submit is a pure no-op: the first attempt stays authoritative until it reaches a terminal state
  // (success / failure / cancel / timeout / route-leave / unmount). Retry after a terminal state is allowed and
  // mints a fresh attempt id.
  if (attemptActive) return;
  attemptActive = true;
  errorMessage.value = '';

  // Establish the per-attempt sequence + reset ALL lifecycle timers/aborts BEFORE the first await, so the
  // leftFlow/stale protection covers the advisory preflight too — a late preflight response after unmount / route
  // change can never continue register() or open Meta.
  attemptSeq += 1;
  const seq = attemptSeq;
  clearCreateTimer();
  abortCreate();
  clearPreflightTimer();
  abortPreflight();

  try {
    // Advisory, BOUNDED, ABORTABLE duplicate preflight — never open the Meta popup for a number already connected
    // in Bloomwire. Shows a visible "checking" state (disables the action). Fails OPEN on blank/timeout/abort/429/
    // error; the authoritative post-Meta guard is unchanged (Meta may confirm a different number). Standard + Coexistence.
    isCheckingAvailability.value = true;
    let availability;
    try {
      availability = await checkPhoneAvailability(expectedNumber.value);
    } finally {
      isCheckingAvailability.value = false;
    }
    // Stale / left-flow check IMMEDIATELY after the await, BEFORE creating a tracer or opening Meta.
    if (isStale(seq)) return;
    if (availability === 'already_connected') {
      errorMessage.value = t(
        'INBOX_MGMT.ADD.WHATSAPP.BLOOMWIRE_MANAGED.ERRORS.PHONE_NUMBER_TAKEN'
      );
      return;
    }

    // Fresh tracer + attempt id PER attempt (only after the preflight cleared). Coexistence traces; Standard/native
    // uses a no-op tracer (no attempt id, no browser trace, no Coexistence endpoint, never logged as mode=coexistence).
    const tracer = isCoexistence.value
      ? createOnboardingTracer()
      : createNoopTracer();
    attemptRef.value = tracer.shortRef;

    let credentials;
    try {
      // Pass the flow so Meta gets the right Embedded Signup featureType: Coexistence uses
      // 'whatsapp_business_app_onboarding'; Standard omits it so the number is provisioned for Cloud API
      // registration (WhatsWay parity) — otherwise the later /register returns Meta #100.
      credentials = await runEmbeddedSignup({
        tracer,
        coexistence: isCoexistence.value,
      });
    } catch (_) {
      if (isStale(seq)) return;
      // Signal-acquisition failure (SDK/one-signal/overall timeout) — the composable already traced the cause.
      tracer.trace('frontend_error_transition', {
        result: 'failure',
        errorCode: 'signal_failure',
      });
      tracer.trace('attempt_finished', { result: 'failure' });
      errorMessage.value = t('INBOX_MGMT.ADD.WHATSAPP.BLOOMWIRE_MANAGED.ERROR');
      return;
    }
    if (isStale(seq)) return;

    // Resolves null when the customer dismisses the Meta popup (or the run was cancelled).
    if (!credentials) {
      tracer.trace('attempt_finished', { result: 'cancelled' });
      errorMessage.value = t(
        'INBOX_MGMT.ADD.WHATSAPP.BLOOMWIRE_MANAGED.CANCELLED'
      );
      return;
    }

    isProcessing.value = true;
    const startedAt = Date.now();
    tracer.trace('create_request_started', { result: 'started' });

    // Lifecycle-scoped, cancellable create timeout + abort. The timer aborts the request; unmount/route abort it
    // too. A late response is ignored by the `isStale` guard so it can never mutate UI/store/trace after the fact.
    createAbort =
      typeof AbortController !== 'undefined' ? new AbortController() : null;
    let timedOut = false;
    clearCreateTimer();
    createTimer = setTimeout(() => {
      timedOut = true;
      abortCreate();
    }, CREATE_REQUEST_TIMEOUT_MS);

    const action = isCoexistence.value
      ? 'inboxes/createBloomwireWhatsAppCoexistenceEmbeddedSignup'
      : 'inboxes/createBloomwireWhatsAppEmbeddedSignup';
    // Only the non-secret Meta signup credentials are sent. Coexistence adds the opaque onboarding_attempt_id to
    // correlate the backend trace; Standard sends NO attempt id. The abort `signal` is stripped server-side.
    const payload = isCoexistence.value
      ? {
          ...credentials,
          onboarding_attempt_id: tracer.attemptId,
          signal: createAbort?.signal,
        }
      : { ...credentials, signal: createAbort?.signal };

    try {
      const dto = await store.dispatch(action, payload);
      if (isStale(seq)) return; // late/superseded → ignore (no UI/nav/trace/store side-effects)
      clearCreateTimer();
      result.value = dto;
      tracer.trace('create_request_succeeded', {
        result: 'success',
        httpStatus: 201,
        elapsedMs: Date.now() - startedAt,
      });
      await maybeRenameInbox();
      if (isStale(seq)) return;
      tracer.trace('frontend_success_transition', { result: 'success' });
      tracer.trace('attempt_finished', { result: 'success' });
    } catch (error) {
      if (isStale(seq)) return; // late/superseded → ignore
      clearCreateTimer();
      const httpStatus = error?.response?.status;
      tracer.trace(
        timedOut ? 'create_request_timeout' : 'create_request_failed',
        {
          result: timedOut ? 'timeout' : 'failure',
          httpStatus,
          errorCode: timedOut
            ? 'create_timeout'
            : `http_${httpStatus || 'error'}`,
          elapsedMs: Date.now() - startedAt,
        }
      );
      tracer.trace('frontend_error_transition', { result: 'failure' });
      tracer.trace('attempt_finished', { result: 'failure' });
      // Map a known safe backend code (phone_number_taken / phone_number_id_conflict / invalid_phone_number) to a
      // specific message; everything else (meta_error / unknown / 5xx / timeout) uses the generic safe message. A
      // raw server/Meta error string is never surfaced.
      errorMessage.value = createErrorMessage(error);
    } finally {
      if (!isStale(seq)) isProcessing.value = false;
    }
  } finally {
    // The attempt reached a terminal state on this (non-left, non-superseded) path → free the wizard so a manual
    // retry can start a fresh attempt. If the flow was left/superseded, `cleanupOnboarding` already cleared it.
    if (!isStale(seq)) attemptActive = false;
  }
};

// Explicit provider-migration confirmation → run the SAME Standard lifecycle (coexistence:false), NOT a separate
// migration flow. Async Standard (when enabled) hands off to the async child, which auto-starts once; otherwise the
// synchronous Standard `register()` runs directly. No migration endpoint/table/Meta flag is involved.
const confirmMigration = async () => {
  errorMessage.value = '';
  flow.value = 'standard';
  if (useAsyncStandardOnboarding.value) {
    autoStartAsync.value = true;
    mode.value = 'async_standard';
    return;
  }
  mode.value = 'register';
  await register();
};

// Guaranteed cleanup on unmount / route change: settle any in-flight signup run, abort the create request, clear
// its timer, mark the flow left (so any late response is ignored) and stop every loading flag, so
// listeners/timers/pending/create state can never leak past this component's lifecycle.
const cleanupOnboarding = () => {
  leftFlow = true;
  cancelEmbeddedSignup();
  clearCreateTimer();
  abortCreate();
  clearPreflightTimer();
  abortPreflight();
  isProcessing.value = false;
  isCheckingAvailability.value = false;
  attemptActive = false;
};
onBeforeUnmount(cleanupOnboarding);
onBeforeRouteLeave(() => {
  cleanupOnboarding();
});
</script>

<template>
  <div class="h-full">
    <LoadingState
      v-if="showLoader"
      :message="$t('INBOX_MGMT.ADD.WHATSAPP.BLOOMWIRE_MANAGED.PROCESSING')"
    />

    <!-- Action required: the number is connected to Meta but the inbox is NOT active yet (not subscribed for
         inbound, cannot send outbound). We show the reason-specific status + (for a verified-missing task) the
         exact safe Meta grant step + a Recheck action — never a "reconnect" instruction (reconnect cannot resume
         an already-connected number) and never a raw actor id / token / secret. -->
    <div
      v-else-if="isComplete && isActionRequired"
      data-testid="bloomwire-wa-action-required"
    >
      <div class="flex flex-col items-start mb-6 text-start">
        <div class="flex justify-start mb-6">
          <div
            class="flex size-11 items-center justify-center rounded-full bg-n-alpha-2"
          >
            <Icon
              icon="i-lucide-triangle-alert"
              class="text-n-amber-10 size-6"
            />
          </div>
        </div>
        <h3 class="mb-2 text-base font-medium text-n-slate-12">
          {{
            $t(
              'INBOX_MGMT.ADD.WHATSAPP.BLOOMWIRE_MANAGED.ACTION_REQUIRED.TITLE'
            )
          }}
        </h3>
        <p class="text-sm leading-6 text-n-slate-11">
          {{
            $t(
              'INBOX_MGMT.ADD.WHATSAPP.BLOOMWIRE_MANAGED.ACTION_REQUIRED.SUBTITLE'
            )
          }}
        </p>
      </div>

      <div
        v-if="showGrantStep"
        class="rounded-xl border border-n-weak p-4 mb-6"
      >
        <p class="mb-1 text-sm font-medium text-n-slate-12">
          {{
            $t(
              'INBOX_MGMT.ADD.WHATSAPP.BLOOMWIRE_MANAGED.ACTION_REQUIRED.STEP_TITLE'
            )
          }}
        </p>
        <p class="text-sm text-n-slate-11">
          {{
            $t(
              'INBOX_MGMT.ADD.WHATSAPP.BLOOMWIRE_MANAGED.ACTION_REQUIRED.STEP_DESC'
            )
          }}
        </p>
      </div>

      <p class="mb-3 text-sm text-n-slate-11" data-testid="bloomwire-wa-reason">
        <template v-if="actionReasonKey === 'UNVERIFIABLE'">
          {{
            $t(
              'INBOX_MGMT.ADD.WHATSAPP.BLOOMWIRE_MANAGED.ACTION_REQUIRED.REASON.UNVERIFIABLE'
            )
          }}
        </template>
        <template v-else-if="actionReasonKey === 'ACTIVATION_INCOMPLETE'">
          {{
            $t(
              'INBOX_MGMT.ADD.WHATSAPP.BLOOMWIRE_MANAGED.ACTION_REQUIRED.REASON.ACTIVATION_INCOMPLETE'
            )
          }}
        </template>
        <template v-else>
          {{
            $t(
              'INBOX_MGMT.ADD.WHATSAPP.BLOOMWIRE_MANAGED.ACTION_REQUIRED.REASON.PERMISSION_REQUIRED'
            )
          }}
        </template>
      </p>

      <p
        v-if="recheckState === 'still_pending'"
        data-testid="bloomwire-wa-recheck-pending"
        class="mb-3 text-sm text-n-amber-11"
      >
        {{
          $t(
            'INBOX_MGMT.ADD.WHATSAPP.BLOOMWIRE_MANAGED.ACTION_REQUIRED.STILL_PENDING'
          )
        }}
      </p>
      <p
        v-else-if="recheckState === 'failed'"
        data-testid="bloomwire-wa-recheck-failed"
        class="mb-3 text-sm text-n-ruby-11"
      >
        {{
          $t(
            'INBOX_MGMT.ADD.WHATSAPP.BLOOMWIRE_MANAGED.ACTION_REQUIRED.RECHECK_FAILED'
          )
        }}
      </p>

      <div class="flex gap-2">
        <NextButton
          solid
          teal
          data-testid="bloomwire-wa-recheck"
          :is-loading="isRechecking"
          :disabled="isRechecking"
          :label="
            $t(
              'INBOX_MGMT.ADD.WHATSAPP.BLOOMWIRE_MANAGED.ACTION_REQUIRED.RECHECK_BUTTON'
            )
          "
          @click="recheckPermission"
        />
        <router-link
          :to="{ name: 'settings_inbox_show', params: { inboxId } }"
          data-testid="bloomwire-wa-inbox-settings"
        >
          <NextButton
            outline
            slate
            :label="
              $t(
                'INBOX_MGMT.ADD.WHATSAPP.BLOOMWIRE_MANAGED.SUCCESS.INBOX_SETTINGS'
              )
            "
          />
        </router-link>
      </div>
    </div>

    <!-- Success: safe DTO only (ids/name/masked number/status) + open/settings. No agents step. -->
    <div v-else-if="isComplete" data-testid="bloomwire-wa-success">
      <div class="flex flex-col items-start mb-6 text-start">
        <div class="flex justify-start mb-6">
          <div
            class="flex size-11 items-center justify-center rounded-full bg-n-alpha-2"
          >
            <Icon icon="i-lucide-check" class="text-n-teal-10 size-6" />
          </div>
        </div>
        <h3 class="mb-2 text-base font-medium text-n-slate-12">
          {{ $t('INBOX_MGMT.ADD.WHATSAPP.BLOOMWIRE_MANAGED.SUCCESS.TITLE') }}
        </h3>
        <p class="text-sm leading-6 text-n-slate-11">
          {{ $t('INBOX_MGMT.ADD.WHATSAPP.BLOOMWIRE_MANAGED.SUCCESS.SUBTITLE') }}
        </p>
      </div>

      <dl class="flex flex-col gap-3 mb-6 text-sm">
        <div class="flex justify-between gap-4">
          <dt class="text-n-slate-11">
            {{
              $t(
                'INBOX_MGMT.ADD.WHATSAPP.BLOOMWIRE_MANAGED.SUCCESS.INBOX_LABEL'
              )
            }}
          </dt>
          <dd class="font-medium text-n-slate-12">{{ displayInboxName }}</dd>
        </div>
        <div v-if="registeredNumber" class="flex justify-between gap-4">
          <dt class="text-n-slate-11">
            {{
              $t(
                'INBOX_MGMT.ADD.WHATSAPP.BLOOMWIRE_MANAGED.SUCCESS.NUMBER_LABEL'
              )
            }}
          </dt>
          <dd class="font-medium text-n-slate-12">{{ registeredNumber }}</dd>
        </div>
        <div class="flex justify-between gap-4">
          <dt class="text-n-slate-11">
            {{
              $t(
                'INBOX_MGMT.ADD.WHATSAPP.BLOOMWIRE_MANAGED.SUCCESS.STATUS_LABEL'
              )
            }}
          </dt>
          <dd class="font-medium text-n-teal-11">
            {{
              $t(
                'INBOX_MGMT.ADD.WHATSAPP.BLOOMWIRE_MANAGED.SUCCESS.STATUS_READY'
              )
            }}
          </dd>
        </div>
      </dl>

      <div class="flex gap-2">
        <router-link
          :to="{ name: 'inbox_dashboard', params: { inbox_id: inboxId } }"
          data-testid="bloomwire-wa-open-inbox"
        >
          <NextButton
            solid
            teal
            :label="
              $t('INBOX_MGMT.ADD.WHATSAPP.BLOOMWIRE_MANAGED.SUCCESS.OPEN_INBOX')
            "
          />
        </router-link>
        <router-link
          :to="{ name: 'settings_inbox_show', params: { inboxId } }"
          data-testid="bloomwire-wa-inbox-settings"
        >
          <NextButton
            outline
            slate
            :label="
              $t(
                'INBOX_MGMT.ADD.WHATSAPP.BLOOMWIRE_MANAGED.SUCCESS.INBOX_SETTINGS'
              )
            "
          />
        </router-link>
      </div>
    </div>

    <!-- Connection choice: three options (migration, coexistence, standard). Each launches Meta Embedded Signup or,
         for migration, an explicit confirmation that reuses the Standard lifecycle. -->
    <div v-else-if="mode === 'choose'" data-testid="bloomwire-wa-choose">
      <div class="flex flex-col items-start mb-6 text-start">
        <h3 class="mb-2 text-base font-medium text-n-slate-12">
          {{ $t('INBOX_MGMT.ADD.WHATSAPP.BLOOMWIRE_MANAGED.CHOOSE.TITLE') }}
        </h3>
        <p class="text-sm leading-6 text-n-slate-11">
          {{ $t('INBOX_MGMT.ADD.WHATSAPP.BLOOMWIRE_MANAGED.CHOOSE.SUBTITLE') }}
        </p>
      </div>

      <div class="flex flex-col gap-4">
        <!-- Option 1: Move Existing Cloud API Number (Migration) — recommended. Confirmation happens first. -->
        <div
          data-testid="bloomwire-wa-choice-migration"
          data-bloomwire-wa-option="migration"
          class="rounded-xl border border-n-weak p-4"
        >
          <div class="flex flex-wrap items-center gap-2 mb-1">
            <h4 class="text-sm font-medium text-n-slate-12">
              {{
                $t(
                  'INBOX_MGMT.ADD.WHATSAPP.BLOOMWIRE_MANAGED.CHOOSE.MIGRATION.TITLE'
                )
              }}
            </h4>
            <span
              data-testid="bloomwire-wa-migration-recommended"
              class="text-xs px-2 py-0.5 rounded-full bg-n-teal-3 text-n-teal-11"
            >
              {{
                $t(
                  'INBOX_MGMT.ADD.WHATSAPP.BLOOMWIRE_MANAGED.CHOOSE.MIGRATION.RECOMMENDED'
                )
              }}
            </span>
            <span
              class="text-xs px-2 py-0.5 rounded-full bg-n-alpha-2 text-n-slate-11"
            >
              {{
                $t(
                  'INBOX_MGMT.ADD.WHATSAPP.BLOOMWIRE_MANAGED.CHOOSE.MIGRATION.BADGE'
                )
              }}
            </span>
          </div>
          <p class="text-sm text-n-slate-11 mb-3">
            {{
              $t(
                'INBOX_MGMT.ADD.WHATSAPP.BLOOMWIRE_MANAGED.CHOOSE.MIGRATION.DESC'
              )
            }}
          </p>
          <NextButton
            solid
            teal
            data-testid="bloomwire-wa-migration-cta"
            :label="
              $t(
                'INBOX_MGMT.ADD.WHATSAPP.BLOOMWIRE_MANAGED.CHOOSE.MIGRATION.CTA'
              )
            "
            @click="startMigration"
          />
        </div>

        <!-- Option 2: Connect Existing WhatsApp Business App (Coexistence) — Phase 17D.3: enabled. -->
        <div
          data-testid="bloomwire-wa-choice-coexistence"
          data-bloomwire-wa-option="coexistence"
          class="rounded-xl border border-n-weak p-4"
        >
          <div class="flex flex-wrap items-center gap-2 mb-1">
            <h4 class="text-sm font-medium text-n-slate-12">
              {{
                $t(
                  'INBOX_MGMT.ADD.WHATSAPP.BLOOMWIRE_MANAGED.CHOOSE.COEXISTENCE.TITLE'
                )
              }}
            </h4>
            <span
              class="text-xs px-2 py-0.5 rounded-full bg-n-alpha-2 text-n-slate-11"
            >
              {{
                $t(
                  'INBOX_MGMT.ADD.WHATSAPP.BLOOMWIRE_MANAGED.CHOOSE.COEXISTENCE.BADGE'
                )
              }}
            </span>
            <span
              data-testid="bloomwire-wa-coexistence-status"
              class="text-xs px-2 py-0.5 rounded-full bg-n-teal-3 text-n-teal-11"
            >
              {{
                $t(
                  'INBOX_MGMT.ADD.WHATSAPP.BLOOMWIRE_MANAGED.CHOOSE.COEXISTENCE.STATUS'
                )
              }}
            </span>
          </div>
          <p class="text-sm text-n-slate-11 mb-3">
            {{
              $t(
                'INBOX_MGMT.ADD.WHATSAPP.BLOOMWIRE_MANAGED.CHOOSE.COEXISTENCE.DESC'
              )
            }}
          </p>
          <p class="text-xs font-medium text-n-slate-11 mb-1">
            {{
              $t(
                'INBOX_MGMT.ADD.WHATSAPP.BLOOMWIRE_MANAGED.CHOOSE.COEXISTENCE.REQUIREMENTS_TITLE'
              )
            }}
          </p>
          <ul class="flex flex-col gap-1 mb-4">
            <li
              v-for="req in coexistenceRequirements"
              :key="req"
              class="flex gap-1 items-start text-xs text-n-slate-10"
            >
              <Icon icon="i-lucide-dot" class="size-4 shrink-0" />
              {{ req }}
            </li>
          </ul>
          <NextButton
            solid
            teal
            data-testid="bloomwire-wa-coexistence-cta"
            :label="
              $t(
                'INBOX_MGMT.ADD.WHATSAPP.BLOOMWIRE_MANAGED.CHOOSE.COEXISTENCE.CTA'
              )
            "
            @click="startCoexistence"
          />
        </div>

        <!-- Option 3: Register New Number (Standard) — available now; continues to the registration form. -->
        <div
          data-testid="bloomwire-wa-choice-standard"
          data-bloomwire-wa-option="standard"
          class="rounded-xl border border-n-weak p-4"
        >
          <div class="flex flex-wrap items-center gap-2 mb-1">
            <h4 class="text-sm font-medium text-n-slate-12">
              {{
                $t(
                  'INBOX_MGMT.ADD.WHATSAPP.BLOOMWIRE_MANAGED.CHOOSE.STANDARD.TITLE'
                )
              }}
            </h4>
            <span
              class="text-xs px-2 py-0.5 rounded-full bg-n-alpha-2 text-n-slate-11"
            >
              {{
                $t(
                  'INBOX_MGMT.ADD.WHATSAPP.BLOOMWIRE_MANAGED.CHOOSE.STANDARD.BADGE'
                )
              }}
            </span>
            <span
              class="text-xs px-2 py-0.5 rounded-full bg-n-teal-3 text-n-teal-11"
            >
              {{
                $t(
                  'INBOX_MGMT.ADD.WHATSAPP.BLOOMWIRE_MANAGED.CHOOSE.STANDARD.STATUS'
                )
              }}
            </span>
          </div>
          <p class="text-sm text-n-slate-11 mb-3">
            {{
              $t(
                'INBOX_MGMT.ADD.WHATSAPP.BLOOMWIRE_MANAGED.CHOOSE.STANDARD.DESC'
              )
            }}
          </p>
          <NextButton
            solid
            teal
            data-testid="bloomwire-wa-choice-standard-cta"
            :label="
              $t(
                'INBOX_MGMT.ADD.WHATSAPP.BLOOMWIRE_MANAGED.CHOOSE.STANDARD.CTA'
              )
            "
            @click="startRegister"
          />
        </div>
      </div>
    </div>

    <!-- Migration confirmation: explicit, truthful warnings BEFORE any Meta/store action. Confirm reuses the exact
         Standard lifecycle (coexistence:false); cancel returns to the chooser with no side effects. -->
    <div
      v-else-if="mode === 'migration_confirm'"
      data-testid="bloomwire-wa-migration-confirm"
    >
      <button
        type="button"
        data-testid="bloomwire-wa-migration-cancel"
        class="inline-flex items-center gap-1 text-xs text-n-slate-11 mb-6 hover:text-n-slate-12"
        @click="backToChoose"
      >
        <Icon icon="i-lucide-chevron-left" class="size-3.5" />
        {{ $t('INBOX_MGMT.ADD.WHATSAPP.BLOOMWIRE_MANAGED.CHOOSE.BACK') }}
      </button>
      <div class="flex flex-col items-start mb-6 text-start">
        <h3 class="mb-2 text-base font-medium text-n-slate-12">
          {{
            $t(
              'INBOX_MGMT.ADD.WHATSAPP.BLOOMWIRE_MANAGED.CHOOSE.MIGRATION.CONFIRM.TITLE'
            )
          }}
        </h3>
        <p class="text-sm leading-6 text-n-slate-11">
          {{
            $t(
              'INBOX_MGMT.ADD.WHATSAPP.BLOOMWIRE_MANAGED.CHOOSE.MIGRATION.CONFIRM.SUBTITLE'
            )
          }}
        </p>
      </div>

      <ul class="flex flex-col gap-2 mb-6">
        <li
          v-for="key in [
            'APPROVAL',
            'PREVIOUS_PROVIDER',
            'HISTORY',
            'CANCEL',
            'ASSET',
          ]"
          :key="key"
          class="flex gap-2 items-start text-sm text-n-slate-11"
        >
          <Icon icon="i-lucide-dot" class="size-5 shrink-0" />
          <span>
            <template v-if="key === 'APPROVAL'">{{
              $t(
                'INBOX_MGMT.ADD.WHATSAPP.BLOOMWIRE_MANAGED.CHOOSE.MIGRATION.CONFIRM.APPROVAL'
              )
            }}</template>
            <template v-else-if="key === 'PREVIOUS_PROVIDER'">{{
              $t(
                'INBOX_MGMT.ADD.WHATSAPP.BLOOMWIRE_MANAGED.CHOOSE.MIGRATION.CONFIRM.PREVIOUS_PROVIDER'
              )
            }}</template>
            <template v-else-if="key === 'HISTORY'">{{
              $t(
                'INBOX_MGMT.ADD.WHATSAPP.BLOOMWIRE_MANAGED.CHOOSE.MIGRATION.CONFIRM.HISTORY'
              )
            }}</template>
            <template v-else-if="key === 'CANCEL'">{{
              $t(
                'INBOX_MGMT.ADD.WHATSAPP.BLOOMWIRE_MANAGED.CHOOSE.MIGRATION.CONFIRM.CANCEL'
              )
            }}</template>
            <template v-else>{{
              $t(
                'INBOX_MGMT.ADD.WHATSAPP.BLOOMWIRE_MANAGED.CHOOSE.MIGRATION.CONFIRM.ASSET'
              )
            }}</template>
          </span>
        </li>
      </ul>

      <div class="flex gap-2">
        <NextButton
          solid
          teal
          data-testid="bloomwire-wa-migration-confirm-button"
          :label="
            $t(
              'INBOX_MGMT.ADD.WHATSAPP.BLOOMWIRE_MANAGED.CHOOSE.MIGRATION.CONFIRM.CONFIRM_BUTTON'
            )
          "
          @click="confirmMigration"
        />
        <NextButton
          faded
          slate
          :label="
            $t(
              'INBOX_MGMT.ADD.WHATSAPP.BLOOMWIRE_MANAGED.CHOOSE.MIGRATION.CONFIRM.CANCEL_BUTTON'
            )
          "
          @click="backToChoose"
        />
      </div>
    </div>

    <BloomwireWhatsappAsync
      v-else-if="mode === 'async_standard'"
      :can-start-new-async="useAsyncStandardOnboarding"
      :auto-start="autoStartAsync"
      @back="backToChoose"
      @use-sync-fallback="useSyncStandardFallback"
    />

    <!-- Registration form: number + inbox name only. NO credentials fields. -->
    <div v-else>
      <button
        type="button"
        data-testid="bloomwire-wa-back"
        class="inline-flex items-center gap-1 text-xs text-n-slate-11 mb-6 hover:text-n-slate-12"
        @click="backToChoose"
      >
        <Icon icon="i-lucide-chevron-left" class="size-3.5" />
        {{ $t('INBOX_MGMT.ADD.WHATSAPP.BLOOMWIRE_MANAGED.CHOOSE.BACK') }}
      </button>
      <div class="flex flex-col items-start mb-6 text-start">
        <div class="flex justify-start mb-6">
          <div
            class="flex size-11 items-center justify-center rounded-full bg-n-alpha-2"
          >
            <Icon icon="i-woot-whatsapp" class="text-n-slate-10 size-6" />
          </div>
        </div>
        <h3
          data-testid="bloomwire-wa-form-title"
          class="mb-2 text-base font-medium text-n-slate-12"
        >
          {{ formTitle }}
        </h3>
        <p class="text-sm leading-6 text-n-slate-11">
          {{ formDesc }}
        </p>
      </div>

      <form class="flex flex-col gap-5 mx-0" @submit.prevent="register">
        <div class="flex-shrink-0 flex-grow-0">
          <label class="flex flex-col gap-1.5">
            {{
              $t('INBOX_MGMT.ADD.WHATSAPP.BLOOMWIRE_MANAGED.INBOX_NAME.LABEL')
            }}
            <input
              v-model="inboxName"
              type="text"
              class="mb-0"
              data-testid="bloomwire-wa-inbox-name"
              :placeholder="
                $t(
                  'INBOX_MGMT.ADD.WHATSAPP.BLOOMWIRE_MANAGED.INBOX_NAME.PLACEHOLDER'
                )
              "
            />
          </label>
          <p class="text-xs text-n-slate-10 mt-1.5">
            {{
              $t('INBOX_MGMT.ADD.WHATSAPP.BLOOMWIRE_MANAGED.INBOX_NAME.HELP')
            }}
          </p>
        </div>

        <div class="flex-shrink-0 flex-grow-0">
          <label class="flex flex-col gap-1.5">
            {{
              $t('INBOX_MGMT.ADD.WHATSAPP.BLOOMWIRE_MANAGED.PHONE_NUMBER.LABEL')
            }}
            <input
              v-model="expectedNumber"
              type="text"
              class="mb-0"
              data-testid="bloomwire-wa-phone-number"
              :placeholder="
                $t(
                  'INBOX_MGMT.ADD.WHATSAPP.BLOOMWIRE_MANAGED.PHONE_NUMBER.PLACEHOLDER'
                )
              "
            />
          </label>
          <p class="text-xs text-n-slate-10 mt-1.5">
            {{
              $t('INBOX_MGMT.ADD.WHATSAPP.BLOOMWIRE_MANAGED.PHONE_NUMBER.HELP')
            }}
          </p>
          <p
            class="text-xs text-n-slate-10 mt-0.5"
            data-testid="bloomwire-wa-phone-number-note"
          >
            {{
              $t('INBOX_MGMT.ADD.WHATSAPP.BLOOMWIRE_MANAGED.PHONE_NUMBER.NOTE')
            }}
          </p>
        </div>

        <div v-if="errorMessage">
          <p data-testid="bloomwire-wa-error" class="text-sm text-n-ruby-11">
            {{ errorMessage }}
          </p>
          <p
            v-if="attemptRef"
            data-testid="bloomwire-wa-attempt-ref"
            class="text-xs text-n-slate-10 mt-1"
          >
            {{
              $t(
                'INBOX_MGMT.ADD.WHATSAPP.BLOOMWIRE_MANAGED.SUPPORT_REFERENCE',
                {
                  reference: attemptRef,
                }
              )
            }}
          </p>
        </div>

        <div class="flex">
          <NextButton
            type="submit"
            solid
            teal
            class="w-full"
            data-testid="bloomwire-wa-register"
            :is-loading="showLoader || isCheckingAvailability"
            :disabled="showLoader || isCheckingAvailability"
            :label="formButtonLabel"
          />
        </div>
      </form>
    </div>
  </div>
</template>
