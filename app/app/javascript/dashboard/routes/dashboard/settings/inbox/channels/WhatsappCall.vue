<script setup>
import WhatsappEmbeddedSignup from './WhatsappEmbeddedSignup.vue';
import { useAccount } from 'dashboard/composables/useAccount';

// Bloomwire (ADR 0005, 4.4-b-WA.2D): WhatsApp Call external setup is platform-owned
// for Bloomwire-managed tenants, so this direct setup route shows a managed notice
// instead of the embedded signup (which the channel tile already hides). Backend
// deny remains the real enforcement.
const { isBloomwireManagedAccount } = useAccount();
</script>

<template>
  <div class="overflow-auto col-span-6 p-6 w-full h-full">
    <div
      v-if="isBloomwireManagedAccount"
      class="px-6 py-5 text-sm rounded-2xl border border-n-weak text-n-slate-11"
    >
      {{ $t('INBOX_MGMT.BLOOMWIRE_MANAGED.NOTICE') }}
    </div>
    <div v-else class="px-6 py-5 rounded-2xl border border-n-weak">
      <WhatsappEmbeddedSignup enable-calling-on-complete />
    </div>
  </div>
</template>
