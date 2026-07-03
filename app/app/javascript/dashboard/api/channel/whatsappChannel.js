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
  createBloomwireEmbeddedSignup(params) {
    return axios.post(
      `${this.baseUrl()}/bloomwire/whatsapp/embedded_signup`,
      params
    );
  }

  // Phase 17D.3: managed self-serve WhatsApp Business App COEXISTENCE signup. Sends the SAME non-secret Meta
  // signup credentials (code / business_id / waba_id / phone_number_id) but to the dedicated coexistence
  // endpoint (connection_mode=coexistence; Phase 17D.1). Never posts to native /whatsapp/authorization; never
  // sends app secret / verify token / webhook URL / API token / provider_config.
  createBloomwireCoexistenceEmbeddedSignup(params) {
    return axios.post(
      `${this.baseUrl()}/bloomwire/whatsapp/coexistence_embedded_signup`,
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
