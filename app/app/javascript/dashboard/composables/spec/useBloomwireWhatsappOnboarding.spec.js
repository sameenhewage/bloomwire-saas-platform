import { ref } from 'vue';
import {
  useBloomwireWhatsappOnboarding,
  STANDARD_ONBOARDING_PATH,
} from '../useBloomwireWhatsappOnboarding';

let caps;
vi.mock('../useBloomwireCapabilities', () => ({
  useBloomwireCapabilities: () => caps,
}));

const setCaps = ({ available, async: usesAsyncStandard, loaded = true }) => {
  caps = {
    canSelfServeManagedWhatsapp: ref(available),
    canUseAsyncStandardWhatsappOnboarding: ref(usesAsyncStandard),
    capabilitiesLoaded: ref(loaded),
  };
};

describe('useBloomwireWhatsappOnboarding (explicit Standard routing; Coexistence unaffected)', () => {
  it('routes to ASYNC when onboarding is available AND async is enabled', () => {
    setCaps({ available: true, async: true });
    const { standardPath, usesAsyncStandard, usesSyncStandard, isAvailable } =
      useBloomwireWhatsappOnboarding();
    expect(standardPath.value).toBe(STANDARD_ONBOARDING_PATH.ASYNC);
    expect(usesAsyncStandard.value).toBe(true);
    expect(usesSyncStandard.value).toBe(false);
    expect(isAvailable.value).toBe(true);
  });

  it('routes to the SYNC fallback when available but async is disabled (kill switch ON) — an INTENTIONAL decision, not a 404 recovery', () => {
    setCaps({ available: true, async: false });
    const { standardPath, usesSyncStandard, usesAsyncStandard, isAvailable } =
      useBloomwireWhatsappOnboarding();
    expect(standardPath.value).toBe(STANDARD_ONBOARDING_PATH.SYNC);
    expect(usesSyncStandard.value).toBe(true);
    expect(usesAsyncStandard.value).toBe(false);
    expect(isAvailable.value).toBe(true);
  });

  it('routes to UNAVAILABLE (both entry paths blocked) when the Bloomwire feature is OFF', () => {
    setCaps({ available: false, async: false });
    const { standardPath, isAvailable, usesAsyncStandard, usesSyncStandard } =
      useBloomwireWhatsappOnboarding();
    expect(standardPath.value).toBe(STANDARD_ONBOARDING_PATH.UNAVAILABLE);
    expect(isAvailable.value).toBe(false);
    expect(usesAsyncStandard.value).toBe(false);
    expect(usesSyncStandard.value).toBe(false);
  });

  it('feature-OFF dominates: never routes to async even if the async flag is stray-true while unavailable', () => {
    setCaps({ available: false, async: true });
    expect(useBloomwireWhatsappOnboarding().standardPath.value).toBe(
      STANDARD_ONBOARDING_PATH.UNAVAILABLE
    );
  });
});
