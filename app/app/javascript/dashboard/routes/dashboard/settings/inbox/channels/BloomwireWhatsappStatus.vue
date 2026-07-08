<script setup>
/**
 * Phase 5 (resume) — DURABLE managed-WhatsApp outbound-capability status for the Inbox Settings surface.
 *
 * Unlike the transient post-onboarding wizard panel, this loads the PERSISTED capability status from the backend
 * on every mount (and whenever the inbox changes), so an Action-Required inbox is always resumable — it survives
 * refresh, navigation and re-login. Admin-gated (canSelfServeManagedWhatsapp; the backend also enforces) and only
 * queried for a Bloomwire-managed WhatsApp inbox. The Recheck action reuses the EXISTING setup (same Channel /
 * Inbox / Setup ids) — never a reconnect, duplicate, or /register — and, once the owner has granted the Meta task,
 * subscribes + promotes it to ready. The copy differs by the sanitized reason (BLOCKER 4): a verified-missing task
 * shows the grant step; an unverifiable / activation-incomplete state shows a neutral "couldn't verify, retry" and
 * never claims the permission is missing. No secret / token / raw actor id is ever read or rendered.
 */
import { ref, computed, onMounted, watch } from 'vue';
import { useStore } from 'dashboard/composables/store';
import { useBloomwireCapabilities } from 'dashboard/composables/useBloomwireCapabilities';
import NextButton from 'dashboard/components-next/button/Button.vue';
import Icon from 'next/icon/Icon.vue';

const props = defineProps({
  inbox: {
    type: Object,
    required: true,
  },
});

const store = useStore();
const { canSelfServeManagedWhatsapp } = useBloomwireCapabilities();

const status = ref(null);
const isRechecking = ref(false);
// 'idle' | 'still_pending' (recheck ran, inbox still not active) | 'failed' (recheck itself could not complete).
const recheckState = ref('idle');

const isManagedInbox = computed(
  () => props.inbox?.provider_config?.source === 'bloomwire_managed'
);
const shouldQuery = computed(
  () => isManagedInbox.value && canSelfServeManagedWhatsapp.value
);
const setupId = computed(() => status.value?.setup?.id);
const isActionRequired = computed(
  () => status.value?.managed === true && status.value?.ready === false
);
const isReady = computed(
  () => status.value?.managed === true && status.value?.ready === true
);

const actionReasonKey = computed(() => {
  switch (status.value?.action_required?.reason) {
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

const loadStatus = async () => {
  if (!shouldQuery.value || !props.inbox?.id) {
    status.value = null;
    return;
  }
  try {
    status.value = await store.dispatch(
      'inboxes/fetchBloomwireWhatsAppCapability',
      { inboxId: props.inbox.id }
    );
  } catch (error) {
    status.value = null;
  }
};

const recheck = async () => {
  if (!setupId.value || isRechecking.value) return;
  isRechecking.value = true;
  recheckState.value = 'idle';
  try {
    const dto = await store.dispatch(
      'inboxes/recheckBloomwireWhatsAppCapability',
      { setupId: setupId.value }
    );
    status.value = dto;
    recheckState.value = dto?.ready ? 'idle' : 'still_pending';
  } catch (error) {
    recheckState.value = 'failed';
  } finally {
    isRechecking.value = false;
  }
};

onMounted(loadStatus);
watch(() => props.inbox?.id, loadStatus);
</script>

<template>
  <div
    v-if="isActionRequired"
    data-testid="bloomwire-wa-status-action-required"
    class="flex flex-col items-start p-4 mb-4 rounded-xl border border-n-weak bg-n-alpha-1"
  >
    <div class="flex gap-2 items-center mb-2">
      <Icon icon="i-lucide-triangle-alert" class="size-5 text-n-amber-10" />
      <h4 class="text-sm font-medium text-n-slate-12">
        {{
          $t('INBOX_MGMT.ADD.WHATSAPP.BLOOMWIRE_MANAGED.ACTION_REQUIRED.TITLE')
        }}
      </h4>
    </div>
    <p class="mb-4 text-sm leading-6 text-n-slate-11">
      {{
        $t('INBOX_MGMT.ADD.WHATSAPP.BLOOMWIRE_MANAGED.ACTION_REQUIRED.SUBTITLE')
      }}
    </p>

    <div
      v-if="showGrantStep"
      data-testid="bloomwire-wa-status-grant-step"
      class="p-4 mb-4 w-full rounded-lg border border-n-weak"
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

    <p
      data-testid="bloomwire-wa-status-reason"
      class="mb-3 text-sm text-n-slate-11"
    >
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
      data-testid="bloomwire-wa-status-pending"
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
      data-testid="bloomwire-wa-status-failed"
      class="mb-3 text-sm text-n-ruby-11"
    >
      {{
        $t(
          'INBOX_MGMT.ADD.WHATSAPP.BLOOMWIRE_MANAGED.ACTION_REQUIRED.RECHECK_FAILED'
        )
      }}
    </p>

    <NextButton
      solid
      teal
      data-testid="bloomwire-wa-status-recheck"
      :is-loading="isRechecking"
      :disabled="isRechecking"
      :label="
        $t(
          'INBOX_MGMT.ADD.WHATSAPP.BLOOMWIRE_MANAGED.ACTION_REQUIRED.RECHECK_BUTTON'
        )
      "
      @click="recheck"
    />
  </div>

  <div
    v-else-if="isReady"
    data-testid="bloomwire-wa-status-ready"
    class="flex gap-2 items-center p-4 mb-4 rounded-xl border border-n-weak bg-n-alpha-1"
  >
    <Icon icon="i-lucide-circle-check" class="size-5 text-n-teal-10" />
    <div>
      <p class="text-sm font-medium text-n-slate-12">
        {{
          $t(
            'INBOX_MGMT.ADD.WHATSAPP.BLOOMWIRE_MANAGED.ACTION_REQUIRED.READY_TITLE'
          )
        }}
      </p>
      <p class="text-sm text-n-slate-11">
        {{
          $t(
            'INBOX_MGMT.ADD.WHATSAPP.BLOOMWIRE_MANAGED.ACTION_REQUIRED.READY_SUBTITLE'
          )
        }}
      </p>
    </div>
  </div>
</template>
