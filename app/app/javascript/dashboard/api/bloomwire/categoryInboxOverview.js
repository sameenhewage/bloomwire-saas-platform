import ApiClient from '../ApiClient';

// Phase 17F.1: read-only client for the administrator "Categories & Inboxes" overview. Maps to the singular
// account-scoped resource GET /api/v1/accounts/:accountId/bloomwire/category_inbox_overview (controller #show).
// Read-only by design: only `get()` is used; no create/update/delete for this managed, safe-DTO overview.
class CategoryInboxOverviewAPI extends ApiClient {
  constructor() {
    super('bloomwire/category_inbox_overview', { accountScoped: true });
  }
}

export default new CategoryInboxOverviewAPI();
