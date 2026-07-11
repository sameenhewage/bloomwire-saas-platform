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

  // Phase 5 (resume): re-verify outbound messaging capability for an existing Action-Required managed WhatsApp
  // setup (setupId = Bloomwire::WhatsappSetup id). PATCH; returns ONLY the safe DTO (ids / status / ready /
  // sanitized reason) — never a token / secret / raw Meta payload. Backs the "Recheck permission" action.
  recheckBloomwireCapability(setupId, config = {}) {
    return axios.patch(
      `${this.baseUrl()}/bloomwire/whatsapp/messaging_capabilities/${setupId}`,
      {},
      config
    );
  }

  // Phase 5 (resume): DURABLE read of an inbox's managed outbound-messaging capability status (inboxId = Inbox
  // id). GET; returns ONLY the safe DTO ({ managed, setup, ready, action_required? }) so the Inbox Settings
  // panel can restore an Action-Required inbox after refresh / navigation / re-login. Never a token / secret.
  fetchBloomwireCapability(inboxId, config = {}) {
    return axios.get(
      `${this.baseUrl()}/bloomwire/whatsapp/messaging_capabilities`,
      { params: { inbox_id: inboxId }, ...config }
    );
  }

  // WhatsWay-parity "Disconnect" (inboxId = Inbox id). POST; deregisters the number on Meta (-> DISCONNECTED) and
  // marks the setup non-routeable while KEEPING the Channel/Inbox/Setup records so a later Embedded Signup reconnect
  // reuses them. Returns ONLY the safe DTO ({ managed, disconnected, inbox, setup }) — never a token / secret.
  disconnectBloomwireCapability(inboxId, config = {}) {
    return axios.post(
      `${this.baseUrl()}/bloomwire/whatsapp/disconnections`,
      { inbox_id: inboxId },
      config
    );
  }

  // Coexistence offboarding recheck (inboxId = Inbox id). POST; the SINGLE reconciliation owner — after the owner
  // completes the mobile Business-Platform disconnect, it asks the backend to confirm with Meta and marks the setup
  // disconnected ONLY on authoritative proof (200); 409 still_connected / 502 recheck_unverified leave state as-is.
  // Returns ONLY the safe DTO ({ managed, disconnected, inbox, setup }) — never a token / secret.
  recheckBloomwireDisconnection(inboxId, config = {}) {
    return axios.post(
      `${this.baseUrl()}/bloomwire/whatsapp/disconnections/recheck`,
      { inbox_id: inboxId },
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

  // ADR-0010 v3 (async managed onboarding). Opens a resumable attempt BEFORE the Meta popup; returns the opaque
  // public attempt_id (no secrets). The request does no Meta work. Inert (404) unless the async flag is ON.
  createBloomwireOnboardingAttempt(config = {}) {
    return axios.post(
      `${this.baseUrl()}/bloomwire/whatsapp/onboarding_attempts`,
      {},
      config
    );
  }

  // Submits the Meta popup result (code + non-secret signup identifiers) for the given attempt. The backend stores
  // the code (encrypted), queues the attempt, and enqueues the background worker. Never sends secrets/tokens.
  submitBloomwireOnboardingAttempt(attemptId, params, config = {}) {
    return axios.post(
      `${this.baseUrl()}/bloomwire/whatsapp/onboarding_attempts/${attemptId}/submit`,
      params,
      config
    );
  }

  // Poll the attempt's safe status DTO (status / step / masked phone / ids) — never a token/secret. Account-scoped
  // on the server (a foreign attempt id is a 404).
  fetchBloomwireOnboardingAttempt(attemptId, config = {}) {
    return axios.get(
      `${this.baseUrl()}/bloomwire/whatsapp/onboarding_attempts/${attemptId}`,
      config
    );
  }

  relaunchBloomwireOnboardingAttempt(attemptId, config = {}) {
    return axios.post(
      `${this.baseUrl()}/bloomwire/whatsapp/onboarding_attempts/${attemptId}/relaunch`,
      {},
      config
    );
  }

  cancelBloomwireOnboardingAttempt(attemptId, config = {}) {
    return axios.post(
      `${this.baseUrl()}/bloomwire/whatsapp/onboarding_attempts/${attemptId}/cancel`,
      {},
      config
    );
  }
}

export default new WhatsappChannel();
