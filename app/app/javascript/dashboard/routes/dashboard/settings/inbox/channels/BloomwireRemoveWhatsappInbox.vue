<script setup>
// Admin "Remove WhatsApp Inbox" — a destructive action + confirmation modal for a managed WhatsApp inbox. It shows
// the inbox name, a MASKED phone number (last 4 only), the connection mode, an irreversible-deletion warning, and
// the Meta-boundary note. On confirm it calls the account-scoped, admin-gated deprovision endpoint (which blocks
// routing, removes setup/inbox/channel + owned data, preserves shared Contacts, and makes no Meta call). Repeated
// clicks are disabled while deleting; success/failure is surfaced via a safe alert. Never renders the full number,
// phone_number_id, WABA id, or any credential.
import { ref, computed, onBeforeUnmount } from 'vue';
import { onBeforeRouteLeave } from 'vue-router';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import NextButton from 'next/button/Button.vue';

const props = defineProps({
  inbox: { type: Object, required: true },
});

const emit = defineEmits(['removed']);

// The removal request only enqueues the async deletion, but must never leave the UI pending forever — bound it and
// abort on unmount / route change.
const REMOVE_REQUEST_TIMEOUT_MS = 15000;

const store = useStore();
const { t } = useI18n();

const showConfirm = ref(false);
const isDeleting = ref(false);

// Bounded, abortable request lifecycle: a cancellable timer + an AbortController + a left-flow flag so a late
// response after unmount / route change never fires an alert, emits, or flips loading state.
let deleteAbort = null;
let deleteTimer = null;
let leftFlow = false;

const clearDeleteTimer = () => {
  if (deleteTimer) {
    clearTimeout(deleteTimer);
    deleteTimer = null;
  }
};
const abortDelete = () => {
  if (deleteAbort) {
    try {
      deleteAbort.abort();
    } catch (_) {
      // AbortController unavailable in some very old runtimes — safe to ignore.
    }
    deleteAbort = null;
  }
};

// Mask to the last 4 digits only — never show the full number.
const maskedNumber = computed(() => {
  const digits = String(props.inbox?.phone_number || '').replace(/\D/g, '');
  return digits ? `••• ••• ${digits.slice(-4)}` : '—';
});

const isCoexistence = computed(
  () => props.inbox?.provider_config?.connection_mode === 'coexistence'
);
const connectionModeLabel = computed(() =>
  isCoexistence.value
    ? t('INBOX_MGMT.ADD.WHATSAPP.BLOOMWIRE_MANAGED.REMOVE.MODE_COEXISTENCE')
    : t('INBOX_MGMT.ADD.WHATSAPP.BLOOMWIRE_MANAGED.REMOVE.MODE_STANDARD')
);

const openConfirm = () => {
  showConfirm.value = true;
};
const closeConfirm = () => {
  if (!isDeleting.value) showConfirm.value = false;
};

const confirmRemove = async () => {
  if (isDeleting.value) return; // disable repeated clicks while the request is in flight
  isDeleting.value = true;
  clearDeleteTimer();
  abortDelete();
  deleteAbort =
    typeof AbortController !== 'undefined' ? new AbortController() : null;
  deleteTimer = setTimeout(abortDelete, REMOVE_REQUEST_TIMEOUT_MS);

  try {
    await store.dispatch('inboxes/removeBloomwireWhatsAppInbox', {
      inboxId: props.inbox.id,
      signal: deleteAbort?.signal,
    });
    if (leftFlow) return; // left the page mid-request — no late alert/emit
    clearDeleteTimer();
    // Accepted async job — the deletion has STARTED (not necessarily finished).
    useAlert(t('INBOX_MGMT.ADD.WHATSAPP.BLOOMWIRE_MANAGED.REMOVE.STARTED'));
    showConfirm.value = false;
    emit('removed', props.inbox.id);
  } catch (error) {
    if (leftFlow) return; // left the page mid-request — no late alert
    clearDeleteTimer();
    // Safe, generic failure message — never a raw backend/Meta error.
    useAlert(t('INBOX_MGMT.ADD.WHATSAPP.BLOOMWIRE_MANAGED.REMOVE.ERROR'));
  } finally {
    if (!leftFlow) isDeleting.value = false;
  }
};

