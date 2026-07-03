import { frontendURL } from '../../../../helper/URLHelper';

import SettingsWrapper from '../SettingsWrapper.vue';
import Index from './Index.vue';
import { redirectIfCategoryAdminDisabled } from './categoryInboxes.routeGuards';

// Phase 17F.1: administrator-only, READ-ONLY "Categories & Inboxes" overview. Admin-only via route meta AND gated
// by the opt-in canAccessCategoryAdmin capability (beforeEnter redirects to the dashboard when it is not granted —
// agent, feature OFF, Bloomwire OFF, or older backend). The backend controller remains the enforcement boundary.
export default {
  routes: [
    {
      path: frontendURL('accounts/:accountId/settings/category-inboxes'),
      component: SettingsWrapper,
      children: [
        {
          path: '',
          name: 'settings_category_inboxes',
          meta: {
            permissions: ['administrator'],
          },
          beforeEnter: redirectIfCategoryAdminDisabled,
          component: Index,
        },
      ],
    },
  ],
};
