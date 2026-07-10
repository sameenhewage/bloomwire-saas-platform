import { computed } from 'vue';
import { useBloomwireCapabilities } from './useBloomwireCapabilities';

// ADR-0010 v3: explicit capability-driven routing for Standard WhatsApp onboarding only. Coexistence stays on its
// existing flow and never reads this path. The decision comes only from account.bloomwire_capabilities, never an
// HTTP status: unavailable when managed onboarding is off; async by default; sync only under the emergency switch.
export const STANDARD_ONBOARDING_PATH = Object.freeze({
  UNAVAILABLE: 'unavailable',
  ASYNC: 'async',
  SYNC: 'sync',
});

export function useBloomwireWhatsappOnboarding() {
  const {
    canSelfServeManagedWhatsapp,
    canUseAsyncStandardWhatsappOnboarding,
    capabilitiesLoaded,
  } = useBloomwireCapabilities();

  const standardPath = computed(() => {
    if (!canSelfServeManagedWhatsapp.value)
      return STANDARD_ONBOARDING_PATH.UNAVAILABLE;
    return canUseAsyncStandardWhatsappOnboarding.value
      ? STANDARD_ONBOARDING_PATH.ASYNC
      : STANDARD_ONBOARDING_PATH.SYNC;
  });

  return {
    capabilitiesLoaded,
    standardPath,
    isAvailable: computed(
      () => standardPath.value !== STANDARD_ONBOARDING_PATH.UNAVAILABLE
    ),
    usesAsyncStandard: computed(
      () => standardPath.value === STANDARD_ONBOARDING_PATH.ASYNC
    ),
    usesSyncStandard: computed(
      () => standardPath.value === STANDARD_ONBOARDING_PATH.SYNC
    ),
    STANDARD_ONBOARDING_PATH,
  };
}
