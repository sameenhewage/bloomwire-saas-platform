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
// Only an explicit action_required setup (backend surfaces the action_required block) is recheckable permission
// work — another non-routeable status (blocked/pending/…) must NOT show the Meta-grant panel.
const isActionRequired = computed(
  () => status.value?.managed === true && Boolean(status.value?.action_required)
);
const isReady = computed(
  () => status.value?.managed === true && status.value?.ready === true
);
// "Disconnect" state: the number was deregistered on Meta (verified) and the records are KEPT
// (setup.status === 'disconnected'), so the owner reconnects via Add Inbox (same records are reused).
const isDisconnected = computed(
  () =>
    status.value?.managed === true &&
    status.value?.setup?.status === 'disconnected'
);
// Coexistence numbers cannot be Cloud-API deregistered from here — the owner offboards from the WhatsApp Business
// app. We detect it from the (non-secret) provider_config marker and also honor a backend mobile_action_required.
const isCoexistence = computed(
  () => props.inbox?.provider_config?.connection_mode === 'coexistence'
);
const isDisconnecting = ref(false);
const confirmingDisconnect = ref(false);
// Truthful disconnect outcomes: mobile-action needed (coexistence / backend-enforced) and "couldn't confirm"
// (Standard verification failed → nothing changed locally). Never a false "disconnected".
const mobileActionRequired = ref(false);
const disconnectFailed = ref(false);
// Coexistence offboarding is reconciled by Bloomwire when Meta delivers the account_update / PARTNER_REMOVED
// webhook (the authoritative owner). The mobile-action panel only REFRESHES the persisted status: 'idle' |
// 'still_connected' (persisted status still shows the number connected — the removal has not been reported yet) |
// 'failed' (the refresh itself could not complete). It never asks Meta and never self-declares disconnected.
const isRefreshingStatus = ref(false);
const refreshStatusResult = ref('idle');

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

// Stale-response guard: switching inboxes can leave an earlier request in flight. Each load captures the inbox
// it was issued for plus a monotonically increasing token; a resolved/rejected request is applied ONLY when it
// is still the latest load AND the displayed inbox is unchanged. Without this a late Inbox-A response could
// overwrite Inbox B (and Recheck could then target Inbox A's setup).
let latestRequestToken = 0;

const loadStatus = async () => {
  const requestedInboxId = props.inbox?.id;
  latestRequestToken += 1;
  const requestToken = latestRequestToken;
  // Clear immediately so nothing from the previous inbox lingers while the new request loads. ALL disconnect UI
  // state is per-inbox and MUST reset here: the mobile-action block is the top-level v-if, so a stale
  // mobileActionRequired from Coexistence Inbox A would otherwise hide Standard/non-managed Inbox B's real status.
  status.value = null;
  recheckState.value = 'idle';
  isRechecking.value = false;
  mobileActionRequired.value = false;
  disconnectFailed.value = false;
  confirmingDisconnect.value = false;
  isDisconnecting.value = false;
  refreshStatusResult.value = 'idle';
  isRefreshingStatus.value = false;
  if (!shouldQuery.value || !requestedInboxId) return;

  const isCurrent = () =>
    requestToken === latestRequestToken && props.inbox?.id === requestedInboxId;
  try {
    const dto = await store.dispatch(
      'inboxes/fetchBloomwireWhatsAppCapability',
      { inboxId: requestedInboxId }
    );
    if (isCurrent()) status.value = dto;
  } catch (error) {
    if (isCurrent()) status.value = null;
  }
};

const recheck = async () => {
  const targetSetupId = setupId.value;
  const requestedInboxId = props.inbox?.id;
  const requestToken = latestRequestToken;
  if (!targetSetupId || isRechecking.value) return;
  isRechecking.value = true;
  recheckState.value = 'idle';

  // Bound to the load generation + inbox that owned the setup; a switch mid-recheck (which re-runs loadStatus
  // and bumps the token) makes this result stale so it can never overwrite the newly displayed inbox.
  const isCurrent = () =>
    requestToken === latestRequestToken && props.inbox?.id === requestedInboxId;
  try {
    const dto = await store.dispatch(
      'inboxes/recheckBloomwireWhatsAppCapability',
      { setupId: targetSetupId }
    );
    if (!isCurrent()) return;
    status.value = dto;
    recheckState.value = dto?.ready ? 'idle' : 'still_pending';
  } catch (error) {
    if (isCurrent()) recheckState.value = 'failed';
  } finally {
    if (isCurrent()) isRechecking.value = false;
  }
};

// Disconnect entry point. Coexistence never calls the backend — it shows the exact mobile offboarding path and
// leaves local state untouched (Bloomwire reflects the change after Meta confirms it). Standard shows the 2-step
// confirm before any dispatch.
const startDisconnect = () => {
  disconnectFailed.value = false;
  if (isCoexistence.value) {
    mobileActionRequired.value = true;
    return;
  }
  confirmingDisconnect.value = true;
};

