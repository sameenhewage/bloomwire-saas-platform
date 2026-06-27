import { redirectIfIntegrationsManaged } from '../integrations.routeGuards';
import store from 'dashboard/store';

vi.mock('dashboard/store', () => ({ default: { getters: {} } }));

const to = { params: { accountId: '7' } };

const setAccount = account => {
  store.getters['accounts/getAccount'] = id => (id === 7 ? account : undefined);
};

describe('redirectIfIntegrationsManaged (Bloomwire 11B.7E route guard)', () => {
  it('redirects to the account dashboard when canAccessIntegrations is explicitly false', () => {
    setAccount({ bloomwire_capabilities: { canAccessIntegrations: false } });
    const next = vi.fn();
    redirectIfIntegrationsManaged(to, {}, next);
    expect(next).toHaveBeenCalledTimes(1);
    expect(next.mock.calls[0][0]).toContain('accounts/7/dashboard');
  });

  it('allows navigation when canAccessIntegrations is true', () => {
    setAccount({ bloomwire_capabilities: { canAccessIntegrations: true } });
    const next = vi.fn();
    redirectIfIntegrationsManaged(to, {}, next);
    expect(next).toHaveBeenCalledWith();
  });

  it('allows navigation (stock-safe) when the capability is absent', () => {
    setAccount({ bloomwire_capabilities: {} });
    const next = vi.fn();
    redirectIfIntegrationsManaged(to, {}, next);
    expect(next).toHaveBeenCalledWith();
  });

  it('allows navigation (stock-safe) when the account is not loaded', () => {
    setAccount(undefined);
    const next = vi.fn();
    redirectIfIntegrationsManaged(to, {}, next);
    expect(next).toHaveBeenCalledWith();
  });
});
