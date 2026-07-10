<script setup>
// ADR-0010 v3: the ASYNC Standard "Register New Number" wizard. The shared BloomwireWhatsapp chooser renders this
// child only for Standard when the explicit `canUseAsyncStandardWhatsappOnboarding` capability is true. It never
// routes from a 404. Coexistence stays on its existing flow regardless of the Standard emergency switch. A persisted
// account-scoped attempt resumes here even if the switch later changes, because in-flight polling remains available.
import { computed, onMounted, onBeforeUnmount } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStoreGetters } from 'dashboard/composables/store';
import {
  useAsyncWhatsappOnboarding,
  ONBOARDING_STATES as S,
} from 'dashboard/composables/useAsyncWhatsappOnboarding';
import Icon from 'next/icon/Icon.vue';
import NextButton from 'next/button/Button.vue';
import LoadingState from 'dashboard/components/widgets/LoadingState.vue';

const props = defineProps({
  canStartNewAsync: {
    type: Boolean,
    default: true,
  },
});
const emit = defineEmits(['back', 'useSyncFallback']);

const { t } = useI18n();
const getters = useStoreGetters();
const accountId = getters.getCurrentAccountId?.value;

const {
  state,
  attempt,
  errorCode,
  takingLongerThanUsual,
  start,
  resume,
  relaunch,
  cancel,
  checkStatus,
  restart,
  stopPolling,
} = useAsyncWhatsappOnboarding({ accountId });

const LAUNCHING = [S.CREATING, S.AWAITING_META, S.SUBMITTING];
const isLaunching = computed(() => LAUNCHING.includes(state.value));
const isProcessing = computed(() => state.value === S.PROCESSING);
const showLoader = computed(() => isLaunching.value || isProcessing.value);
const isIdle = computed(() => [S.IDLE, S.CANCELLED].includes(state.value));

// Static keys only (no dynamic $t args) so the vue-i18n linter can resolve them, matching the sync sibling.
const statusMessage = computed(() => {
  switch (state.value) {
    case S.CREATING:
      return t('INBOX_MGMT.ADD.WHATSAPP.BLOOMWIRE_MANAGED.ASYNC.CREATING');
    case S.AWAITING_META:
      return t('INBOX_MGMT.ADD.WHATSAPP.BLOOMWIRE_MANAGED.ASYNC.AWAITING_META');
    case S.SUBMITTING:
      return t('INBOX_MGMT.ADD.WHATSAPP.BLOOMWIRE_MANAGED.ASYNC.SUBMITTING');
    case S.PROCESSING:
      return t('INBOX_MGMT.ADD.WHATSAPP.BLOOMWIRE_MANAGED.ASYNC.PROCESSING');
    default:
      return '';
  }
});

const inboxId = computed(() => attempt.value?.inbox_id);
const maskedPhone = computed(() => attempt.value?.phone);

const actionReasonKey = computed(() => {
  if (errorCode.value === 'outbound_messaging_permission_required')
    return 'PERMISSION_REQUIRED';
  if (errorCode.value === 'activation_incomplete')
    return 'ACTIVATION_INCOMPLETE';
  return 'UNVERIFIABLE';
});

const startOnCurrentPath = () => {
  if (props.canStartNewAsync) return start();
  emit('useSyncFallback');
  return undefined;
};

const restartOnCurrentPath = async () => {
  if (props.canStartNewAsync) return restart();
  await cancel();
  emit('useSyncFallback');
  return undefined;
};

// Resume an in-flight attempt (account-scoped) after a refresh / navigation. Returns false when there is none, so
// the UI lands on the start screen.
onMounted(() => {
  resume();
});
// Stop polling on unmount WITHOUT clearing the resumable attempt (it keeps running server-side; a return resumes).
onBeforeUnmount(() => {
  stopPolling();
});
</script>

