import store from 'dashboard/store';
import { frontendURL } from 'dashboard/helper/URLHelper';

// Bloomwire (11B.7E): integrations are Ops-owned in managed mode. Redirect direct access to the integrations
// settings pages to the account dashboard when canAccessIntegrations is explicitly false. Stock-safe: if the
// capability is still missing after an account fetch (Bloomwire OFF / older backend), allow stock behavior.
const canAccessIntegrationsFor = account =>
  account?.bloomwire_capabilities?.canAccessIntegrations;

export const redirectIfIntegrationsManaged = async (to, _from, next) => {
  const { accountId } = to.params;
  const numericAccountId = Number(accountId);
  let account = store.getters['accounts/getAccount'](numericAccountId);
  let canAccess = canAccessIntegrationsFor(account);

  if (canAccess === undefined) {
    try {
      await store.dispatch('accounts/get', { silent: true });
      account = store.getters['accounts/getAccount'](numericAccountId);
      canAccess = canAccessIntegrationsFor(account);
    } catch {
      canAccess = undefined;
    }
  }

  if (canAccess === false) {
    next(frontendURL(`accounts/${accountId}/dashboard`));
  } else {
    next();
  }
};
