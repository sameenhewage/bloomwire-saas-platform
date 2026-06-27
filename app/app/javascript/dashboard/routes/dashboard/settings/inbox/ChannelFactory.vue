<script setup>
import { computed } from 'vue';
import Facebook from './channels/Facebook.vue';
import Website from './channels/Website.vue';
import Twitter from './channels/Twitter.vue';
import Api from './channels/Api.vue';
import Email from './channels/Email.vue';
import Sms from './channels/Sms.vue';
import Whatsapp from './channels/Whatsapp.vue';
import WhatsappCall from './channels/WhatsappCall.vue';
import Line from './channels/Line.vue';
import Telegram from './channels/Telegram.vue';
import Instagram from './channels/Instagram.vue';
import Tiktok from './channels/Tiktok.vue';
import Voice from './channels/Voice.vue';
import { useBloomwireCapabilities } from 'dashboard/composables/useBloomwireCapabilities';

const props = defineProps({
  channelName: {
    type: String,
    required: true,
  },
});

// Bloomwire (11B.6C): defense-in-depth for direct URL access to a provider/native-WhatsApp
// channel setup route. ChannelList cards are the normal entry point and are hidden when
// Ops-managed; if a guarded route is still reached directly, show a safe managed-by-ops
// state instead of the create form. Backend (PR #40/#44/#46/#47) remains the 403 enforcement.
const { canManageProviderSetup, canManageNativeWhatsappSetup } =
  useBloomwireCapabilities();

const SELF_SERVICE_CHANNELS = ['website', 'api'];
const NATIVE_WHATSAPP_CHANNELS = ['whatsapp', 'whatsapp_call'];

const channelViewList = {
  facebook: Facebook,
  website: Website,
  twitter: Twitter,
  api: Api,
  email: Email,
  sms: Sms,
  whatsapp: Whatsapp,
  whatsapp_call: WhatsappCall,
  line: Line,
  telegram: Telegram,
  instagram: Instagram,
  tiktok: Tiktok,
  voice: Voice,
};

const channelComponent = computed(
  () => channelViewList[props.channelName] ?? null
);

const isChannelSetupAllowed = computed(() => {
  const key = props.channelName;
  if (SELF_SERVICE_CHANNELS.includes(key)) return true;
  if (NATIVE_WHATSAPP_CHANNELS.includes(key))
    return canManageNativeWhatsappSetup.value;
  return canManageProviderSetup.value;
});
</script>

<template>
  <component
    :is="channelComponent"
    v-if="isChannelSetupAllowed && channelComponent"
  />
  <div
    v-else-if="!isChannelSetupAllowed"
    class="flex flex-col items-center justify-center w-full max-w-lg gap-2 p-8 mx-auto text-center"
  >
    <h3 class="text-heading-2 text-n-slate-12">
      {{ $t('INBOX_MGMT.MANAGED_BY_OPS.TITLE') }}
    </h3>
    <p class="text-body-main text-n-slate-11">
      {{ $t('INBOX_MGMT.MANAGED_BY_OPS.BODY') }}
    </p>
  </div>
</template>
