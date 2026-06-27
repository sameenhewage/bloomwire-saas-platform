<script setup>
import { useStoreGetters, useStore } from 'dashboard/composables/store';
import { computed, onMounted, ref } from 'vue';
import { useBranding } from 'shared/composables/useBranding';
import { useBloomwireCapabilities } from 'dashboard/composables/useBloomwireCapabilities';
import { picoSearch } from '@scmmishra/pico-search';
import IntegrationItem from './IntegrationItem.vue';
import SettingsLayout from '../SettingsLayout.vue';
import BaseSettingsHeader from '../components/BaseSettingsHeader.vue';

const store = useStore();
const getters = useStoreGetters();
const { replaceInstallationName } = useBranding();
// Bloomwire (11B.7E): integrations are Ops-owned in managed mode. Show a managed-by-ops state and skip the
// catalog fetch when blocked; connect/config writes are already 403 server-side (PR #47). The route-level
// beforeEnter guard also redirects direct access — this is the in-page fallback.
const { canAccessIntegrations } = useBloomwireCapabilities();

const searchQuery = ref('');
const uiFlags = getters['integrations/getUIFlags'];

const integrationList = computed(
  () => getters['integrations/getAppIntegrations'].value
);

const filteredIntegrationList = computed(() => {
  const query = searchQuery.value.trim();
  if (!query) return integrationList.value;
  return picoSearch(integrationList.value, query, ['name', 'description']);
});

onMounted(() => {
  if (canAccessIntegrations.value) store.dispatch('integrations/get');
});
</script>

<template>
  <!-- Bloomwire (11B.7E): managed-mode in-page block — integrations are Ops-owned -->
  <div
    v-if="!canAccessIntegrations"
    class="flex flex-col items-center justify-center w-full max-w-lg gap-2 p-8 mx-auto text-center"
  >
    <h3 class="text-heading-2 text-n-slate-12">
      {{ $t('INTEGRATION_SETTINGS.MANAGED_BY_OPS.TITLE') }}
    </h3>
    <p class="text-body-main text-n-slate-11">
      {{ $t('INTEGRATION_SETTINGS.MANAGED_BY_OPS.BODY') }}
    </p>
  </div>
  <SettingsLayout
    v-else
    :is-loading="uiFlags.isFetching"
    :loading-message="$t('INTEGRATION_SETTINGS.LOADING')"
  >
    <template #header>
      <BaseSettingsHeader
        v-model:search-query="searchQuery"
        :title="$t('INTEGRATION_SETTINGS.HEADER')"
        :description="
          replaceInstallationName($t('INTEGRATION_SETTINGS.DESCRIPTION'))
        "
        :link-text="$t('INTEGRATION_SETTINGS.LEARN_MORE')"
        :search-placeholder="$t('INTEGRATION_SETTINGS.SEARCH_PLACEHOLDER')"
        feature-name="integrations"
      />
    </template>
    <template #body>
      <div class="flex-grow flex-shrink overflow-auto">
        <span
          v-if="!filteredIntegrationList.length && searchQuery"
          class="flex-1 flex items-center justify-center py-20 text-center text-body-main !text-base text-n-slate-11"
        >
          {{ $t('INTEGRATION_SETTINGS.NO_RESULTS') }}
        </span>
        <div
          v-else
          class="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-3 gap-4"
        >
          <IntegrationItem
            v-for="item in filteredIntegrationList"
            :id="item.id"
            :key="item.id"
            :logo="item.logo"
            :name="item.name"
            :description="item.description"
            :enabled="item.enabled"
          />
        </div>
      </div>
    </template>
  </SettingsLayout>
</template>
