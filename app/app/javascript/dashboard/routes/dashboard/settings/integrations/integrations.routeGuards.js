import store from 'dashboard/store';
import { frontendURL } from 'dashboard/helper/URLHelper';

// Bloomwire (11B.7E): integrations are Ops-owned in managed mode. Redirect direct access to the integrations
// settings pages to the account dashboard when canAccessIntegrations is explicitly false. Stock-safe: a
// missing capability (Bloomwire OFF, older backend, account not yet loaded) allows access (stock behavior).
export const redirectIfIntegrationsManaged = (to, _from, next) => {
  const { accountId } = to.params;
  const account = store.getters['accounts/getAccount'](Number(accountId));
  const canAccess = account?.bloomwire_capabilities?.canAccessIntegrations;
  if (canAccess === false) {
    next(frontendURL(`accounts/${accountId}/dashboard`));
  } else {
    next();
  }
};
