<script setup>
// Phase 17F.1: read-only summary row for a single inbox inside the "Categories & Inboxes" overview. Presentational
// only — it renders the SAFE DTO from Bloomwire::CategoryInboxOverview (name, WhatsApp connection-mode badge, setup
// status, collaborator count, membership drift) and a deep-link to the existing inbox editor. It NEVER receives or
// renders provider_config / tokens / secrets, and performs no writes.
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Label from 'dashboard/components-next/label/Label.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';

const props = defineProps({
  inbox: {
    type: Object,
    required: true,
  },
});

const { t } = useI18n();

const isWhatsapp = computed(() => Boolean(props.inbox.whatsapp));

const isCoexistence = computed(
  () => props.inbox.whatsapp?.connection_mode === 'coexistence'
);

const connectionModeLabel = computed(() => {
  if (!isWhatsapp.value) return '';
  return isCoexistence.value
    ? t('CATEGORY_INBOX_OVERVIEW.CONNECTION_MODE.COEXISTENCE')
    : t('CATEGORY_INBOX_OVERVIEW.CONNECTION_MODE.STANDARD');
});

const setupStatusLabel = computed(() => {
  if (!isWhatsapp.value) return '';
  const status = props.inbox.whatsapp?.setup_status || 'not_configured';
  return t(`CATEGORY_INBOX_OVERVIEW.SETUP_STATUS.${status.toUpperCase()}`);
});

const relationshipStatus = computed(
  () => props.inbox.relationship_status || ''
);

const relationshipStatusLabel = computed(() => {
  if (!relationshipStatus.value) return '';
  return t(
    `CATEGORY_INBOX_OVERVIEW.RELATIONSHIP.${relationshipStatus.value.toUpperCase()}`
  );
});

const relationshipColor = computed(() => {
  if (relationshipStatus.value === 'ambiguous') return 'amber';
  if (relationshipStatus.value === 'unlinked') return 'ruby';
  return 'teal';
});

const collaboratorCount = computed(
  () => props.inbox.collaborators?.length ?? 0
);

const inboxRoute = computed(() => ({
  name: 'settings_inbox_show',
  params: { inboxId: props.inbox.id },
}));

const staffMissing = computed(
  () => props.inbox.drift?.staff_missing_inbox_access ?? []
);
const collaboratorsNotInTeam = computed(
  () => props.inbox.drift?.collaborators_not_in_team ?? []
);
const hasDrift = computed(
  () => staffMissing.value.length > 0 || collaboratorsNotInTeam.value.length > 0
);
</script>

<template>
  <div class="flex flex-col gap-2 p-3 border border-n-weak rounded-lg">
    <div class="flex items-center justify-between gap-3">
      <div class="flex items-center gap-2 min-w-0">
        <Icon
          icon="i-lucide-inbox"
          class="size-4 text-n-slate-11 flex-shrink-0"
        />
        <span class="text-body-main text-n-slate-12 truncate">
          {{ inbox.name }}
        </span>
      </div>
      <div class="flex items-center gap-2 flex-shrink-0">
        <Label
          v-if="relationshipStatusLabel"
          :label="relationshipStatusLabel"
          :color="relationshipColor"
          compact
        />
        <Label
          v-if="isWhatsapp"
          :label="connectionModeLabel"
          :color="isCoexistence ? 'amber' : 'teal'"
          compact
        />
        <Label
          v-if="setupStatusLabel"
          :label="setupStatusLabel"
          color="slate"
          compact
        />
      </div>
    </div>
    <div class="flex items-center justify-between gap-3">
      <span class="text-label-small text-n-slate-11">
        {{
          $t('CATEGORY_INBOX_OVERVIEW.INBOX.COLLABORATORS', {
            count: collaboratorCount,
          })
        }}
      </span>
      <router-link
        :to="inboxRoute"
        class="text-label-small text-n-blue-11 hover:underline flex-shrink-0"
      >
        {{ $t('CATEGORY_INBOX_OVERVIEW.INBOX.MANAGE') }}
      </router-link>
    </div>
    <div
      v-if="hasDrift"
      data-testid="inbox-drift"
      class="flex flex-col gap-1 mt-1 p-2 rounded-md bg-n-amber-2 text-n-amber-11"
    >
      <span v-if="staffMissing.length" class="text-label-small">
        {{
          $t('CATEGORY_INBOX_OVERVIEW.DRIFT.STAFF_MISSING', {
            count: staffMissing.length,
          })
        }}
      </span>
      <span v-if="collaboratorsNotInTeam.length" class="text-label-small">
        {{
          $t('CATEGORY_INBOX_OVERVIEW.DRIFT.COLLABORATORS_EXTRA', {
            count: collaboratorsNotInTeam.length,
          })
        }}
      </span>
    </div>
  </div>
</template>
