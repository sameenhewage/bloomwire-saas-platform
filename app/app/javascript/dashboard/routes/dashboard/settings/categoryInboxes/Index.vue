<script setup>
// Phase 17F.1: administrator-only, READ-ONLY "Categories & Inboxes" overview page. It fetches the SAFE DTO from
// GET /bloomwire/category_inbox_overview and composes existing primitives (categories = Teams, their derived
// WhatsApp inboxes, staff, and membership drift) with deep-links to the existing Team/Inbox editors. It performs
// NO writes and never renders provider secrets. The route is admin-only + guarded by canAccessCategoryAdmin; the
// backend controller (admin-only + feature-gated 404) remains the enforcement boundary.
import { computed, onBeforeMount, ref } from 'vue';
import categoryInboxOverviewAPI from 'dashboard/api/bloomwire/categoryInboxOverview';
import BaseSettingsHeader from '../components/BaseSettingsHeader.vue';
import SettingsLayout from '../SettingsLayout.vue';
import InboxSummary from './InboxSummary.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';

const isLoading = ref(false);
const hasError = ref(false);
const categories = ref([]);
const ambiguousInboxes = ref([]);
const unlinkedInboxes = ref([]);
const derivationNote = ref('');

const isEmpty = computed(
  () =>
    !categories.value.length &&
    !ambiguousInboxes.value.length &&
    !unlinkedInboxes.value.length
);

const teamRoute = id => ({
  name: 'settings_teams_edit',
  params: { teamId: id },
});

const agentsRoute = { name: 'agent_list' };

const matchedTeamNames = inbox =>
  (inbox.matched_teams ?? []).map(team => team.name).join(', ');

const fetchOverview = async () => {
  if (isLoading.value) return;

  isLoading.value = true;
  hasError.value = false;
  try {
    const { data } = await categoryInboxOverviewAPI.get();
    categories.value = data.categories ?? [];
    ambiguousInboxes.value = data.ambiguous_inboxes ?? [];
    unlinkedInboxes.value = data.unlinked_inboxes ?? [];
    derivationNote.value = data.derivation?.note ?? '';
  } catch {
    hasError.value = true;
  } finally {
    isLoading.value = false;
  }
};

onBeforeMount(fetchOverview);
</script>

