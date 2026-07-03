import { redirectIfCategoryAdminDisabled } from '../categoryInboxes.routeGuards';
import store from 'dashboard/store';
import { frontendURL } from 'dashboard/helper/URLHelper';

vi.mock('dashboard/store', () => ({
  default: { getters: {}, dispatch: vi.fn() },
}));

// Phase 17F.1: the "Categories & Inboxes" page is admin-only AND gated by canAccessCategoryAdmin (opt-in). The
// guard must ALLOW only on an explicit `true`, and redirect to the dashboard otherwise (agent, feature OFF, or an
// older backend that never sends the capability). This mirrors the integrations route guard but inverted (opt-in).
describe('redirectIfCategoryAdminDisabled', () => {
  const to = { params: { accountId: '7' } };
  let next;

  const setCapability = value => {
    store.getters = {
      'accounts/getAccount': () => ({
        bloomwire_capabilities:
          value === undefined ? {} : { canAccessCategoryAdmin: value },
      }),
    };
  };

  beforeEach(() => {
    next = vi.fn();
    store.dispatch = vi.fn().mockResolvedValue();
  });

  it('calls next() (allow) when canAccessCategoryAdmin is explicitly true', async () => {
    setCapability(true);
    await redirectIfCategoryAdminDisabled(to, {}, next);
    expect(next).toHaveBeenCalledWith();
  });

  it('redirects to the account dashboard when the capability is explicitly false (agent / feature OFF)', async () => {
    setCapability(false);
    await redirectIfCategoryAdminDisabled(to, {}, next);
    expect(next).toHaveBeenCalledWith(frontendURL('accounts/7/dashboard'));
  });

  it('refetches the account and still redirects when the capability is absent (older backend)', async () => {
    setCapability(undefined);
    await redirectIfCategoryAdminDisabled(to, {}, next);
    expect(store.dispatch).toHaveBeenCalledWith('accounts/get', {
      silent: true,
    });
    expect(next).toHaveBeenCalledWith(frontendURL('accounts/7/dashboard'));
  });
});
