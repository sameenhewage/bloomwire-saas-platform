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

  reauthorizeWhatsApp({ inboxId, ...params }) {
    return axios.post(`${this.baseUrl()}/whatsapp/authorization`, {
      ...params,
      inbox_id: inboxId,
    });
  }
}

export default new WhatsappChannel();
