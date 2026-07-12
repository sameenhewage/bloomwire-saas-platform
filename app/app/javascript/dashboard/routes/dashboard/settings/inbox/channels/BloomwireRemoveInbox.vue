<script setup>
// Bloomwire universal "Remove inbox" — an Account Administrator's destructive delete + confirmation modal for ANY
// inbox type (WhatsApp, API, Web widget, Email, Facebook/Instagram, …). The confirmation shows the inbox name, the
// channel type, a MASKED identifier where applicable (WhatsApp/SMS phone last-4, Email address), and a permanent-
// deletion warning. On confirm it dispatches the stock account-scoped, admin-gated inbox delete — which, in Bloomwire
// mode, routes a WhatsApp delete through the Meta-safe async deprovision (no Meta call) and every other type through
// the stock DeleteObjectJob. Repeated clicks are disabled while deleting; a bounded timeout + a route-leave/unmount
// guard prevent a stuck spinner or a late alert. Never renders a full phone number, an email local-part, a provider
// id, or any credential.
import { ref, computed, onBeforeUnmount } from 'vue';
import { onBeforeRouteLeave } from 'vue-router';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { INBOX_TYPES } from 'dashboard/helper/inbox';
import ChannelName from '../components/ChannelName.vue';
import NextButton from 'next/button/Button.vue';

const props = defineProps({
  inbox: { type: Object, required: true },
});

const emit = defineEmits(['removed']);

// The delete request only enqueues the async deletion, but the UI must never hang forever — bound it and stop
// reacting on unmount / route change.
const REMOVE_REQUEST_TIMEOUT_MS = 15000;

const store = useStore();
const { t } = useI18n();

const showConfirm = ref(false);
const isDeleting = ref(false);

// Single-settle lifecycle: whichever of success / error / timeout fires first wins; the rest are no-ops. `leftFlow`
// blocks every terminal handler once the component unmounts or the route changes (no late alert / emit).
let deleteTimer = null;
let leftFlow = false;
let settled = false;

const clearDeleteTimer = () => {
  if (deleteTimer) {
    clearTimeout(deleteTimer);
    deleteTimer = null;
  }
};

const isWhatsApp = computed(
  () => props.inbox?.channel_type === INBOX_TYPES.WHATSAPP
);

const maskEmail = value => {
  const [local, domain] = String(value || '').split('@');
  if (!domain || !local) return '';
  return `${local.slice(0, 2)}${'•'.repeat(Math.max(local.length - 2, 1))}@${domain}`;
};

// Masked, non-secret identifier for the confirmation (phone for WhatsApp/SMS, address for Email; blank otherwise).
const maskedIdentifier = computed(() => {
  const type = props.inbox?.channel_type;
  if (type === INBOX_TYPES.WHATSAPP || type === INBOX_TYPES.SMS) {
    const digits = String(props.inbox?.phone_number || '').replace(/\D/g, '');
    return digits ? `••• ••• ${digits.slice(-4)}` : '';
  }
  if (type === INBOX_TYPES.EMAIL) {
    return maskEmail(props.inbox?.email || props.inbox?.forward_to_email);
  }
  return '';
});

const openConfirm = () => {
  showConfirm.value = true;
};
const closeConfirm = () => {
  if (!isDeleting.value) showConfirm.value = false;
};

// Runs the FIRST terminal outcome only, clears the timer, and stops the spinner.
const settle = handler => {
  if (settled || leftFlow) return;
  settled = true;
  clearDeleteTimer();
  isDeleting.value = false;
  handler();
};

