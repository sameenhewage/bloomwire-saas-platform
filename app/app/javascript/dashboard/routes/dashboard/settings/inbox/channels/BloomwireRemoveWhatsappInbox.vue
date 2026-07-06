<script setup>
// Admin "Remove WhatsApp Inbox" — a destructive action + confirmation modal for a managed WhatsApp inbox. It shows
// the inbox name, a MASKED phone number (last 4 only), the connection mode, an irreversible-deletion warning, and
// the Meta-boundary note. On confirm it calls the account-scoped, admin-gated deprovision endpoint (which blocks
// routing, removes setup/inbox/channel + owned data, preserves shared Contacts, and makes no Meta call). Repeated
// clicks are disabled while deleting; success/failure is surfaced via a safe alert. Never renders the full number,
// phone_number_id, WABA id, or any credential.
import { ref, computed } from 'vue';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import NextButton from 'next/button/Button.vue';

const props = defineProps({
  inbox: { type: Object, required: true },
});
const emit = defineEmits(['removed']);

const store = useStore();
const { t } = useI18n();

const showConfirm = ref(false);
const isDeleting = ref(false);

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
  if (isDeleting.value) return; // disable repeated clicks while deletion runs
  isDeleting.value = true;
  try {
    await store.dispatch(
      'inboxes/removeBloomwireWhatsAppInbox',
      props.inbox.id
    );
    useAlert(t('INBOX_MGMT.ADD.WHATSAPP.BLOOMWIRE_MANAGED.REMOVE.SUCCESS'));
    showConfirm.value = false;
    emit('removed', props.inbox.id);
  } catch (error) {
    // Safe, generic failure message — never a raw backend/Meta error.
    useAlert(t('INBOX_MGMT.ADD.WHATSAPP.BLOOMWIRE_MANAGED.REMOVE.ERROR'));
  } finally {
    isDeleting.value = false;
  }
};
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
              }}:
            </dt>
            <dd data-testid="bloomwire-remove-wa-name">{{ inbox.name }}</dd>
          </div>
          <div class="flex gap-2">
            <dt class="text-n-slate-10">
              {{
                $t(
                  'INBOX_MGMT.ADD.WHATSAPP.BLOOMWIRE_MANAGED.REMOVE.NUMBER_LABEL'
                )
              }}:
            </dt>
            <dd data-testid="bloomwire-remove-wa-number">{{ maskedNumber }}</dd>
          </div>
          <div class="flex gap-2">
            <dt class="text-n-slate-10">
              {{
                $t(
                  'INBOX_MGMT.ADD.WHATSAPP.BLOOMWIRE_MANAGED.REMOVE.MODE_LABEL'
                )
              }}:
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
