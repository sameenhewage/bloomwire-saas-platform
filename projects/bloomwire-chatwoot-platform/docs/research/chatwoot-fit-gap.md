# Research — Chatwoot Fit / Gap Analysis

Assessment of what Chatwoot Community Edition already provides versus what
Bloomwire must add. Used to keep the SaaS layer thin and avoid duplication.

## What Chatwoot CE already covers (good fit)

| Capability | Chatwoot CE |
|---|---|
| Omnichannel inbox (WhatsApp, web, email, social) | ✅ |
| Accounts, users, account_users | ✅ |
| Inboxes, inbox_members, channels | ✅ |
| Contacts, contact_inboxes | ✅ |
| Conversations, messages | ✅ |
| Teams, labels | ✅ |
| Campaigns | ✅ |
| Automation rules | ✅ |
| Reporting events / basic reporting | ✅ |

➡️ **Bloomwire treats all of the above as the source of truth and does not
re-implement or duplicate them.**

## Gaps Bloomwire must fill (SaaS layer)

| Need | In Chatwoot CE? | Bloomwire adds |
|---|---|---|
| Multi-tenant SaaS management | partial (accounts exist, no SaaS layer) | tenant management on top |
| Business profile metadata | ❌ | `bloomwire_` business profile |
| Plans / subscriptions | ❌ | plan/subscription metadata |
| Feature flags per tenant | ❌ | Bloomwire feature flags |
| Custom roles/permissions (backend-enforced) | partial (basic roles) | richer role/permission foundation |
| Audit logs (control plane) | partial | Bloomwire audit logs |
| Usage analytics (SaaS view) | partial reporting | SaaS usage analytics |
| Guided onboarding steps | ❌ | onboarding tracking |
| Industry presets | ❌ | telecom / retail / agency presets |
| SaaS deployment pipeline | n/a | Docker + GH Actions + VPS plan |

## Constraints confirmed by this analysis

- **No Chatwoot Enterprise** code/features are used; gaps are filled by
  Bloomwire-owned code, not Enterprise.
- **No data duplication** — Bloomwire references Chatwoot entities, never copies
  conversation/message/contact history.
- **Safe DTOs** — Bloomwire surfaces avoid exposing raw Chatwoot internal IDs,
  phone numbers, or tokens.

## Conclusion

Chatwoot CE is a strong fit for the conversation engine. Bloomwire's job is a
**thin SaaS/business control layer**: tenancy, plans, roles, audit, analytics,
onboarding, and presets — nothing that re-implements Chatwoot or depends on
Enterprise.