// Standard "Disconnect": the backend deregisters on Meta and only marks local state disconnected AFTER Meta
// authoritatively confirms it. Bound to the displayed inbox so a mid-request switch can't apply a stale result.
// We NEVER flip to a local "disconnected" on our own — only an authoritative DTO does. A backend-enforced
// mobile_action_required (stale frontend mode) shows the mobile path; any other failure shows a safe "couldn't
// confirm" (nothing changed, retryable) — never a false success.
const disconnect = async () => {
  const requestedInboxId = props.inbox?.id;
  if (!requestedInboxId || isDisconnecting.value) return;
  isDisconnecting.value = true;
  disconnectFailed.value = false;
  try {
    const dto = await store.dispatch('inboxes/disconnectBloomwireWhatsApp', {
      inboxId: requestedInboxId,
    });
    if (props.inbox?.id === requestedInboxId) {
      status.value = dto;
      confirmingDisconnect.value = false;
    }
  } catch (error) {
    if (props.inbox?.id !== requestedInboxId) return;
    confirmingDisconnect.value = false;
    if (error?.response?.data?.code === 'mobile_action_required') {
      mobileActionRequired.value = true;
    } else {
      disconnectFailed.value = true;
    }
  } finally {
    if (props.inbox?.id === requestedInboxId) isDisconnecting.value = false;
  }
};

// Refresh the PERSISTED offboarding status. Coexistence offboarding is reconciled by Bloomwire when Meta delivers
// the account_update / PARTNER_REMOVED webhook (the authoritative owner) — this button NEVER asks Meta and NEVER
// self-declares disconnected from an inverse predicate. It re-reads the persisted status: once the webhook has
// marked the setup disconnected the panel flips to the disconnected view; otherwise it shows a truthful
// "not detected yet" note. Bound to the displayed inbox + load generation so a mid-refresh inbox switch can never
// apply a stale result to another inbox.
const refreshDisconnectStatus = async () => {
  const requestedInboxId = props.inbox?.id;
  const requestToken = latestRequestToken;
  if (!requestedInboxId || isRefreshingStatus.value) return;
  isRefreshingStatus.value = true;
  refreshStatusResult.value = 'idle';

  const isCurrent = () =>
    requestToken === latestRequestToken && props.inbox?.id === requestedInboxId;
  try {
    const dto = await store.dispatch(
      'inboxes/fetchBloomwireWhatsAppCapability',
      { inboxId: requestedInboxId }
    );
    if (!isCurrent()) return;
    status.value = dto;
    // Only an authoritative persisted 'disconnected' (set by the PARTNER_REMOVED webhook) flips the panel.
    if (dto?.setup?.status === 'disconnected') {
      mobileActionRequired.value = false;
    } else {
      refreshStatusResult.value = 'still_connected';
    }
  } catch (error) {
    if (isCurrent()) refreshStatusResult.value = 'failed';
  } finally {
    if (isCurrent()) isRefreshingStatus.value = false;
  }
};

onMounted(loadStatus);
// Reload when the inbox changes OR when the admin capability gate hydrates AFTER mount: on a refresh / re-login
// canSelfServeManagedWhatsapp can be false initially (account payload not yet loaded), so the first load is
// skipped until it flips true — without this the durable panel would never appear until a remount.
watch([() => props.inbox?.id, shouldQuery], loadStatus);
</script>