<template>
  <div class="h-full">
    <div
      v-if="state === S.WAITING_META"
      class="flex flex-col items-start py-8"
      data-testid="bloomwire-wa-async-waiting-meta"
    >
      <p
        class="mb-2 text-xs font-medium uppercase text-n-slate-10"
        data-testid="bloomwire-wa-async-flow-label"
      >
        {{
          $t(
            'INBOX_MGMT.ADD.WHATSAPP.BLOOMWIRE_MANAGED.ASYNC.STANDARD_FLOW_LABEL'
          )
        }}
      </p>
      <h3 class="mb-2 text-base font-medium text-n-slate-12">
        {{
          $t(
            'INBOX_MGMT.ADD.WHATSAPP.BLOOMWIRE_MANAGED.ASYNC.WAITING_META.TITLE'
          )
        }}
      </h3>
      <p class="mb-4 text-sm leading-6 text-n-slate-11">
        {{
          $t(
            'INBOX_MGMT.ADD.WHATSAPP.BLOOMWIRE_MANAGED.ASYNC.WAITING_META.SUBTITLE'
          )
        }}
      </p>
      <p
        v-if="errorCode"
        class="mb-6 text-xs text-n-slate-10"
        data-testid="bloomwire-wa-async-error-code"
      >
        {{
          $t('INBOX_MGMT.ADD.WHATSAPP.BLOOMWIRE_MANAGED.ASYNC.ERROR_REFERENCE')
        }}
        <code>{{ errorCode }}</code>
      </p>
      <div class="flex gap-2">
        <NextButton
          solid
          teal
          :label="
            $t(
              'INBOX_MGMT.ADD.WHATSAPP.BLOOMWIRE_MANAGED.ASYNC.WAITING_META.RELAUNCH_BUTTON'
            )
          "
          data-testid="bloomwire-wa-async-relaunch"
          @click="relaunch"
        />
        <NextButton
          outline
          slate
          :label="
            $t(
              'INBOX_MGMT.ADD.WHATSAPP.BLOOMWIRE_MANAGED.ASYNC.WAITING_META.CANCEL_BUTTON'
            )
          "
          data-testid="bloomwire-wa-async-cancel"
          @click="cancel"
        />
      </div>
    </div>

    <!-- Launch + processing: the attempt exists server-side and is being polled; never an infinite spinner. -->
    <div v-else-if="showLoader" data-testid="bloomwire-wa-async-processing">
      <LoadingState :message="statusMessage" />
      <p
        v-if="isProcessing && takingLongerThanUsual"
        class="mt-4 text-sm text-center text-n-slate-11"
        data-testid="bloomwire-wa-async-longer"
      >
        {{
          $t(
            'INBOX_MGMT.ADD.WHATSAPP.BLOOMWIRE_MANAGED.ASYNC.LONGER_THAN_USUAL'
          )
        }}
      </p>
    </div>

    <!-- Completed: the inbox is live. -->
    <div
      v-else-if="state === S.COMPLETED"
      class="flex flex-col items-center py-8 text-center"
      data-testid="bloomwire-wa-async-success"
    >
      <div
        class="flex items-center justify-center w-12 h-12 mb-4 rounded-full bg-n-teal-3"
      >
        <Icon icon="i-lucide-check" class="text-n-teal-11 size-6" />
      </div>
      <h3 class="mb-2 text-base font-medium text-n-slate-12">
        {{ $t('INBOX_MGMT.ADD.WHATSAPP.BLOOMWIRE_MANAGED.SUCCESS.TITLE') }}
      </h3>
      <p class="mb-6 text-sm leading-6 text-n-slate-11">
        {{ $t('INBOX_MGMT.ADD.WHATSAPP.BLOOMWIRE_MANAGED.SUCCESS.SUBTITLE') }}
      </p>
      <dl v-if="maskedPhone" class="mb-6 text-sm">
        <dt class="text-n-slate-11">
          {{
            $t('INBOX_MGMT.ADD.WHATSAPP.BLOOMWIRE_MANAGED.SUCCESS.NUMBER_LABEL')
          }}
        </dt>
        <dd class="font-medium text-n-slate-12">{{ maskedPhone }}</dd>
      </dl>
      <div class="flex gap-2">
        <router-link
          v-if="inboxId"
          :to="{ name: 'inbox_dashboard', params: { inbox_id: inboxId } }"
          data-testid="bloomwire-wa-async-open-inbox"
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
          v-if="inboxId"
          :to="{ name: 'settings_inbox_show', params: { inboxId } }"
          data-testid="bloomwire-wa-async-inbox-settings"
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

    <!-- Action required: connected to Meta but outbound messaging not enabled yet. -->
    <div
      v-else-if="state === S.ACTION_REQUIRED"
      class="flex flex-col items-start py-8"
      data-testid="bloomwire-wa-async-action-required"
    >
      <h3 class="mb-2 text-base font-medium text-n-slate-12">
        {{
          $t('INBOX_MGMT.ADD.WHATSAPP.BLOOMWIRE_MANAGED.ACTION_REQUIRED.TITLE')
        }}
      </h3>
      <p class="mb-4 text-sm leading-6 text-n-slate-11">
        {{
          $t(
            'INBOX_MGMT.ADD.WHATSAPP.BLOOMWIRE_MANAGED.ACTION_REQUIRED.SUBTITLE'
          )
        }}
      </p>
      <p class="mb-4 text-sm text-n-slate-11">
        <template v-if="actionReasonKey === 'PERMISSION_REQUIRED'">
          {{
            $t(
              'INBOX_MGMT.ADD.WHATSAPP.BLOOMWIRE_MANAGED.ACTION_REQUIRED.REASON.PERMISSION_REQUIRED'
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
              'INBOX_MGMT.ADD.WHATSAPP.BLOOMWIRE_MANAGED.ACTION_REQUIRED.REASON.UNVERIFIABLE'
            )
          }}
        </template>
      </p>
      <router-link
        v-if="inboxId"
        :to="{ name: 'settings_inbox_show', params: { inboxId } }"
        data-testid="bloomwire-wa-async-action-settings"
      >
        <NextButton
          solid
          teal
          :label="
            $t(
              'INBOX_MGMT.ADD.WHATSAPP.BLOOMWIRE_MANAGED.ACTION_REQUIRED.RECHECK_BUTTON'
            )
          "
        />
      </router-link>
    </div>

    <!-- Expired: the server explicitly reported that the Meta session expired. -->
    <div
      v-else-if="state === S.EXPIRED"
      class="flex flex-col items-start py-8"
      data-testid="bloomwire-wa-async-expired"
    >
      <h3 class="mb-2 text-base font-medium text-n-slate-12">
        {{
          $t('INBOX_MGMT.ADD.WHATSAPP.BLOOMWIRE_MANAGED.ASYNC.EXPIRED.TITLE')
        }}
      </h3>
      <p class="mb-6 text-sm leading-6 text-n-slate-11">
        {{
          $t('INBOX_MGMT.ADD.WHATSAPP.BLOOMWIRE_MANAGED.ASYNC.EXPIRED.SUBTITLE')
        }}
      </p>
      <NextButton
        solid
        teal
        :label="
          $t(
            'INBOX_MGMT.ADD.WHATSAPP.BLOOMWIRE_MANAGED.ASYNC.EXPIRED.RESTART_BUTTON'
          )
        "
        data-testid="bloomwire-wa-async-restart"
        @click="restartOnCurrentPath"
      />
    </div>

    <div
      v-else-if="state === S.ATTEMPT_NOT_FOUND"
      class="flex flex-col items-start py-8"
      data-testid="bloomwire-wa-async-attempt-not-found"
    >
      <h3 class="mb-2 text-base font-medium text-n-slate-12">
        {{
          $t(
            'INBOX_MGMT.ADD.WHATSAPP.BLOOMWIRE_MANAGED.ASYNC.ATTEMPT_NOT_FOUND.TITLE'
          )
        }}
      </h3>
      <p class="mb-6 text-sm leading-6 text-n-slate-11">
        {{
          $t(
            'INBOX_MGMT.ADD.WHATSAPP.BLOOMWIRE_MANAGED.ASYNC.ATTEMPT_NOT_FOUND.SUBTITLE'
          )
        }}
      </p>
      <div class="flex gap-2">
        <NextButton
          outline
          slate
          :label="
            $t(
              'INBOX_MGMT.ADD.WHATSAPP.BLOOMWIRE_MANAGED.ASYNC.ATTEMPT_NOT_FOUND.CHECK_BUTTON'
            )
          "
          data-testid="bloomwire-wa-async-check-status"
          @click="checkStatus"
        />
        <NextButton
          solid
          teal
          :label="
            $t(
              'INBOX_MGMT.ADD.WHATSAPP.BLOOMWIRE_MANAGED.ASYNC.ATTEMPT_NOT_FOUND.RESTART_BUTTON'
            )
          "
          data-testid="bloomwire-wa-async-restart"
          @click="restartOnCurrentPath"
        />
      </div>
    </div>

    <!-- Failed: no automatic retry. Offer a clean restart. -->
    <div
      v-else-if="state === S.FAILED"
      class="flex flex-col items-start py-8"
      data-testid="bloomwire-wa-async-failed"
    >
      <p
        class="mb-2 text-xs font-medium uppercase text-n-slate-10"
        data-testid="bloomwire-wa-async-flow-label"
      >
        {{
          $t(
            'INBOX_MGMT.ADD.WHATSAPP.BLOOMWIRE_MANAGED.ASYNC.STANDARD_FLOW_LABEL'
          )
        }}
      </p>
      <h3
        class="mb-2 text-base font-medium text-n-slate-12"
        data-testid="bloomwire-wa-async-failed-title"
      >
        {{ $t('INBOX_MGMT.ADD.WHATSAPP.BLOOMWIRE_MANAGED.ASYNC.FAILED.TITLE') }}
      </h3>
      <p class="mb-4 text-sm leading-6 text-n-slate-11">
        {{
          $t('INBOX_MGMT.ADD.WHATSAPP.BLOOMWIRE_MANAGED.ASYNC.FAILED.SUBTITLE')
        }}
      </p>
      <p
        v-if="errorCode"
        class="mb-6 text-xs text-n-slate-10"
        data-testid="bloomwire-wa-async-error-code"
      >
        {{
          $t('INBOX_MGMT.ADD.WHATSAPP.BLOOMWIRE_MANAGED.ASYNC.ERROR_REFERENCE')
        }}
        <code>{{ errorCode }}</code>
      </p>
      <NextButton
        solid
        teal
        :label="
          $t('INBOX_MGMT.ADD.WHATSAPP.BLOOMWIRE_MANAGED.ASYNC.RESTART_BUTTON')
        "
        data-testid="bloomwire-wa-async-restart"
        @click="restartOnCurrentPath"
      />
    </div>

    <!-- Idle / cancelled: the start screen. -->
    <div v-else-if="isIdle" data-testid="bloomwire-wa-async-start">
      <button
        type="button"
        data-testid="bloomwire-wa-async-back"
        class="inline-flex items-center gap-1 text-xs text-n-slate-11 mb-6 hover:text-n-slate-12"
        @click="emit('back')"
      >
        <Icon icon="i-lucide-chevron-left" class="size-3.5" />
        {{ $t('INBOX_MGMT.ADD.WHATSAPP.BLOOMWIRE_MANAGED.CHOOSE.BACK') }}
      </button>
      <div class="flex flex-col items-start mb-6 text-start">
        <h3 class="mb-2 text-base font-medium text-n-slate-12">
          {{ $t('INBOX_MGMT.ADD.WHATSAPP.BLOOMWIRE_MANAGED.TITLE') }}
        </h3>
        <p class="text-sm leading-6 text-n-slate-11">
          {{ $t('INBOX_MGMT.ADD.WHATSAPP.BLOOMWIRE_MANAGED.DESC') }}
        </p>
      </div>
      <NextButton
        solid
        teal
        :label="$t('INBOX_MGMT.ADD.WHATSAPP.BLOOMWIRE_MANAGED.REGISTER_BUTTON')"
        data-testid="bloomwire-wa-async-register"
        @click="startOnCurrentPath"
      />
    </div>
  </div>
</template>
