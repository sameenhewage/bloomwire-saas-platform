# 01 — Users and Roles

Bloomwire has two role planes:

- **Platform roles** — Bloomwire operator staff who run the SaaS.
- **Tenant roles** — staff inside a customer business (one Chatwoot account =
  one Bloomwire tenant).

All permissions are **backend-enforced**. Frontend hiding is UX only, never the
security boundary.

---

## Platform roles (Bloomwire operator)

### Bloomwire Super Admin
- Full control of the platform and all tenants.
- Manages plans, feature flags, and platform-wide settings.
- Can view the list of all business tenants and their SaaS metadata.

### Bloomwire Operations / Admin Team
- Day-to-day platform operations: onboarding businesses, support, monitoring.
- Can manage tenants and subscriptions but not platform-destroying actions.

---

## Tenant roles (inside a business)

### Business Owner
- Owns the business tenant. Top authority within the tenant.
- Manages plan/subscription choices, billing contacts, and senior staff.

### Business Admin
- Administers the tenant: channels, staff, roles, settings.
- Cannot change platform-level configuration.

### Supervisor
- Oversees agents and conversation quality within the tenant.
- Can reassign conversations, view team performance.

### Support Agent
- Handles customer support conversations across connected channels.

### Sales Agent
- Handles sales-oriented conversations and leads.

### Campaign Manager
- Runs and monitors outbound/campaign responses.

### Analyst
- Reads usage analytics and reports; no write access to conversations.

### Auditor / Viewer
- Read-only access to audit logs and permitted data for compliance.

---

## Early permission examples (illustrative, backend-enforced)

| Capability | Super Admin | Ops/Admin | Business Owner | Business Admin | Supervisor | Support Agent | Analyst | Auditor |
|---|---|---|---|---|---|---|---|---|
| View all tenants | ✅ | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |
| Manage plans/flags | ✅ | partial | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |
| Manage tenant staff | ✅ | ✅ | ✅ | ✅ | ❌ | ❌ | ❌ | ❌ |
| Connect channels | ✅ | ✅ | ✅ | ✅ | ❌ | ❌ | ❌ | ❌ |
| Handle conversations | ❌ | ❌ | ✅ | ✅ | ✅ | ✅ | ❌ | ❌ |
| Run campaigns | ❌ | ❌ | ✅ | ✅ | ✅ | ❌ | ❌ | ❌ |
| View analytics | ✅ | ✅ | ✅ | ✅ | ✅ | partial | ✅ | partial |
| View audit logs | ✅ | ✅ | ✅ | partial | ❌ | ❌ | ❌ | ✅ |

> These are starting points for the roles/permissions foundation, not the final
> permission matrix. The final matrix is defined when the roles slice is built.
