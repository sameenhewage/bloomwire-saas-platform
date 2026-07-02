<script setup>
// Phase 17C.3: managed self-serve customer WhatsApp NUMBER REGISTRATION wizard (Bloomwire). Rendered by
// ChannelFactory in place of the native WhatsApp setup when `canSelfServeManagedWhatsapp` is true. This is ONLY
// number registration — there is deliberately NO "Add Agents" step (Chatwoot's existing inbox-agent management
// owns that). It asks the customer for NO credentials (no App Secret / Verify Token / Webhook URL / API token /
// provider_config); it launches Meta Embedded Signup, sends only the non-secret signup credentials to the
// dedicated Bloomwire endpoint, and renders a safe DTO on success. The registered number shown is the backend/
// Meta source of truth (not the typed number). Failures show a single sanitized generic message.
import { ref, computed } from 'vue';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import { useWhatsappEmbeddedSignup } from 'dashboard/composables/useWhatsappEmbeddedSignup';
import Icon from 'next/icon/Icon.vue';
import NextButton from 'next/button/Button.vue';
import LoadingState from 'dashboard/components/widgets/LoadingState.vue';

const store = useStore();
const { t } = useI18n();
const { isAuthenticating, runEmbeddedSignup } = useWhatsappEmbeddedSignup();

const inboxName = ref('');
const expectedNumber = ref('');
const isProcessing = ref(false);
const errorMessage = ref('');
const result = ref(null);

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

const register = async () => {
  errorMessage.value = '';

  let credentials;
  try {
    credentials = await runEmbeddedSignup();
  } catch (_) {
    errorMessage.value = t('INBOX_MGMT.ADD.WHATSAPP.BLOOMWIRE_MANAGED.ERROR');
    return;
  }

  // Resolves null when the customer dismisses the Meta popup.
  if (!credentials) {
    errorMessage.value = t(
      'INBOX_MGMT.ADD.WHATSAPP.BLOOMWIRE_MANAGED.CANCELLED'
    );
    return;
  }

  isProcessing.value = true;
  try {
    // Only the non-secret Meta signup credentials are sent — no typed number, no credentials.
    const dto = await store.dispatch(
      'inboxes/createBloomwireWhatsAppEmbeddedSignup',
      credentials
    );
    result.value = dto;
    await maybeRenameInbox();
  } catch (_) {
    // Never surface the raw server/Meta error — always the sanitized generic message.
    errorMessage.value = t('INBOX_MGMT.ADD.WHATSAPP.BLOOMWIRE_MANAGED.ERROR');
  } finally {
    isProcessing.value = false;
  }
};
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

    <!-- Registration form: number + inbox name only. NO credentials fields. -->
    <div v-else>
      <div class="flex flex-col items-start mb-6 text-start">
        <div class="flex justify-start mb-6">
          <div
            class="flex size-11 items-center justify-center rounded-full bg-n-alpha-2"
          >
            <Icon icon="i-woot-whatsapp" class="text-n-slate-10 size-6" />
          </div>
        </div>
        <h3 class="mb-2 text-base font-medium text-n-slate-12">
          {{ $t('INBOX_MGMT.ADD.WHATSAPP.BLOOMWIRE_MANAGED.TITLE') }}
        </h3>
        <p class="text-sm leading-6 text-n-slate-11">
          {{ $t('INBOX_MGMT.ADD.WHATSAPP.BLOOMWIRE_MANAGED.DESC') }}
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
          <p class="text-xs text-n-slate-10 -mt-2 mb-4">
            {{
              $t('INBOX_MGMT.ADD.WHATSAPP.BLOOMWIRE_MANAGED.PHONE_NUMBER.HELP')
            }}
          </p>
        </div>

        <p
          v-if="errorMessage"
          data-testid="bloomwire-wa-error"
          class="text-sm text-n-ruby-11 mb-4"
        >
          {{ errorMessage }}
        </p>

        <div class="flex mt-2">
          <NextButton
            type="submit"
            solid
            teal
            class="w-full"
            data-testid="bloomwire-wa-register"
            :is-loading="showLoader"
            :disabled="showLoader"
            :label="
              $t('INBOX_MGMT.ADD.WHATSAPP.BLOOMWIRE_MANAGED.REGISTER_BUTTON')
            "
          />
        </div>
      </form>
    </div>
  </div>
</template>
