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
import {
  createOnboardingTracer,
  createNoopTracer,
} from 'dashboard/routes/dashboard/settings/inbox/channels/whatsapp/onboardingTrace';
import Icon from 'next/icon/Icon.vue';
import NextButton from 'next/button/Button.vue';
import LoadingState from 'dashboard/components/widgets/LoadingState.vue';

// The backend create must never leave the UI pending forever (the "POST started and stayed pending" class).
// Bound it and fail closed with a safe recoverable error.
const CREATE_REQUEST_TIMEOUT_MS = 45000;

const store = useStore();
const { t } = useI18n();
const {
  isAuthenticating,
  runEmbeddedSignup,
  cancel: cancelEmbeddedSignup,
} = useWhatsappEmbeddedSignup();
// Short, non-sensitive support reference for the CURRENT attempt (set per attempt; changes on every retry).
const attemptRef = ref('');

// Lifecycle-scoped create-request control (Finding 3): a cancellable timer + an AbortController + a per-attempt
// sequence + a left-flow flag, so an in-flight create is aborted and any late response is ignored (no UI change,
// no navigation, no trace, no store refresh) on success/failure/retry/unmount/route change.
let createTimer = null;
let createAbort = null;
let attemptSeq = 0;
let leftFlow = false;
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
// True when this attempt no longer owns the flow — the component left, or a newer attempt superseded it.
const isStale = seq => leftFlow || seq !== attemptSeq;

// 'choose' = connection-choice screen (default); 'register' = the number/connect form (shared by both flows).
const mode = ref('choose');
// 'standard' = Register New Number (Cloud API); 'coexistence' = Connect Existing WhatsApp Business App (17D.3).
// Both reuse the same credential-free form + Meta Embedded Signup; only the target endpoint differs.
const flow = ref('standard');
const inboxName = ref('');
const expectedNumber = ref('');
const isProcessing = ref(false);
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
  flow.value = 'standard';
  mode.value = 'register';
};

// Phase 17D.3: enter the same credential-free form for the Coexistence flow (existing WhatsApp Business App).
const startCoexistence = () => {
  errorMessage.value = '';
  flow.value = 'coexistence';
  mode.value = 'register';
};

