import { frontendURL } from '../../../helper/URLHelper';
import BloomwireOverview from './Overview.vue';

export const routes = [
  {
    path: frontendURL('accounts/:accountId/bloomwire/overview'),
    name: 'bloomwire_overview',
    meta: {
      permissions: ['administrator', 'agent', 'custom_role'],
    },
    component: BloomwireOverview,
  },
];
