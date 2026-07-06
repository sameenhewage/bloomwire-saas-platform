/* global axios */
import ApiClient from '../ApiClient';

class WhatsappChannel extends ApiClient {
  constructor() {
    super('whatsapp', { accountScoped: true });
  }

  createEmbeddedSignup(params) {
    return axios.post(`${this.baseUrl()}/whatsapp/authorization`, params);
  }

  // Phase 17C.3: managed self-serve WhatsApp Embedded Signup. Sends only the non-secret Meta signup credentials
  // (code / business_id / waba_id / phone_number_id) to the dedicated Bloomwire endpoint (global webhook router).
  // Never posts to native /whatsapp/authorization; never sends app secret / verify token / webhook URL / token.
  createBloomwireEmbeddedSignup(params, config = {}) {
    return axios.post(
      `${this.baseUrl()}/bloomwire/whatsapp/embedded_signup`,
      params,
      config
    );
  }

  // Phase 17D.3: managed self-serve WhatsApp Business App COEXISTENCE signup. Sends the SAME non-secret Meta
  // signup credentials (code / business_id / waba_id / phone_number_id) but to the dedicated coexistence
  // endpoint (connection_mode=coexistence; Phase 17D.1). Never posts to native /whatsapp/authorization; never
  // sends app secret / verify token / webhook URL / API token / provider_config.
  createBloomwireCoexistenceEmbeddedSignup(params, config = {}) {
    return axios.post(
      `${this.baseUrl()}/bloomwire/whatsapp/coexistence_embedded_signup`,
      params,
      config
    );
  }

  // Advisory duplicate-number preflight for the managed WhatsApp wizard. Sends only the typed phone number and
  // receives ONLY { status: "available" | "already_connected" } — never another tenant's account/inbox/channel.
  checkPhoneAvailability(phoneNumber, config = {}) {
    return axios.post(
      `${this.baseUrl()}/bloomwire/whatsapp/phone_availability`,
      { phone_number: phoneNumber },
      config
    );
  }

  // Structured, sanitized onboarding trace sink (managed WhatsApp / Coexistence). Sends ONLY allow-listed,
  // non-sensitive telemetry (attempt id, event, result, elapsed_ms, http_status, error_code) to the
  // account-scoped admin endpoint. Never sends the auth code / tokens / phone number / WABA / Meta identifiers.
  sendOnboardingTrace(params) {
    return axios.post(
      `${this.baseUrl()}/bloomwire/whatsapp/onboarding_traces`,
      params
    );
  }

  reauthorizeWhatsApp({ inboxId, ...params }) {
    return axios.post(`${this.baseUrl()}/whatsapp/authorization`, {
      ...params,
      inbox_id: inboxId,
    });
  }
}

export default new WhatsappChannel();
