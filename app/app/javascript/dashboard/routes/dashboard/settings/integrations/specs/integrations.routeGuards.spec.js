import { redirectIfIntegrationsManaged } from '../integrations.routeGuards';
import store from 'dashboard/store';

vi.mock('dashboard/store', () => ({
  default: { getters: {}, dispatch: vi.fn() },
}));

const to = { params: { accountId: '7' } };

const setAccount = account => {
  store.getters['accounts/getAccount'] = id => (id === 7 ? account : undefined);
};

describe('redirectIfIntegrationsManaged (Bloomwire 11B.7E route guard)', () => {
  beforeEach(() => {
    store.dispatch.mockReset();
  });

  it('redirects to the account dashboard when canAccessIntegrations is explicitly false', async () => {
    setAccount({ bloomwire_capabilities: { canAccessIntegrations: false } });
    const next = vi.fn();
    await redirectIfIntegrationsManaged(to, {}, next);
    expect(next).toHaveBeenCalledTimes(1);
    expect(next.mock.calls[0][0]).toContain('accounts/7/dashboard');
  });

  it('allows navigation when canAccessIntegrations is true', async () => {
    setAccount({ bloomwire_capabilities: { canAccessIntegrations: true } });
    const next = vi.fn();
    await redirectIfIntegrationsManaged(to, {}, next);
    expect(next).toHaveBeenCalledWith();
  });

  it('fetches the account and redirects when the loaded capability is false', async () => {
    let loadedAccount;
    store.getters['accounts/getAccount'] = id =>
      id === 7 ? loadedAccount : undefined;
    store.dispatch.mockImplementation(async () => {
      loadedAccount = {
        bloomwire_capabilities: { canAccessIntegrations: false },
      };
    });

    const next = vi.fn();
    await redirectIfIntegrationsManaged(to, {}, next);

    expect(store.dispatch).toHaveBeenCalledWith('accounts/get', {
      silent: true,
    });
    expect(next.mock.calls[0][0]).toContain('accounts/7/dashboard');
  });

  it('allows navigation when the fetched account has no capability', async () => {
    setAccount({ bloomwire_capabilities: {} });
    store.dispatch.mockResolvedValue();
    const next = vi.fn();
    await redirectIfIntegrationsManaged(to, {}, next);
    expect(next).toHaveBeenCalledWith();
  });

  it('allows navigation (stock-safe) when the account fetch fails', async () => {
    setAccount(undefined);
    store.dispatch.mockRejectedValue(new Error('failed'));
    const next = vi.fn();
    await redirectIfIntegrationsManaged(to, {}, next);
    expect(next).toHaveBeenCalledWith();
  });
});