<template>
  <SettingsLayout
    :is-loading="isLoading"
    :loading-message="$t('CATEGORY_INBOX_OVERVIEW.LOADING')"
    :no-records-found="!isLoading && !hasError && isEmpty"
    :no-records-message="$t('CATEGORY_INBOX_OVERVIEW.EMPTY')"
  >
    <template #header>
      <BaseSettingsHeader
        :title="$t('CATEGORY_INBOX_OVERVIEW.TITLE')"
        :description="$t('CATEGORY_INBOX_OVERVIEW.DESCRIPTION')"
      />
    </template>
    <template #body>
      <div
        v-if="hasError"
        data-testid="overview-error"
        class="flex items-center justify-between gap-3 p-3 rounded-lg bg-n-ruby-2 text-n-ruby-11"
      >
        <div class="flex items-center gap-2">
          <Icon icon="i-lucide-triangle-alert" class="size-4 flex-shrink-0" />
          <span class="text-body-main">
            {{ $t('CATEGORY_INBOX_OVERVIEW.ERROR') }}
          </span>
        </div>
        <button
          type="button"
          data-testid="overview-retry"
          class="text-label-small font-medium text-n-ruby-12 hover:underline"
          @click="fetchOverview"
        >
          {{ $t('CATEGORY_INBOX_OVERVIEW.RETRY') }}
        </button>
      </div>

      <template v-else>
        <p
          v-if="derivationNote"
          data-testid="derivation-note"
          class="mb-4 p-3 rounded-lg bg-n-slate-2 text-n-slate-11 text-label-small"
        >
          {{ derivationNote }}
        </p>

        <div class="flex justify-end mb-4">
          <router-link
            :to="agentsRoute"
            data-testid="agents-link"
            class="text-label-small text-n-blue-11 hover:underline"
          >
            {{ $t('CATEGORY_INBOX_OVERVIEW.MANAGE_AGENTS') }}
          </router-link>
        </div>

        <section
          v-for="category in categories"
          :key="category.id"
          data-testid="category-row"
          class="flex flex-col gap-3 mb-4 p-4 border border-n-weak rounded-xl"
        >
          <div class="flex items-center justify-between gap-3">
            <div class="flex items-center gap-2 min-w-0">
              <Icon
                icon="i-lucide-folder"
                class="size-4 text-n-slate-11 flex-shrink-0"
              />
              <h3 class="text-heading-2 text-n-slate-12 truncate">
                {{ category.name }}
              </h3>
              <span class="text-label-small text-n-slate-11 flex-shrink-0">
                {{
                  $t('CATEGORY_INBOX_OVERVIEW.CATEGORY.STAFF', {
                    count: category.staff.length,
                  })
                }}
              </span>
            </div>
            <router-link
              :to="teamRoute(category.id)"
              class="text-label-small text-n-blue-11 hover:underline flex-shrink-0"
            >
              {{ $t('CATEGORY_INBOX_OVERVIEW.CATEGORY.MANAGE_TEAM') }}
            </router-link>
          </div>

          <div
            v-if="!category.has_inbox"
            data-testid="category-no-inbox"
            class="flex items-center gap-2 p-2 rounded-md bg-n-amber-2 text-n-amber-11 text-label-small"
          >
            <Icon icon="i-lucide-triangle-alert" class="size-4 flex-shrink-0" />
            <span>{{ $t('CATEGORY_INBOX_OVERVIEW.CATEGORY.NO_INBOX') }}</span>
          </div>

          <div v-else class="grid gap-2">
            <InboxSummary
              v-for="inbox in category.derived_inboxes"
              :key="inbox.id"
              :inbox="inbox"
            />
          </div>
        </section>

        <section
          v-if="ambiguousInboxes.length"
          data-testid="ambiguous-section"
          class="flex flex-col gap-3 mb-4 p-4 border border-n-amber-6 rounded-xl bg-n-amber-1"
        >
          <div class="flex items-center gap-2">
            <Icon
              icon="i-lucide-triangle-alert"
              class="size-4 text-n-amber-11 flex-shrink-0"
            />
            <h3 class="text-heading-2 text-n-slate-12">
              {{ $t('CATEGORY_INBOX_OVERVIEW.AMBIGUOUS.TITLE') }}
            </h3>
          </div>
          <p class="text-label-small text-n-slate-11">
            {{ $t('CATEGORY_INBOX_OVERVIEW.AMBIGUOUS.DESCRIPTION') }}
          </p>
          <div class="grid gap-2">
            <div
              v-for="inbox in ambiguousInboxes"
              :key="inbox.id"
              class="grid gap-2"
            >
              <InboxSummary :inbox="inbox" />
              <p class="text-label-small text-n-amber-11 px-3">
                {{
                  $t('CATEGORY_INBOX_OVERVIEW.AMBIGUOUS.MATCHES', {
                    teams: matchedTeamNames(inbox),
                  })
                }}
              </p>
            </div>
          </div>
        </section>

        <section
          v-if="unlinkedInboxes.length"
          data-testid="unlinked-section"
          class="flex flex-col gap-3 mb-4 p-4 border border-dashed border-n-weak rounded-xl"
        >
          <div class="flex items-center gap-2">
            <Icon
              icon="i-lucide-unlink"
              class="size-4 text-n-slate-11 flex-shrink-0"
            />
            <h3 class="text-heading-2 text-n-slate-12">
              {{ $t('CATEGORY_INBOX_OVERVIEW.UNLINKED.TITLE') }}
            </h3>
          </div>
          <p class="text-label-small text-n-slate-11">
            {{ $t('CATEGORY_INBOX_OVERVIEW.UNLINKED.DESCRIPTION') }}
          </p>
          <div class="grid gap-2">
            <InboxSummary
              v-for="inbox in unlinkedInboxes"
              :key="inbox.id"
              :inbox="inbox"
            />
          </div>
        </section>
      </template>
    </template>
  </SettingsLayout>
</template>