<template>
  <!-- Mobile offboarding (Coexistence / backend-enforced): the exact WhatsApp Business app path. No local state is
       changed — Bloomwire reflects the disconnect once Meta confirms it. -->
  <div
    v-if="mobileActionRequired"
    data-testid="bloomwire-wa-status-mobile-action-required"
    class="flex flex-col items-start p-4 mb-4 rounded-xl border border-n-weak bg-n-alpha-1"
  >
    <div class="flex gap-2 items-center mb-2">
      <Icon icon="i-lucide-smartphone" class="size-5 text-n-amber-10" />
      <h4 class="text-sm font-medium text-n-slate-12">
        {{
          $t(
            'INBOX_MGMT.ADD.WHATSAPP.BLOOMWIRE_MANAGED.DISCONNECT.MOBILE_ACTION_TITLE'
          )
        }}
      </h4>
    </div>
    <p class="mb-2 text-sm leading-6 text-n-slate-11">
      {{
        $t(
          'INBOX_MGMT.ADD.WHATSAPP.BLOOMWIRE_MANAGED.DISCONNECT.MOBILE_ACTION_INSTRUCTIONS'
        )
      }}
    </p>
    <p class="mb-3 text-sm leading-6 text-n-slate-11">
      {{
        $t(
          'INBOX_MGMT.ADD.WHATSAPP.BLOOMWIRE_MANAGED.DISCONNECT.MOBILE_ACTION_DETAIL'
        )
      }}
    </p>

    <!-- Coexistence offboarding is reconciled automatically when Meta notifies Bloomwire (account_update /
         PARTNER_REMOVED). This button only REFRESHES the persisted status: once the webhook has marked the number
         disconnected the panel flips to the disconnected view; otherwise it shows a truthful "not detected yet"
         note. It never asks Meta and never self-declares disconnected. -->
    <p
      v-if="refreshStatusResult === 'still_connected'"
      data-testid="bloomwire-wa-status-mobile-still-connected"
      class="mb-3 text-sm text-n-amber-11"
    >
      {{
        $t(
          'INBOX_MGMT.ADD.WHATSAPP.BLOOMWIRE_MANAGED.DISCONNECT.MOBILE_STILL_CONNECTED'
        )
      }}
    </p>
    <p
      v-else-if="refreshStatusResult === 'failed'"
      data-testid="bloomwire-wa-status-mobile-refresh-failed"
      class="mb-3 text-sm text-n-ruby-11"
    >
      {{
        $t(
          'INBOX_MGMT.ADD.WHATSAPP.BLOOMWIRE_MANAGED.DISCONNECT.MOBILE_REFRESH_FAILED'
        )
      }}
    </p>

    <NextButton
      solid
      teal
      data-testid="bloomwire-wa-status-mobile-refresh"
      :is-loading="isRefreshingStatus"
      :disabled="isRefreshingStatus"
      :label="
        $t(
          'INBOX_MGMT.ADD.WHATSAPP.BLOOMWIRE_MANAGED.DISCONNECT.MOBILE_REFRESH_BUTTON'
        )
      "
      @click="refreshDisconnectStatus"
    />
  </div>

  <div
    v-else-if="isActionRequired"
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
    class="flex flex-col items-start p-4 mb-4 rounded-xl border border-n-weak bg-n-alpha-1"
  >
    <div class="flex gap-2 items-center">
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

    <!-- Truthful failure: Meta could not confirm the disconnect, so nothing was changed. Retryable, no raw error. -->
    <div
      v-if="disconnectFailed"
      data-testid="bloomwire-wa-status-disconnect-failed"
      class="mt-4 w-full rounded-lg border border-n-weak p-3"
    >
      <p class="text-sm font-medium text-n-ruby-11">
        {{
          $t(
            'INBOX_MGMT.ADD.WHATSAPP.BLOOMWIRE_MANAGED.DISCONNECT.FAILED_TITLE'
          )
        }}
      </p>
      <p class="text-sm text-n-slate-11">
        {{
          $t(
            'INBOX_MGMT.ADD.WHATSAPP.BLOOMWIRE_MANAGED.DISCONNECT.FAILED_DETAIL'
          )
        }}
      </p>
    </div>

    <template v-if="confirmingDisconnect">
      <p
        data-testid="bloomwire-wa-status-disconnect-confirm"
        class="mt-4 mb-2 text-sm text-n-slate-11"
      >
        {{ $t('INBOX_MGMT.ADD.WHATSAPP.BLOOMWIRE_MANAGED.DISCONNECT.CONFIRM') }}
      </p>
      <div class="flex gap-2">
        <NextButton
          solid
          ruby
          data-testid="bloomwire-wa-status-disconnect-confirm-button"
          :is-loading="isDisconnecting"
          :disabled="isDisconnecting"
          :label="
            $t(
              'INBOX_MGMT.ADD.WHATSAPP.BLOOMWIRE_MANAGED.DISCONNECT.CONFIRM_BUTTON'
            )
          "
          @click="disconnect"
        />
        <NextButton
          faded
          slate
          :disabled="isDisconnecting"
          :label="
            $t('INBOX_MGMT.ADD.WHATSAPP.BLOOMWIRE_MANAGED.DISCONNECT.CANCEL')
          "
          @click="confirmingDisconnect = false"
        />
      </div>
    </template>
    <NextButton
      v-else
      faded
      ruby
      class="mt-4"
      data-testid="bloomwire-wa-status-disconnect"
      :label="$t('INBOX_MGMT.ADD.WHATSAPP.BLOOMWIRE_MANAGED.DISCONNECT.BUTTON')"
      @click="startDisconnect"
    />
  </div>

  <div
    v-else-if="isDisconnected"
    data-testid="bloomwire-wa-status-disconnected"
    class="flex flex-col items-start p-4 mb-4 rounded-xl border border-n-weak bg-n-alpha-1"
  >
    <div class="flex gap-2 items-center mb-2">
      <Icon icon="i-lucide-plug-zap" class="size-5 text-n-amber-10" />
      <h4 class="text-sm font-medium text-n-slate-12">
        {{
          $t(
            'INBOX_MGMT.ADD.WHATSAPP.BLOOMWIRE_MANAGED.DISCONNECT.DISCONNECTED_TITLE'
          )
        }}
      </h4>
    </div>
    <p class="text-sm leading-6 text-n-slate-11">
      {{
        $t(
          'INBOX_MGMT.ADD.WHATSAPP.BLOOMWIRE_MANAGED.DISCONNECT.DISCONNECTED_SUBTITLE'
        )
      }}
    </p>
  </div>
</template>
