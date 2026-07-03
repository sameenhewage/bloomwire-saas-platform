import store from 'dashboard/store';
import { frontendURL } from 'dashboard/helper/URLHelper';

// Phase 17F.1: the "Categories & Inboxes" overview is admin-only AND gated by the opt-in canAccessCategoryAdmin
// capability (admin + BLOOMWIRE_CATEGORY_ADMIN_UI on). Unlike the integrations guard (stock-safe, redirect only on
// an explicit `false`), this is an OPT-IN managed surface: allow ONLY on an explicit `true`, and redirect to the
// account dashboard otherwise (agent, feature OFF, Bloomwire OFF, or an older backend that omits the capability).
// This is UI gating only; the backend controller (admin-only + feature-gated 404) remains the enforcement boundary.
const canAccessCategoryAdminFor = account =>
  account?.bloomwire_capabilities?.canAccessCategoryAdmin;

export const redirectIfCategoryAdminDisabled = async (to, _from, next) => {
  const { accountId } = to.params;
  const numericAccountId = Number(accountId);
  let account = store.getters['accounts/getAccount'](numericAccountId);
  let canAccess = canAccessCategoryAdminFor(account);

  if (canAccess === undefined) {
    try {
      await store.dispatch('accounts/get', { silent: true });
      account = store.getters['accounts/getAccount'](numericAccountId);
      canAccess = canAccessCategoryAdminFor(account);
    } catch {
      canAccess = undefined;
    }
  }

  if (canAccess === true) {
    next();
  } else {
    next(frontendURL(`accounts/${accountId}/dashboard`));
  }
};