const confirmRemove = async () => {
  if (isDeleting.value) return; // disable repeated clicks while the request is in flight
  settled = false;
  isDeleting.value = true;
  clearDeleteTimer();
  deleteTimer = setTimeout(
    () => settle(() => useAlert(t('INBOX_MGMT.BLOOMWIRE_REMOVE.ERROR'))),
    REMOVE_REQUEST_TIMEOUT_MS
  );

  try {
    const result = await store.dispatch('inboxes/delete', props.inbox.id);
    settle(() => {
      // Accepted — the deletion has STARTED (a WhatsApp delete finishes asynchronously).
      useAlert(t('INBOX_MGMT.BLOOMWIRE_REMOVE.STARTED'));
      showConfirm.value = false;
      if (result?.status !== 'pending') emit('removed', props.inbox.id);
    });
  } catch (error) {
    // Safe, generic failure message — never a raw backend / Meta error.
    settle(() => useAlert(t('INBOX_MGMT.BLOOMWIRE_REMOVE.ERROR')));
  }
};

// On unmount / route change: mark the flow left so no late alert / emit / spinner-flip can fire.
const cleanup = () => {
  leftFlow = true;
  clearDeleteTimer();
};
onBeforeUnmount(cleanup);
onBeforeRouteLeave(() => {
  cleanup();
});
</script>

<template>
  <div>
    <NextButton
      ruby
      solid
      data-testid="bloomwire-remove-inbox-action"
      :label="$t('INBOX_MGMT.BLOOMWIRE_REMOVE.ACTION')"
      @click="openConfirm"
    />

    <woot-modal
      v-if="showConfirm"
      v-model:show="showConfirm"
      :on-close="closeConfirm"
    >
      <div
        class="flex flex-col p-8 gap-4"
        data-testid="bloomwire-remove-inbox-modal"
      >
        <h2 class="text-lg font-medium text-n-slate-12">
          {{ $t('INBOX_MGMT.BLOOMWIRE_REMOVE.TITLE') }}
        </h2>

        <p
          class="text-sm text-n-ruby-11"
          data-testid="bloomwire-remove-inbox-warning"
        >
          {{ $t('INBOX_MGMT.BLOOMWIRE_REMOVE.WARNING') }}
        </p>

        <dl class="text-sm text-n-slate-12 flex flex-col gap-1">
          <div class="flex gap-2">
            <dt class="text-n-slate-10">
              {{ $t('INBOX_MGMT.BLOOMWIRE_REMOVE.INBOX_LABEL') }}
            </dt>
            <dd data-testid="bloomwire-remove-inbox-name">{{ inbox.name }}</dd>
          </div>
          <div class="flex gap-2">
            <dt class="text-n-slate-10">
              {{ $t('INBOX_MGMT.BLOOMWIRE_REMOVE.TYPE_LABEL') }}
            </dt>
            <dd data-testid="bloomwire-remove-inbox-type">
              <ChannelName
                :channel-type="inbox.channel_type"
                :medium="inbox.medium"
              />
            </dd>
          </div>
          <div v-if="maskedIdentifier" class="flex gap-2">
            <dt class="text-n-slate-10">
              {{ $t('INBOX_MGMT.BLOOMWIRE_REMOVE.IDENTIFIER_LABEL') }}
            </dt>
            <dd data-testid="bloomwire-remove-inbox-identifier">
              {{ maskedIdentifier }}
            </dd>
          </div>
        </dl>

        <p
          v-if="isWhatsApp"
          class="text-xs text-n-slate-11"
          data-testid="bloomwire-remove-inbox-meta-note"
        >
          {{ $t('INBOX_MGMT.BLOOMWIRE_REMOVE.META_NOTE') }}
        </p>

        <div class="flex justify-end gap-2 mt-2">
          <NextButton
            faded
            slate
            data-testid="bloomwire-remove-inbox-cancel"
            :disabled="isDeleting"
            :label="$t('INBOX_MGMT.BLOOMWIRE_REMOVE.CANCEL')"
            @click="closeConfirm"
          />
          <NextButton
            ruby
            solid
            data-testid="bloomwire-remove-inbox-confirm"
            :is-loading="isDeleting"
            :disabled="isDeleting"
            :label="$t('INBOX_MGMT.BLOOMWIRE_REMOVE.CONFIRM')"
            @click="confirmRemove"
          />
        </div>
      </div>
    </woot-modal>
  </div>
</template>
