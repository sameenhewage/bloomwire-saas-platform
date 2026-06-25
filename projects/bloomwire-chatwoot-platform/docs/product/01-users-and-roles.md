# 01 — Users and Roles

Grounded in Chatwoot's `Account` / `User` / `AccountUser` model (decision register D-01 / D-02).

| Role | Who | Capabilities |
|---|---|---|
| **Bloomwire Ops / SuperAdmin** | Internal operator | Onboard managed WhatsApp numbers, manage the routing registry, toggle Bloomwire features, support-access (audited). |
| **Tenant Administrator** | Business owner / admin | Manage their account, inboxes, agents (native Chatwoot admin). Native WhatsApp setup is **restricted** when the account is managed. |
| **Tenant Agent** | Business staff | Handle conversations in assigned inboxes (native Chatwoot agent). |
| **Customer** | End user on WhatsApp | Messages the business number; never logs in. |

## Notes

- A SuperAdmin is **not** automatically an account member (S-05). Self-add and impersonation must be
  restricted / audited (privacy phase).
- A distinct tenant **owner** role and/or reseller-above-account hierarchy is an open question (Q-09 / Q-10), deferred.
