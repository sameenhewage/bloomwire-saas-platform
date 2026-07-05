<script setup>
import { ref, computed, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';
import { useStore } from 'vuex';
import { useMapGetter } from 'dashboard/composables/store';

import { useAccount } from 'dashboard/composables/useAccount';
import { useBloomwireCapabilities } from 'dashboard/composables/useBloomwireCapabilities';

import ChannelItem from 'dashboard/components/widgets/ChannelItem.vue';
import LoadingState from 'dashboard/components/widgets/LoadingState.vue';
import NextButton from 'next/button/Button.vue';

const { t } = useI18n();
const router = useRouter();
const store = useStore();
const { accountId, currentAccount } = useAccount();
// Bloomwire (11B.6C/11B.7C): hide channel setup entries when Ops-managed (backend still enforces the 403).
// 11B.7C: in managed mode ALL inbox creation is Ops-owned, so even self-service website/api cards are hidden.
const {
  capabilitiesLoaded,
  canManageProviderSetup,
  canManageNativeWhatsappSetup,
  canCreateInbox,
  canSelfServeManagedWhatsapp,
} = useBloomwireCapabilities();

const globalConfig = useMapGetter('globalConfig/get');

// Channels the business/customer admin can always self-serve, even in managed mode.
const SELF_SERVICE_CHANNELS = ['website', 'api'];
// Native WhatsApp setup channels (gated by canManageNativeWhatsappSetup); everything
// else that is not self-service is a provider/external channel (canManageProviderSetup).
const NATIVE_WHATSAPP_CHANNELS = ['whatsapp', 'whatsapp_call'];

const enabledFeatures = ref({});

const hasTiktokConfigured = computed(() => {
  return window.chatwootConfig?.tiktokAppId;
});

const channelList = computed(() => {
  const { apiChannelName } = globalConfig.value;
  const channels = [
    {
      key: 'website',
      title: t('INBOX_MGMT.ADD.AUTH.CHANNEL.WEBSITE.TITLE'),
      description: t('INBOX_MGMT.ADD.AUTH.CHANNEL.WEBSITE.DESCRIPTION'),
      icon: 'i-woot-website',
    },
    {
      key: 'facebook',
      title: t('INBOX_MGMT.ADD.AUTH.CHANNEL.FACEBOOK.TITLE'),
      description: t('INBOX_MGMT.ADD.AUTH.CHANNEL.FACEBOOK.DESCRIPTION'),
      icon: 'i-woot-messenger',
    },
    {
      key: 'whatsapp',
      title: t('INBOX_MGMT.ADD.AUTH.CHANNEL.WHATSAPP.TITLE'),
      description: t('INBOX_MGMT.ADD.AUTH.CHANNEL.WHATSAPP.DESCRIPTION'),
      icon: 'i-woot-whatsapp',
    },
    {
      key: 'sms',
      title: t('INBOX_MGMT.ADD.AUTH.CHANNEL.SMS.TITLE'),
      description: t('INBOX_MGMT.ADD.AUTH.CHANNEL.SMS.DESCRIPTION'),
      icon: 'i-woot-sms',
    },
    {
      key: 'email',
      title: t('INBOX_MGMT.ADD.AUTH.CHANNEL.EMAIL.TITLE'),
      description: t('INBOX_MGMT.ADD.AUTH.CHANNEL.EMAIL.DESCRIPTION'),
      icon: 'i-woot-mail',
    },
    {
      key: 'api',
      title: apiChannelName || t('INBOX_MGMT.ADD.AUTH.CHANNEL.API.TITLE'),
      description: t('INBOX_MGMT.ADD.AUTH.CHANNEL.API.DESCRIPTION'),
      icon: 'i-woot-api',
    },
    {
      key: 'telegram',
      title: t('INBOX_MGMT.ADD.AUTH.CHANNEL.TELEGRAM.TITLE'),
      description: t('INBOX_MGMT.ADD.AUTH.CHANNEL.TELEGRAM.DESCRIPTION'),
      icon: 'i-woot-telegram',
    },
    {
      key: 'line',
      title: t('INBOX_MGMT.ADD.AUTH.CHANNEL.LINE.TITLE'),
      description: t('INBOX_MGMT.ADD.AUTH.CHANNEL.LINE.DESCRIPTION'),
      icon: 'i-woot-line',
    },
    {
      key: 'instagram',
      title: t('INBOX_MGMT.ADD.AUTH.CHANNEL.INSTAGRAM.TITLE'),
      description: t('INBOX_MGMT.ADD.AUTH.CHANNEL.INSTAGRAM.DESCRIPTION'),
      icon: 'i-woot-instagram',
    },
  ];

  if (hasTiktokConfigured.value) {
    channels.push({
      key: 'tiktok',
      title: t('INBOX_MGMT.ADD.AUTH.CHANNEL.TIKTOK.TITLE'),
      description: t('INBOX_MGMT.ADD.AUTH.CHANNEL.TIKTOK.DESCRIPTION'),
      icon: 'i-woot-tiktok',
    });
  }

  channels.push({
    key: 'voice',
    title: t('INBOX_MGMT.ADD.AUTH.CHANNEL.VOICE.TITLE'),
    description: t('INBOX_MGMT.ADD.AUTH.CHANNEL.VOICE.DESCRIPTION'),
    icon: 'i-woot-voice',
  });

  channels.push({
    key: 'whatsapp_call',
    title: t('INBOX_MGMT.ADD.AUTH.CHANNEL.WHATSAPP_CALL.TITLE'),
    description: t('INBOX_MGMT.ADD.AUTH.CHANNEL.WHATSAPP_CALL.DESCRIPTION'),
    icon: 'i-woot-whatsapp',
  });

  return channels;
});

const isChannelSetupAllowed = key => {
  // 17C.3: in managed mode the WhatsApp card is shown for self-serve registration even though native WhatsApp /
  // inbox-creation are restricted (false). Gated by its own capability; the card routes to the managed wizard.
  if (key === 'whatsapp' && canSelfServeManagedWhatsapp.value) return true;
  // 11B.7C: managed mode blocks ALL inbox creation, so self-service channels are gated too.
  if (!canCreateInbox.value) return false;
  if (SELF_SERVICE_CHANNELS.includes(key)) return true;
  if (NATIVE_WHATSAPP_CHANNELS.includes(key))
    return canManageNativeWhatsappSetup.value;
  return canManageProviderSetup.value;
};

const visibleChannelList = computed(() =>
  channelList.value.filter(channel => isChannelSetupAllowed(channel.key))
);

// Loading = the server-derived capabilities (which live ONLY on the account-show payload) have not hydrated yet
// for the current account. While loading we render a skeleton — never the empty "managed by Ops" state — so the
// WhatsApp card cannot momentarily disappear on refresh. `loadError` drives a recoverable retry surface.
const isLoadingCapabilities = ref(!capabilitiesLoaded.value);
const loadError = ref(false);

const initializeEnabledFeatures = () => {
  enabledFeatures.value = currentAccount.value?.features ?? {};
};

// Ensure the authoritative account payload (the only source of `bloomwire_capabilities`) is hydrated BEFORE we
// decide what to render. The stock `accounts/get` action swallows failures, so after awaiting it we treat
// still-missing capabilities as a recoverable error rather than silently painting an empty channel list.
const loadCapabilities = async () => {
  loadError.value = false;
  isLoadingCapabilities.value = !capabilitiesLoaded.value;
  try {
    if (!capabilitiesLoaded.value) {
      await store.dispatch('accounts/get', {});
    }
    initializeEnabledFeatures();
    loadError.value = !capabilitiesLoaded.value;
  } catch (error) {
    loadError.value = true;
  } finally {
    isLoadingCapabilities.value = false;
  }
};

const initChannelAuth = channel => {
  const params = {
    sub_page: channel,
    accountId: accountId.value,
  };
  router.push({ name: 'settings_inboxes_page_channel', params });
};

// Bloomwire (17F.2A): when no channel card is permitted (e.g. managed mode with self-serve not granted) the list is
// empty. Never render a blank surface — show a safe, non-secret "managed for you" state with a usable Back action.
const goBack = () => {
  router.push({ name: 'settings_inbox_list' });
};

onMounted(loadCapabilities);
</script>

<template>
  <!-- Capabilities still hydrating: render a loading state, NEVER the empty channel surface, so the WhatsApp
       card cannot momentarily disappear while the account-show payload is in flight. -->
  <div
    v-if="isLoadingCapabilities"
    data-testid="channel-loading"
    class="flex items-center justify-center w-full p-8"
  >
    <LoadingState :message="$t('INBOX_MGMT.ADD.AUTH.LOADING_CHANNELS')" />
  </div>
  <!-- Authoritative capability/account request failed: recoverable error with retry — never silently hide. -->
  <div
    v-else-if="loadError"
    data-testid="channel-load-error"
    class="flex flex-col items-center justify-center w-full max-w-lg gap-2 p-8 mx-auto text-center"
  >
    <h3 class="text-heading-2 text-n-slate-12">
      {{ $t('INBOX_MGMT.ADD.AUTH.LOAD_ERROR.TITLE') }}
    </h3>
    <p class="text-body-main text-n-slate-11">
      {{ $t('INBOX_MGMT.ADD.AUTH.LOAD_ERROR.BODY') }}
    </p>
    <NextButton
      type="button"
      solid
      blue
      data-testid="channel-load-retry"
      :label="$t('INBOX_MGMT.ADD.AUTH.LOAD_ERROR.RETRY')"
      class="mt-2"
      @click="loadCapabilities"
    />
  </div>
  <div
    v-else-if="visibleChannelList.length"
    class="grid max-w-3xl grid-cols-1 xs:grid-cols-2 mx-0 gap-6 sm:grid-cols-3 p-8"
  >
    <ChannelItem
      v-for="channel in visibleChannelList"
      :key="channel.key"
      :channel="channel"
      :enabled-features="enabledFeatures"
      @channel-item-click="initChannelAuth"
    />
  </div>
  <div
    v-else
    data-testid="channel-unavailable"
    class="flex flex-col items-center justify-center w-full max-w-lg gap-2 p-8 mx-auto text-center"
  >
    <h3 class="text-heading-2 text-n-slate-12">
      {{ $t('INBOX_MGMT.MANAGED_BY_OPS.TITLE') }}
    </h3>
    <p class="text-body-main text-n-slate-11">
      {{ $t('INBOX_MGMT.MANAGED_BY_OPS.BODY') }}
    </p>
    <button
      type="button"
      data-testid="channel-unavailable-back"
      class="mt-2 text-label-small font-medium text-n-blue-11 hover:underline"
      @click="goBack"
    >
      {{ $t('GENERAL_SETTINGS.BACK') }}
    </button>
  </div>
</template>
