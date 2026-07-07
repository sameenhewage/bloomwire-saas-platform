import { loadScript } from 'dashboard/helper/DOMHelpers';

// Approved Meta Graph API version for the WhatsApp Embedded Signup / Coexistence popup. The frontend
// normally receives the version from the WHATSAPP_API_VERSION global config (window.chatwootConfig
// .whatsappApiVersion); this is the safety default so the Facebook JS SDK never silently initializes on an
// older Graph API version when that config value is absent. Keep this in step with
// Whatsapp::GraphApi::DEFAULT_VERSION on the backend.
export const DEFAULT_WHATSAPP_GRAPH_API_VERSION = 'v25.0';

export const loadFacebookSdk = async () => {
  return loadScript('https://connect.facebook.net/en_US/sdk.js', {
    async: true,
    defer: true,
    crossOrigin: 'anonymous',
  });
};

export const initializeFacebook = (appId, apiVersion) => {
  const version = apiVersion || DEFAULT_WHATSAPP_GRAPH_API_VERSION;
  return new Promise(resolve => {
    const init = () => {
      window.FB.init({
        appId,
        autoLogAppEvents: true,
        xfbml: true,
        version,
      });
      resolve();
    };

    if (window.FB) {
      init();
    } else {
      window.fbAsyncInit = init;
    }
  });
};

export const isValidBusinessData = businessData => {
  return businessData && businessData.business_id && businessData.waba_id;
};

export const createMessageHandler = onEmbeddedSignupData => {
  return event => {
    if (!event.origin.endsWith('facebook.com')) return;

    try {
      let data;
      if (typeof event.data === 'string') {
        data = JSON.parse(event.data);
      } else if (typeof event.data === 'object' && event.data !== null) {
        data = event.data;
      } else {
        return;
      }

      if (data.type === 'WA_EMBEDDED_SIGNUP') {
        onEmbeddedSignupData(data);
      }
    } catch {
      // Ignore non-JSON or irrelevant messages
    }
  };
};

export const initWhatsAppEmbeddedSignup = configId => {
  return new Promise((resolve, reject) => {
    window.FB.login(
      response => {
        if (response.authResponse && response.authResponse.code) {
          resolve(response.authResponse.code);
        } else if (response.error) {
          reject(new Error(response.error));
        } else {
          reject(new Error('Login cancelled'));
        }
      },
      {
        config_id: configId,
        response_type: 'code',
        override_default_response_type: true,
        extras: {
          setup: {},
          featureType: 'whatsapp_business_app_onboarding',
          sessionInfoVersion: '3',
        },
      }
    );
  });
};

export const setupFacebookSdk = async (appId, apiVersion) => {
  const version = apiVersion || DEFAULT_WHATSAPP_GRAPH_API_VERSION;
  // Arm FB.init (via window.fbAsyncInit) BEFORE the SDK script loads, so the SDK invokes it as part of its own
  // bootstrap — Meta's canonical order. Loading first and initializing after races the SDK's async readiness and
  // can let FB.login() fire "before FB.init()". `initialized` resolves only once FB.init has actually run, and it
  // is awaited last so callers never reach FB.login on an uninitialized SDK (cached-SDK path resolves eagerly via
  // the `window.FB` branch in initializeFacebook).
  const initialized = initializeFacebook(appId, version);
  await loadFacebookSdk();
  await initialized;
};
