import { useWhatsappEmbeddedSignup } from '../useWhatsappEmbeddedSignup';
import {
  setupFacebookSdk,
  initWhatsAppEmbeddedSignup,
  createMessageHandler,
} from 'dashboard/routes/dashboard/settings/inbox/channels/whatsapp/utils';

vi.mock(
  'dashboard/routes/dashboard/settings/inbox/channels/whatsapp/utils',
  () => ({
    setupFacebookSdk: vi.fn(),
    initWhatsAppEmbeddedSignup: vi.fn(),
    createMessageHandler: vi.fn(),
    isValidBusinessData: vi.fn(data =>
      Boolean(data && data.business_id && data.waba_id)
    ),
  })
);

const flushPromises = () =>
  new Promise(resolve => {
    setTimeout(resolve, 0);
  });

const createDeferred = () => {
  let resolve;
  let reject;
  const promise = new Promise((res, rej) => {
    resolve = res;
    reject = rej;
  });
  return { promise, resolve, reject };
};

const VALID_BUSINESS = {
  business_id: 'biz-1',
  waba_id: 'waba-1',
  phone_number_id: 'phone-1',
};

describe('useWhatsappEmbeddedSignup', () => {
  // The mocked createMessageHandler captures the callback the composable
  // registers, so tests can simulate Meta's WA_EMBEDDED_SIGNUP postMessages
  // directly without the window-event + origin plumbing (that is covered by
  // the utils' own tests).
  let signupCallback;
  let registeredListener;

  const emit = data => signupCallback(data);

  beforeEach(() => {
    vi.clearAllMocks();

    window.chatwootConfig = {
      whatsappAppId: 'app-id',
      whatsappConfigurationId: 'config-id',
      whatsappApiVersion: 'v22.0',
    };

    setupFacebookSdk.mockResolvedValue();
    createMessageHandler.mockImplementation(callback => {
      signupCallback = callback;
      registeredListener = () => {};
      return registeredListener;
    });
  });

  it('resolves credentials when the auth code arrives before the business data', async () => {
    initWhatsAppEmbeddedSignup.mockResolvedValue('auth-code');

    const { runEmbeddedSignup } = useWhatsappEmbeddedSignup();
    const result = runEmbeddedSignup();

    await flushPromises(); // SDK setup + FB.login resolve the code first
    emit({ event: 'FINISH', data: VALID_BUSINESS });

    await expect(result).resolves.toEqual({
      code: 'auth-code',
      business_id: 'biz-1',
      waba_id: 'waba-1',
      phone_number_id: 'phone-1',
    });
    expect(setupFacebookSdk).toHaveBeenCalledWith('app-id', 'v22.0');
    expect(initWhatsAppEmbeddedSignup).toHaveBeenCalledWith('config-id');
  });

  it('resolves credentials when the business data arrives before the auth code', async () => {
    const code = createDeferred();
    initWhatsAppEmbeddedSignup.mockReturnValue(code.promise);

    const { runEmbeddedSignup } = useWhatsappEmbeddedSignup();
    const result = runEmbeddedSignup();

    // Business data lands first, while FB.login is still pending.
    emit({
      event: 'FINISH_WHATSAPP_BUSINESS_APP_ONBOARDING',
      data: VALID_BUSINESS,
    });
    code.resolve('late-code');

    await expect(result).resolves.toEqual({
      code: 'late-code',
      business_id: 'biz-1',
      waba_id: 'waba-1',
      phone_number_id: 'phone-1',
    });
  });

  it('defaults phone_number_id to an empty string when absent', async () => {
    initWhatsAppEmbeddedSignup.mockResolvedValue('auth-code');

    const { runEmbeddedSignup } = useWhatsappEmbeddedSignup();
    const result = runEmbeddedSignup();

    await flushPromises();
    emit({
      event: 'FINISH',
      data: { business_id: 'biz-1', waba_id: 'waba-1' },
    });

    await expect(result).resolves.toMatchObject({ phone_number_id: '' });
  });

  it('resolves null when FB.login is cancelled', async () => {
    initWhatsAppEmbeddedSignup.mockRejectedValue(new Error('Login cancelled'));

    const { runEmbeddedSignup } = useWhatsappEmbeddedSignup();

    await expect(runEmbeddedSignup()).resolves.toBeNull();
  });

  it('resolves null on a CANCEL event', async () => {
    initWhatsAppEmbeddedSignup.mockReturnValue(createDeferred().promise);

    const { runEmbeddedSignup } = useWhatsappEmbeddedSignup();
    const result = runEmbeddedSignup();

    emit({ event: 'CANCEL' });

    await expect(result).resolves.toBeNull();
  });

  it('rejects with the Meta error message on an error event', async () => {
    initWhatsAppEmbeddedSignup.mockReturnValue(createDeferred().promise);

    const { runEmbeddedSignup } = useWhatsappEmbeddedSignup();
    const result = runEmbeddedSignup();

    emit({ event: 'error', error_message: 'WABA not eligible' });

    await expect(result).rejects.toThrow('WABA not eligible');
  });

  it('rejects when the business data is invalid', async () => {
    initWhatsAppEmbeddedSignup.mockReturnValue(createDeferred().promise);

    const { runEmbeddedSignup } = useWhatsappEmbeddedSignup();
    const result = runEmbeddedSignup();

    emit({ event: 'FINISH', data: { business_id: 'biz-1' } }); // no waba_id

    await expect(result).rejects.toThrow('Invalid business data');
  });

  it('rejects when the SDK or login fails for a non-cancel reason', async () => {
    initWhatsAppEmbeddedSignup.mockRejectedValue(new Error('popup blocked'));

    const { runEmbeddedSignup } = useWhatsappEmbeddedSignup();

    await expect(runEmbeddedSignup()).rejects.toThrow('popup blocked');
  });

  it('ignores a second call while a run is in flight', async () => {
    initWhatsAppEmbeddedSignup.mockResolvedValue('auth-code');

    const { runEmbeddedSignup } = useWhatsappEmbeddedSignup();
    const first = runEmbeddedSignup();
    const second = runEmbeddedSignup();

    await expect(second).resolves.toBeNull();

    // Let the first run finish so it doesn't leak into the next test.
    await flushPromises();
    emit({ event: 'FINISH', data: VALID_BUSINESS });
    await first;

    expect(setupFacebookSdk).toHaveBeenCalledTimes(1);
  });

  it('toggles isAuthenticating and removes the listener once settled', async () => {
    initWhatsAppEmbeddedSignup.mockResolvedValue('auth-code');
    const removeSpy = vi.spyOn(window, 'removeEventListener');

    const { isAuthenticating, runEmbeddedSignup } = useWhatsappEmbeddedSignup();
    expect(isAuthenticating.value).toBe(false);

    const result = runEmbeddedSignup();
    expect(isAuthenticating.value).toBe(true);

    await flushPromises();
    emit({ event: 'FINISH', data: VALID_BUSINESS });
    await result;

    expect(isAuthenticating.value).toBe(false);
    expect(removeSpy).toHaveBeenCalledWith('message', registeredListener);
    removeSpy.mockRestore();
  });

  // Regression for the Stage-B incident: Meta delivered one signal (the auth
  // code) but the business-data postMessage never arrived, so the composable
  // waited forever, isAuthenticating stayed true, and the caller's create POST
  // was never dispatched (infinite "Registering..." spinner). A bounded timeout
  // must settle the run with a safe error instead of hanging.
  it('rejects with a bounded timeout when only the auth code arrives and business data never does', async () => {
    vi.useFakeTimers();
    initWhatsAppEmbeddedSignup.mockResolvedValue('auth-code');

    const { isAuthenticating, runEmbeddedSignup } = useWhatsappEmbeddedSignup();
    const result = runEmbeddedSignup({ timeoutMs: 1000 });
    const assertion = expect(result).rejects.toThrow(/timed out/i);

    await vi.advanceTimersByTimeAsync(0); // SDK + FB.login resolve the code (arms the bounded wait)
    await vi.advanceTimersByTimeAsync(1000); // business data never arrives → timeout fires

    await assertion;
    expect(isAuthenticating.value).toBe(false); // spinner can end; a retry is possible
    vi.useRealTimers();
  });

  it('rejects with a bounded timeout when only the business data arrives and the auth code never does', async () => {
    vi.useFakeTimers();
    initWhatsAppEmbeddedSignup.mockReturnValue(createDeferred().promise); // code never resolves

    const { isAuthenticating, runEmbeddedSignup } = useWhatsappEmbeddedSignup();
    const result = runEmbeddedSignup({ timeoutMs: 1000 });
    const assertion = expect(result).rejects.toThrow(/timed out/i);

    emit({ event: 'FINISH', data: VALID_BUSINESS }); // business data arrives, arms the bounded wait
    await vi.advanceTimersByTimeAsync(1000);

    await assertion;
    expect(isAuthenticating.value).toBe(false);
    vi.useRealTimers();
  });

  it('does not fire the bounded timeout once both signals have resolved the run', async () => {
    vi.useFakeTimers();
    initWhatsAppEmbeddedSignup.mockResolvedValue('auth-code');

    const { runEmbeddedSignup } = useWhatsappEmbeddedSignup();
    const result = runEmbeddedSignup({ timeoutMs: 1000 });

    await vi.advanceTimersByTimeAsync(0); // code arrives (arms the bounded wait)
    emit({ event: 'FINISH', data: VALID_BUSINESS }); // both present → resolve + clear timer

    await expect(result).resolves.toMatchObject({ code: 'auth-code' });
    await vi.advanceTimersByTimeAsync(5000); // past the (cleared) timeout — must not settle again / throw
    vi.useRealTimers();
  });

  it('resolves exactly once when duplicate Meta FINISH events arrive (no duplicate create request)', async () => {
    initWhatsAppEmbeddedSignup.mockResolvedValue('auth-code');
    const resolved = vi.fn();

    const { runEmbeddedSignup } = useWhatsappEmbeddedSignup();
    const result = runEmbeddedSignup().then(resolved);

    await flushPromises();
    emit({ event: 'FINISH', data: VALID_BUSINESS });
    emit({ event: 'FINISH', data: VALID_BUSINESS }); // duplicate event
    emit({
      event: 'FINISH_WHATSAPP_BUSINESS_APP_ONBOARDING',
      data: VALID_BUSINESS,
    }); // duplicate (coexistence alias)

    await result;
    expect(resolved).toHaveBeenCalledTimes(1);
    expect(resolved).toHaveBeenCalledWith(
      expect.objectContaining({ code: 'auth-code' })
    );
  });
});