const backToChoose = () => {
  errorMessage.value = '';
  mode.value = 'choose';
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

// Advisory duplicate-number preflight. Returns 'already_connected' | 'available'. Fails OPEN ('available') on a
// blank number or ANY error/network failure, so the authoritative post-Meta guard stays the source of truth.
const checkPhoneAvailability = async number => {
  const trimmed = (number || '').trim();
  if (!trimmed) return 'available';
  try {
    const data = await store.dispatch(
      'inboxes/checkBloomwireWhatsAppPhoneAvailability',
      { phoneNumber: trimmed }
    );
    return data?.status === 'already_connected'
      ? 'already_connected'
      : 'available';
  } catch (_) {
    return 'available';
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

  // Advisory duplicate-number preflight — never open the Meta popup for a number already connected in Bloomwire.
  // Fails OPEN (proceeds) on blank input or any error; the authoritative global guard still runs AFTER the Meta
  // callback (Meta may confirm a different number than the one typed). Applies to Standard and Coexistence.
  if (
    (await checkPhoneAvailability(expectedNumber.value)) === 'already_connected'
  ) {
    errorMessage.value = t(
      'INBOX_MGMT.ADD.WHATSAPP.BLOOMWIRE_MANAGED.ERRORS.PHONE_NUMBER_TAKEN'
    );
    attemptActive = false;
    return;
  }

  // Fresh tracer + attempt id PER attempt. Coexistence traces; Standard/native uses a no-op tracer (no attempt
  // id, no browser trace events, no Coexistence trace endpoint, never logged as mode=coexistence).
  const tracer = isCoexistence.value
    ? createOnboardingTracer()
    : createNoopTracer();
  attemptRef.value = tracer.shortRef;
  // New attempt sequence. The guard above guarantees no active attempt is superseded here; this only advances
  // when starting a fresh attempt, so a late response from a PREVIOUS (already-terminal) attempt is ignored.
  attemptSeq += 1;
  const seq = attemptSeq;
  clearCreateTimer();
  abortCreate();

  try {
    let credentials;
    try {
      credentials = await runEmbeddedSignup({ tracer });
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

// Guaranteed cleanup on unmount / route change: settle any in-flight signup run, abort the create request, clear
// its timer, mark the flow left (so any late response is ignored) and stop every loading flag, so
// listeners/timers/pending/create state can never leak past this component's lifecycle.
const cleanupOnboarding = () => {
  leftFlow = true;
  cancelEmbeddedSignup();
  clearCreateTimer();
  abortCreate();
  isProcessing.value = false;
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
          :to="{ name: 'inbox_dashboard', params: { inboxId } }"
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

    <!-- Connection choice: two options. Both launch Meta Embedded Signup; each posts to its own endpoint. -->
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
        <!-- Option 1: Connect Existing WhatsApp Business App (Coexistence) — Phase 17D.3: enabled. -->
        <div
          data-testid="bloomwire-wa-choice-coexistence"
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

        <!-- Option 2: Register New Number (Standard) — available now; continues to the registration form. -->
        <div
          data-testid="bloomwire-wa-choice-standard"
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

    <!-- Registration form: number + inbox name only. NO credentials fields. -->
    <div v-else>
      <button
        type="button"
        data-testid="bloomwire-wa-back"
        class="text-xs text-n-slate-11 mb-4 hover:text-n-slate-12"
        @click="backToChoose"
      >
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

      <form class="flex flex-col mx-0 mb-2" @submit.prevent="register">
        <div class="flex-shrink-0 flex-grow-0">
          <label>
            {{
              $t('INBOX_MGMT.ADD.WHATSAPP.BLOOMWIRE_MANAGED.INBOX_NAME.LABEL')
            }}
            <input
              v-model="inboxName"
              type="text"
              data-testid="bloomwire-wa-inbox-name"
              :placeholder="
                $t(
                  'INBOX_MGMT.ADD.WHATSAPP.BLOOMWIRE_MANAGED.INBOX_NAME.PLACEHOLDER'
                )
              "
            />
          </label>
          <p class="text-xs text-n-slate-10 -mt-2 mb-4">
            {{
              $t('INBOX_MGMT.ADD.WHATSAPP.BLOOMWIRE_MANAGED.INBOX_NAME.HELP')
            }}
          </p>
        </div>

        <div class="flex-shrink-0 flex-grow-0">
          <label>
            {{
              $t('INBOX_MGMT.ADD.WHATSAPP.BLOOMWIRE_MANAGED.PHONE_NUMBER.LABEL')
            }}
            <input
              v-model="expectedNumber"
              type="text"
              data-testid="bloomwire-wa-phone-number"
              :placeholder="
                $t(
                  'INBOX_MGMT.ADD.WHATSAPP.BLOOMWIRE_MANAGED.PHONE_NUMBER.PLACEHOLDER'
                )
              "
            />
          </label>
          <p class="text-xs text-n-slate-10 -mt-2">
            {{
              $t('INBOX_MGMT.ADD.WHATSAPP.BLOOMWIRE_MANAGED.PHONE_NUMBER.HELP')
            }}
          </p>
          <p
            class="text-xs text-n-slate-10 mb-4"
            data-testid="bloomwire-wa-phone-number-note"
          >
            {{
              $t('INBOX_MGMT.ADD.WHATSAPP.BLOOMWIRE_MANAGED.PHONE_NUMBER.NOTE')
            }}
          </p>
        </div>

        <div v-if="errorMessage" class="mb-4">
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

        <div class="flex mt-2">
          <NextButton
            type="submit"
            solid
            teal
            class="w-full"
            data-testid="bloomwire-wa-register"
            :is-loading="showLoader"
            :disabled="showLoader"
            :label="formButtonLabel"
          />
        </div>
      </form>
    </div>
  </div>
</template>
