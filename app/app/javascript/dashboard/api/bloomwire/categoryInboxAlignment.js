import ApiClient from '../ApiClient';

// Phase 17F.3: client for the administrator guided staff-access alignment. Maps to the account-scoped resource
// POST /api/v1/accounts/:accountId/bloomwire/category_inbox_alignment (controller #create). Additive only — it
// sends { team_id, inbox_id, user_ids } and the backend adds those users to BOTH the Team and the Inbox in one
// transaction. No read/update/delete; no persisted Category↔Inbox mapping.
class CategoryInboxAlignmentAPI extends ApiClient {
  constructor() {
    super('bloomwire/category_inbox_alignment', { accountScoped: true });
  }
}

export default new CategoryInboxAlignmentAPI();
