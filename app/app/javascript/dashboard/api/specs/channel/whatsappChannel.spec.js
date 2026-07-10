import whatsappChannel from '../../channel/whatsappChannel';
import ApiClient from '../../ApiClient';

// Phase 17C.3 / 17D.3: the managed Bloomwire WhatsApp client. These tests pin the exact endpoint each method
// posts to — the security boundary between the native path, the Standard managed flow, and the Coexistence
// flow. No real Meta/HTTP: window.axios is mocked. In the test env baseUrl() resolves to `/api/v1` (no account
// in window.location), so the asserted paths are deterministic.
describe('#whatsappChannel', () => {
  it('creates correct instance', () => {
    expect(whatsappChannel).toBeInstanceOf(ApiClient);
    expect(whatsappChannel).toHaveProperty('createEmbeddedSignup');
    expect(whatsappChannel).toHaveProperty('createBloomwireEmbeddedSignup');
    expect(whatsappChannel).toHaveProperty(
      'createBloomwireCoexistenceEmbeddedSignup'
    );
    expect(whatsappChannel).toHaveProperty('createBloomwireOnboardingAttempt');
    expect(whatsappChannel).toHaveProperty('submitBloomwireOnboardingAttempt');
    expect(whatsappChannel).toHaveProperty('fetchBloomwireOnboardingAttempt');
    expect(whatsappChannel).toHaveProperty(
      'relaunchBloomwireOnboardingAttempt'
    );
    expect(whatsappChannel).toHaveProperty('cancelBloomwireOnboardingAttempt');
  });

  describe('API calls', () => {
    const originalAxios = window.axios;
    const axiosMock = {
      post: vi.fn(() => Promise.resolve()),
      get: vi.fn(() => Promise.resolve()),
    };

    const CREDS = {
      code: 'META-CODE',
      business_id: 'BIZ-1',
      waba_id: 'WABA-1',
      phone_number_id: 'PNID-1',
    };

    beforeEach(() => {
      window.axios = axiosMock;
      axiosMock.post.mockClear();
      axiosMock.get.mockClear();
    });

    afterEach(() => {
      window.axios = originalAxios;
    });

    it('#createEmbeddedSignup posts to the NATIVE /whatsapp/authorization (unchanged)', () => {
      whatsappChannel.createEmbeddedSignup(CREDS);
      expect(axiosMock.post).toHaveBeenCalledWith(
        '/api/v1/whatsapp/authorization',
        CREDS
      );
    });

    it('#createBloomwireEmbeddedSignup posts to the Standard managed endpoint (unchanged)', () => {
      whatsappChannel.createBloomwireEmbeddedSignup(CREDS);
      expect(axiosMock.post).toHaveBeenCalledWith(
        '/api/v1/bloomwire/whatsapp/embedded_signup',
        CREDS,
        {}
      );
    });

    it('#createBloomwireCoexistenceEmbeddedSignup posts only the safe signup credentials to the Coexistence endpoint', () => {
      whatsappChannel.createBloomwireCoexistenceEmbeddedSignup(CREDS);
      expect(axiosMock.post).toHaveBeenCalledWith(
        '/api/v1/bloomwire/whatsapp/coexistence_embedded_signup',
        CREDS,
        {}
      );
      // never touches the native authorization path
      expect(axiosMock.post).not.toHaveBeenCalledWith(
        '/api/v1/whatsapp/authorization',
        expect.anything()
      );
      // payload carries no secrets / manual credentials
      const sentBody = axiosMock.post.mock.calls[0][1];
      expect(Object.keys(sentBody).sort()).toEqual([
        'business_id',
        'code',
        'phone_number_id',
        'waba_id',
      ]);
      [
        'app_secret',
        'verify_token',
        'webhook',
        'api_key',
        'provider_config',
      ].forEach(secret => expect(sentBody).not.toHaveProperty(secret));
    });

    it('#createBloomwireOnboardingAttempt opens an async attempt (no body, no Meta work)', () => {
      whatsappChannel.createBloomwireOnboardingAttempt();
      expect(axiosMock.post).toHaveBeenCalledWith(
        '/api/v1/bloomwire/whatsapp/onboarding_attempts',
        {},
        {}
      );
    });

    it('#submitBloomwireOnboardingAttempt posts the signup credentials to the attempt submit path', () => {
      whatsappChannel.submitBloomwireOnboardingAttempt('ATT-UUID', CREDS);
      expect(axiosMock.post).toHaveBeenCalledWith(
        '/api/v1/bloomwire/whatsapp/onboarding_attempts/ATT-UUID/submit',
        CREDS,
        {}
      );
    });

    it('#fetchBloomwireOnboardingAttempt GETs the account-scoped attempt status path', () => {
      whatsappChannel.fetchBloomwireOnboardingAttempt('ATT-UUID');
      expect(axiosMock.get).toHaveBeenCalledWith(
        '/api/v1/bloomwire/whatsapp/onboarding_attempts/ATT-UUID',
        {}
      );
    });

    it('#relaunchBloomwireOnboardingAttempt authorizes relaunch of the same attempt without credentials', () => {
      whatsappChannel.relaunchBloomwireOnboardingAttempt('ATT-UUID');
      expect(axiosMock.post).toHaveBeenCalledWith(
        '/api/v1/bloomwire/whatsapp/onboarding_attempts/ATT-UUID/relaunch',
        {},
        {}
      );
    });

    it('#cancelBloomwireOnboardingAttempt cancels the same server attempt without credentials', () => {
      whatsappChannel.cancelBloomwireOnboardingAttempt('ATT-UUID');
      expect(axiosMock.post).toHaveBeenCalledWith(
        '/api/v1/bloomwire/whatsapp/onboarding_attempts/ATT-UUID/cancel',
        {},
        {}
      );
    });
  });
});
