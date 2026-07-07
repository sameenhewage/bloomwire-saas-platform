import {
  initializeFacebook,
  setupFacebookSdk,
  DEFAULT_WHATSAPP_GRAPH_API_VERSION,
} from '../utils';
import { loadScript } from 'dashboard/helper/DOMHelpers';

vi.mock('dashboard/helper/DOMHelpers', () => ({
  loadScript: vi.fn(() => Promise.resolve()),
}));

// Approved Meta Graph API version contract: the WhatsApp Embedded Signup / Coexistence popup must initialize
// the Facebook JS SDK on v25.0 and must never silently fall back to an older Graph API version. In production
// the frontend receives whatsappApiVersion from the WHATSAPP_API_VERSION global config; this default is the
// safety net when that value is empty (which is exactly what happened during the account-21 incident window).
describe('whatsapp/utils — Graph API version', () => {
  afterEach(() => {
    delete window.FB;
    delete window.fbAsyncInit;
  });

  it('exports the approved default Graph API version (v25.0)', () => {
    expect(DEFAULT_WHATSAPP_GRAPH_API_VERSION).toBe('v25.0');
  });

  it('initializes the Facebook SDK with v25.0 when no version is provided', async () => {
    const init = vi.fn();
    window.FB = { init };
    await initializeFacebook('app-id');
    expect(init).toHaveBeenCalledWith(
      expect.objectContaining({ version: 'v25.0' })
    );
  });

  it('never initializes the SDK on an older/implicit Graph API version', async () => {
    const init = vi.fn();
    window.FB = { init };
    await initializeFacebook('app-id', '');
    const { version } = init.mock.calls[0][0];
    expect(version).toBe('v25.0');
    expect(version).not.toMatch(/^v(1[0-9]|2[0-4])\.0$/);
  });

  it('still respects an explicitly provided version (override preserved)', async () => {
    const init = vi.fn();
    window.FB = { init };
    await initializeFacebook('app-id', 'v23.0');
    expect(init).toHaveBeenCalledWith(
      expect.objectContaining({ version: 'v23.0' })
    );
  });

  it('setupFacebookSdk initializes the SDK on v25.0 when no version is provided', async () => {
    const init = vi.fn();
    window.FB = { init };
    await setupFacebookSdk('app-id');
    expect(init).toHaveBeenCalledWith(
      expect.objectContaining({ version: 'v25.0' })
    );
  });

  // Regression: 'FB.login() called before FB.init()'. On a fresh page (window.FB absent until the SDK
  // bootstraps), FB.init must be armed via window.fbAsyncInit BEFORE the SDK script loads, so the SDK invokes
  // it during its own bootstrap and callers never reach FB.login on an uninitialized SDK.
  it('arms FB.init before the SDK script loads so FB.login can never run first', async () => {
    const init = vi.fn();
    loadScript.mockImplementationOnce(() => {
      // The SDK is loading now — FB.init MUST already be armed.
      expect(typeof window.fbAsyncInit).toBe('function');
      // Simulate the SDK finishing: it defines window.FB and invokes fbAsyncInit.
      window.FB = { init };
      window.fbAsyncInit();
      return Promise.resolve();
    });

    await setupFacebookSdk('app-id');

    expect(init).toHaveBeenCalledWith(
      expect.objectContaining({ version: 'v25.0' })
    );
  });
});