// On unmount / route change: mark the flow left and abort any in-flight request so no late alert/emit can fire.
const cleanup = () => {
  leftFlow = true;
  abortDelete();
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
      data-testid="bloomwire-remove-wa-action"
      :label="$t('INBOX_MGMT.ADD.WHATSAPP.BLOOMWIRE_MANAGED.REMOVE.ACTION')"
      @click="openConfirm"
    />

    <woot-modal
      v-if="showConfirm"
      v-model:show="showConfirm"
      :on-close="closeConfirm"
    >
      <div
        class="flex flex-col p-8 gap-4"
        data-testid="bloomwire-remove-wa-modal"
      >
        <h2 class="text-lg font-medium text-n-slate-12">
          {{ $t('INBOX_MGMT.ADD.WHATSAPP.BLOOMWIRE_MANAGED.REMOVE.TITLE') }}
        </h2>

        <p
          class="text-sm text-n-ruby-11"
          data-testid="bloomwire-remove-wa-warning"
        >
          {{ $t('INBOX_MGMT.ADD.WHATSAPP.BLOOMWIRE_MANAGED.REMOVE.WARNING') }}
        </p>

        <dl class="text-sm text-n-slate-12 flex flex-col gap-1">
          <div class="flex gap-2">
            <dt class="text-n-slate-10">
              {{
                $t(
                  'INBOX_MGMT.ADD.WHATSAPP.BLOOMWIRE_MANAGED.REMOVE.INBOX_LABEL'
                )
              }}
            </dt>
            <dd data-testid="bloomwire-remove-wa-name">{{ inbox.name }}</dd>
          </div>
          <div class="flex gap-2">
            <dt class="text-n-slate-10">
              {{
                $t(
                  'INBOX_MGMT.ADD.WHATSAPP.BLOOMWIRE_MANAGED.REMOVE.NUMBER_LABEL'
                )
              }}
            </dt>
            <dd data-testid="bloomwire-remove-wa-number">{{ maskedNumber }}</dd>
          </div>
          <div class="flex gap-2">
            <dt class="text-n-slate-10">
              {{
                $t(
                  'INBOX_MGMT.ADD.WHATSAPP.BLOOMWIRE_MANAGED.REMOVE.MODE_LABEL'
                )
              }}
            </dt>
            <dd data-testid="bloomwire-remove-wa-mode">
              {{ connectionModeLabel }}
            </dd>
          </div>
        </dl>

        <p
          class="text-xs text-n-slate-11"
          data-testid="bloomwire-remove-wa-meta-note"
        >
          {{ $t('INBOX_MGMT.ADD.WHATSAPP.BLOOMWIRE_MANAGED.REMOVE.META_NOTE') }}
        </p>

        <div class="flex justify-end gap-2 mt-2">
          <NextButton
            faded
            slate
            data-testid="bloomwire-remove-wa-cancel"
            :disabled="isDeleting"
            :label="
              $t('INBOX_MGMT.ADD.WHATSAPP.BLOOMWIRE_MANAGED.REMOVE.CANCEL')
            "
            @click="closeConfirm"
          />
          <NextButton
            ruby
            solid
            data-testid="bloomwire-remove-wa-confirm"
            :is-loading="isDeleting"
            :disabled="isDeleting"
            :label="
              $t('INBOX_MGMT.ADD.WHATSAPP.BLOOMWIRE_MANAGED.REMOVE.CONFIRM')
            "
            @click="confirmRemove"
          />
        </div>
      </div>
    </woot-modal>
  </div>
</template>
