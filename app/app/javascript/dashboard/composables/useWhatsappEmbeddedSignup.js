import { ref } from 'vue';
import {
  setupFacebookSdk,
  initWhatsAppEmbeddedSignup,
  createMessageHandler,
  isValidBusinessData,
} from 'dashboard/routes/dashboard/settings/inbox/channels/whatsapp/utils';

// How long to wait for the SECOND Meta signal once the FIRST has arrived. The
// auth code (FB.login) and the business data (postMessage) are both emitted at
// popup completion, so a real signup delivers the second within a few seconds.
// If it never arrives (the Stage-B incident: Meta delivered one signal but the
// other was dropped), this bounds the wait so the run ends with a safe error
// instead of an infinite "Registering..." spinner. It does NOT limit the time
// the customer spends inside the Meta popup — it only starts once one signal is
// already in hand.
const SIGNUP_COMPLETION_TIMEOUT_MS = 60000;

// Drives Meta's WhatsApp embedded-signup popup (Facebook JS SDK). FB.login()
// resolves an auth `code` while the WABA identifiers (waba_id, phone_number_id)
// arrive separately over a postMessage event — order isn't guaranteed, so we
// hold both and resolve once both are present.
//
// `runEmbeddedSignup` returns the signup credentials; the caller exchanges them
// for an inbox via `inboxes/createWhatsAppEmbeddedSignup` and owns its own UX
// (alerts, navigation, etc). Resolves `null` when the user cancels the popup;
// rejects on SDK load or signup errors, or when only one of the two required
// Meta signals ever arrives (bounded by `timeoutMs`). The window listener and
// timer are scoped to a single run, so this is safe to call from anywhere
// without lifecycle wiring.
export function useWhatsappEmbeddedSignup() {
  const isAuthenticating = ref(false);

  const runEmbeddedSignup = ({
    timeoutMs = SIGNUP_COMPLETION_TIMEOUT_MS,
  } = {}) => {
    if (isAuthenticating.value) return Promise.resolve(null);
    isAuthenticating.value = true;

    return new Promise((resolve, reject) => {
      let authCode = null;
      let businessData = null;
      let settled = false;
      let messageHandler;
      let completionTimer = null;

      const settle = (fn, value) => {
        if (settled) return;
        settled = true;
        if (completionTimer) clearTimeout(completionTimer);
        window.removeEventListener('message', messageHandler);
        isAuthenticating.value = false;
        fn(value);
      };

      // Both the auth code and the business data arrive asynchronously and in
      // no fixed order; only resolve once we're holding both. Once the FIRST of
      // the two arrives, arm a bounded timeout so a never-delivered second
      // signal fails closed with a safe error instead of hanging forever.
      const resolveIfReady = () => {
        if (authCode && businessData) {
          settle(resolve, {
            code: authCode,
            business_id: businessData.business_id,
            waba_id: businessData.waba_id,
            phone_number_id: businessData.phone_number_id || '',
          });
          return;
        }
        if ((authCode || businessData) && !completionTimer) {
          completionTimer = setTimeout(() => {
            settle(reject, new Error('Embedded signup timed out'));
          }, timeoutMs);
        }
      };

      messageHandler = createMessageHandler(data => {
        if (
          data.event === 'FINISH' ||
          data.event === 'FINISH_WHATSAPP_BUSINESS_APP_ONBOARDING'
        ) {
          if (!isValidBusinessData(data.data)) {
            settle(reject, new Error('Invalid business data'));
            return;
          }
          businessData = data.data;
          resolveIfReady();
        } else if (data.event === 'CANCEL') {
          settle(resolve, null);
        } else if (data.event === 'error') {
          settle(reject, new Error(data.error_message || 'Signup error'));
        }
      });

      window.addEventListener('message', messageHandler);

      (async () => {
        try {
          await setupFacebookSdk(
            window.chatwootConfig?.whatsappAppId,
            window.chatwootConfig?.whatsappApiVersion
          );
          authCode = await initWhatsAppEmbeddedSignup(
            window.chatwootConfig?.whatsappConfigurationId
          );
          resolveIfReady();
        } catch (error) {
          // FB.login() rejects with 'Login cancelled' when the user dismisses
          // the popup — treat it as a cancel rather than an error.
          if (error.message === 'Login cancelled') {
            settle(resolve, null);
          } else {
            settle(reject, error);
          }
        }
      })();
    });
  };

  return { isAuthenticating, runEmbeddedSignup };
}
