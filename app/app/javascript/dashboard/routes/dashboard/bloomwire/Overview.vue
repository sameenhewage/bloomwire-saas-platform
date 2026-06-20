<script setup>
import { ref, computed, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAccount } from 'dashboard/composables/useAccount';
import ConversationAPI from 'dashboard/api/inbox/conversation';
import ContactAPI from 'dashboard/api/contacts';
import ChannelIcon from 'next/icon/ChannelIcon.vue';
import Button from 'dashboard/components-next/button/Button.vue';

const { t } = useI18n();
const store = useStore();
const { currentAccount, accountScopedRoute } = useAccount();

const inboxes = useMapGetter('inboxes/getInboxes');

const CONVERSATION_STATUSES = ['open', 'resolved', 'pending', 'snoozed'];

const openConversations = ref(null);
const totalConversations = ref(null);
const contactsCount = ref(null);
const isLoading = ref(true);

const accountName = computed(
  () => currentAccount.value?.name || t('BLOOMWIRE.OVERVIEW.PLACEHOLDER')
);
const channelsCount = computed(() => inboxes.value?.length ?? 0);

const formatCount = value =>
  value === null || value === undefined
    ? t('BLOOMWIRE.OVERVIEW.PLACEHOLDER')
    : value;

const summaryCards = computed(() => [
  {
    key: 'account',
    label: t('BLOOMWIRE.OVERVIEW.CARDS.ACCOUNT_NAME'),
    value: accountName.value,
    icon: 'i-lucide-building-2',
  },
  {
    key: 'channels',
    label: t('BLOOMWIRE.OVERVIEW.CARDS.CHANNELS'),
    value: formatCount(channelsCount.value),
    icon: 'i-lucide-mailbox',
  },
  {
    key: 'open',
    label: t('BLOOMWIRE.OVERVIEW.CARDS.OPEN_CONVERSATIONS'),
    value: formatCount(openConversations.value),
    icon: 'i-lucide-message-circle',
  },
  {
    key: 'total',
    label: t('BLOOMWIRE.OVERVIEW.CARDS.TOTAL_CONVERSATIONS'),
    value: formatCount(totalConversations.value),
    icon: 'i-lucide-messages-square',
  },
  {
    key: 'contacts',
    label: t('BLOOMWIRE.OVERVIEW.CARDS.CONTACTS'),
    value: formatCount(contactsCount.value),
    icon: 'i-lucide-contact',
  },
]);

const channelType = inbox =>
  (inbox.channel_type || '').replace('Channel::', '') ||
  t('BLOOMWIRE.OVERVIEW.PLACEHOLDER');

const fetchConversationCounts = async () => {
  try {
    const responses = await Promise.all(
      CONVERSATION_STATUSES.map(status => ConversationAPI.meta({ status }))
    );
    const counts = responses.map(
      response => response?.data?.meta?.all_count || 0
    );
    [openConversations.value] = counts;
    totalConversations.value = counts.reduce((sum, count) => sum + count, 0);
  } catch (error) {
    openConversations.value = null;
    totalConversations.value = null;
  }
};

const fetchContactsCount = async () => {
  try {
    const { data } = await ContactAPI.get(1);
    contactsCount.value = data?.meta?.count ?? null;
  } catch (error) {
    contactsCount.value = null;
  }
};

onMounted(async () => {
  store.dispatch('inboxes/get');
  await Promise.all([fetchConversationCounts(), fetchContactsCount()]);
  isLoading.value = false;
});
</script>

<template>
  <main class="flex flex-col w-full h-full overflow-y-auto bg-n-background">
    <div class="flex flex-col gap-6 p-6 mx-auto w-full max-w-5xl">
      <header class="flex flex-col gap-2">
        <div class="flex flex-wrap gap-3 items-center">
          <h1 class="text-xl font-semibold text-n-slate-12">
            {{ accountName }}
          </h1>
          <span
            class="inline-flex gap-1.5 items-center px-2 py-0.5 text-xs font-medium rounded-full text-n-teal-11 bg-n-teal-3"
          >
            <span class="rounded-full size-1.5 bg-n-teal-9" />
            {{ t('BLOOMWIRE.OVERVIEW.STATUS_CONNECTED') }}
          </span>
        </div>
        <p class="text-sm text-n-slate-11">
          {{ t('BLOOMWIRE.OVERVIEW.SUBTITLE') }}
        </p>
      </header>

      <section
        class="grid grid-cols-1 gap-3 sm:grid-cols-2 lg:grid-cols-3"
        aria-busy="true"
      >
        <div
          v-for="card in summaryCards"
          :key="card.key"
          class="flex flex-col gap-2 p-4 rounded-xl outline outline-1 bg-n-solid-1 outline-n-weak"
        >
          <div class="flex gap-2 items-center text-n-slate-11">
            <span :class="card.icon" class="size-4" />
            <span class="text-xs font-medium uppercase tracking-wide">
              {{ card.label }}
            </span>
          </div>
          <span class="text-lg font-semibold truncate text-n-slate-12">
            {{ card.value }}
          </span>
        </div>
      </section>

      <section
        class="flex flex-col rounded-xl divide-y outline outline-1 bg-n-solid-1 outline-n-weak divide-n-weak"
      >
        <div class="flex justify-between items-center px-4 py-3">
          <h2 class="text-sm font-medium text-n-slate-12">
            {{ t('BLOOMWIRE.OVERVIEW.CHANNELS.TITLE') }}
          </h2>
          <span class="text-xs text-n-slate-10">{{ channelsCount }}</span>
        </div>
        <p
          v-if="!channelsCount"
          class="px-4 py-6 text-sm text-center text-n-slate-10"
        >
          {{ t('BLOOMWIRE.OVERVIEW.CHANNELS.EMPTY') }}
        </p>
        <template v-else>
          <div
            v-for="inbox in inboxes"
            :key="inbox.name"
            class="flex gap-3 items-center px-4 py-3"
          >
            <ChannelIcon :inbox="inbox" class="size-4 text-n-slate-11" />
            <span class="flex-grow text-sm truncate text-n-slate-12">
              {{ inbox.name }}
            </span>
            <span
              class="px-2 py-0.5 text-xs rounded-md text-n-slate-11 bg-n-alpha-2"
            >
              {{ channelType(inbox) }}
            </span>
          </div>
        </template>
      </section>

      <section
        class="flex flex-col gap-3 p-4 rounded-xl outline outline-1 bg-n-solid-1 outline-n-weak"
      >
        <h2 class="text-sm font-medium text-n-slate-12">
          {{ t('BLOOMWIRE.OVERVIEW.ABOUT.TITLE') }}
        </h2>
        <p class="text-sm leading-relaxed text-n-slate-11">
          {{ t('BLOOMWIRE.OVERVIEW.ABOUT.CHATWOOT') }}
        </p>
        <p class="text-sm leading-relaxed text-n-slate-11">
          {{ t('BLOOMWIRE.OVERVIEW.ABOUT.BLOOMWIRE') }}
        </p>
      </section>

      <section class="flex flex-wrap gap-3 justify-between items-center">
        <p class="text-sm text-n-slate-11">
          {{ t('BLOOMWIRE.OVERVIEW.CTA.HINT') }}
        </p>
        <RouterLink :to="accountScopedRoute('home')">
          <Button
            icon="i-lucide-inbox"
            :label="t('BLOOMWIRE.OVERVIEW.CTA.OPEN_INBOX')"
            size="sm"
          />
        </RouterLink>
      </section>
    </div>
  </main>
</template>
