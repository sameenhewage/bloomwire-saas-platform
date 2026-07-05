<script setup>
// Phase 17F.3: administrator-guided staff-access alignment preview + confirm dialog. Shows the current Team staff
// and Inbox collaborators and the ADDITIVE diff (who will be added to each side) BEFORE any write. Confirm calls the
// local, transactional alignment endpoint (adds the same users to both the Team and the Inbox); it NEVER removes
// staff, creates no Category↔Inbox mapping, and makes no Meta/WhatsApp call. It renders only the safe {id,name} DTO.
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import categoryInboxAlignmentAPI from 'dashboard/api/bloomwire/categoryInboxAlignment';
import Icon from 'dashboard/components-next/icon/Icon.vue';

const props = defineProps({
  category: { type: Object, required: true },
  inbox: { type: Object, required: true },
});

const emit = defineEmits(['close', 'aligned']);

const { t } = useI18n();

const isSubmitting = ref(false);
const hasError = ref(false);

const teamStaff = computed(() => props.category.staff ?? []);
const inboxStaff = computed(() => props.inbox.collaborators ?? []);
const willAddToInbox = computed(
  () => props.inbox.drift?.staff_missing_inbox_access ?? []
);
const willAddToTeam = computed(
  () => props.inbox.drift?.collaborators_not_in_team ?? []
);

// Additive union of the drift: exactly the users who must be added on one or both sides to remove the drift.
const userIds = computed(() => [
  ...new Set(
    [...willAddToInbox.value, ...willAddToTeam.value].map(user => user.id)
  ),
]);

const nameList = people =>
  people.length
    ? people.map(person => person.name).join(', ')
    : t('CATEGORY_INBOX_OVERVIEW.ALIGN.NONE');

const cancel = () => emit('close');

const confirm = async () => {
  if (isSubmitting.value) return;
  isSubmitting.value = true;
  hasError.value = false;
  try {
    await categoryInboxAlignmentAPI.create({
      team_id: props.category.id,
      inbox_id: props.inbox.id,
      user_ids: userIds.value,
    });
    emit('aligned');
  } catch {
    hasError.value = true;
  } finally {
    isSubmitting.value = false;
  }
};
</script>

<template>
  <div
    class="fixed inset-0 z-50 flex items-center justify-center p-4 bg-n-alpha-black2"
    data-testid="align-dialog"
  >
    <div
      class="flex flex-col w-full max-w-lg gap-4 p-5 rounded-xl bg-n-solid-2 border border-n-weak max-h-[90vh] overflow-y-auto"
    >
      <div class="flex items-start gap-2">
        <Icon
          icon="i-lucide-users"
          class="size-5 text-n-slate-11 flex-shrink-0 mt-0.5"
        />
        <div class="flex flex-col">
          <h3 class="text-heading-2 text-n-slate-12">
            {{ $t('CATEGORY_INBOX_OVERVIEW.ALIGN.TITLE') }}
          </h3>
          <p class="text-label-small text-n-slate-11">
            {{ $t('CATEGORY_INBOX_OVERVIEW.ALIGN.DESCRIPTION') }}
          </p>
        </div>
      </div>

      <div class="grid grid-cols-2 gap-3">
        <div class="flex flex-col gap-1 p-3 rounded-lg bg-n-slate-2">
          <span class="text-label-small font-medium text-n-slate-12">
            {{ $t('CATEGORY_INBOX_OVERVIEW.ALIGN.TEAM') }}
            <span>{{ category.name }}</span>
          </span>
          <span
            data-testid="current-team-staff"
            class="text-label-small text-n-slate-11"
          >
            {{ $t('CATEGORY_INBOX_OVERVIEW.ALIGN.CURRENT_TEAM_STAFF') }}
            <span>{{ nameList(teamStaff) }}</span>
          </span>
        </div>
        <div class="flex flex-col gap-1 p-3 rounded-lg bg-n-slate-2">
          <span class="text-label-small font-medium text-n-slate-12">
            {{ $t('CATEGORY_INBOX_OVERVIEW.ALIGN.INBOX') }}
            <span>{{ inbox.name }}</span>
          </span>
          <span
            data-testid="current-inbox-staff"
            class="text-label-small text-n-slate-11"
          >
            {{ $t('CATEGORY_INBOX_OVERVIEW.ALIGN.CURRENT_INBOX_STAFF') }}
            <span>{{ nameList(inboxStaff) }}</span>
          </span>
        </div>
      </div>

      <div
        class="flex flex-col gap-2 p-3 rounded-lg bg-n-teal-2 text-n-teal-11"
      >
        <span data-testid="will-add-to-inbox" class="text-label-small">
          {{ $t('CATEGORY_INBOX_OVERVIEW.ALIGN.WILL_ADD_TO_INBOX') }}
          <span>{{ nameList(willAddToInbox) }}</span>
        </span>
        <span data-testid="will-add-to-team" class="text-label-small">
          {{ $t('CATEGORY_INBOX_OVERVIEW.ALIGN.WILL_ADD_TO_TEAM') }}
          <span>{{ nameList(willAddToTeam) }}</span>
        </span>
        <span
          data-testid="no-removal-note"
          class="text-label-small font-medium"
        >
          {{ $t('CATEGORY_INBOX_OVERVIEW.ALIGN.NO_REMOVAL') }}
        </span>
      </div>

      <div
        v-if="hasError"
        data-testid="align-error"
        class="flex items-center gap-2 p-2 rounded-md bg-n-ruby-2 text-n-ruby-11 text-label-small"
      >
        <Icon icon="i-lucide-triangle-alert" class="size-4 flex-shrink-0" />
        {{ $t('CATEGORY_INBOX_OVERVIEW.ALIGN.ERROR') }}
      </div>

      <div class="flex items-center justify-end gap-2 mt-1">
        <button
          type="button"
          data-testid="align-cancel"
          class="px-3 py-1.5 rounded-lg text-label-small text-n-slate-12 bg-n-slate-3 hover:bg-n-slate-4"
          @click="cancel"
        >
          {{ $t('CATEGORY_INBOX_OVERVIEW.ALIGN.CANCEL') }}
        </button>
        <button
          type="button"
          data-testid="align-confirm"
          :disabled="isSubmitting"
          class="px-3 py-1.5 rounded-lg text-label-small text-white bg-n-blue-9 hover:bg-n-blue-10 disabled:opacity-60"
          @click="confirm"
        >
          {{ $t('CATEGORY_INBOX_OVERVIEW.ALIGN.CONFIRM') }}
        </button>
      </div>
    </div>
  </div>
</template>
