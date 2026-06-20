# 03 — Feature Scope

## V1 scope (in)

- **Chatwoot-based omnichannel inbox foundation** — use Chatwoot CE as the
  conversation engine; do not replace its inbox UI.
- **Business tenant / account management** — create and manage tenants
  (1 Chatwoot account = 1 tenant).
- **Business profile metadata** — name, industry, status, contact info, etc.
  (Bloomwire-owned).
- **Plan / subscription metadata** — which plan a tenant is on and its status
  (metadata only in V1, not full billing automation).
- **Super admin dashboard** — Bloomwire operators view/manage all tenants.
- **Business owner dashboard** — owners see their tenant's key info and status.
- **Basic roles / permissions foundation** — backend-enforced role model
  (platform + tenant roles) with an initial permission set.
- **Audit logs** — record Bloomwire control-plane actions.
- **Usage analytics** — summaries sourced from Chatwoot data (no duplication).
- **WhatsApp setup flow** — guided connection of a WhatsApp channel
  (1 inbox = 1 channel).
- **Industry presets** — for **telecom**, **retail/e-commerce**, and
  **marketing agencies**.
- **CI/CD / deployment planning** — define how Bloomwire will build, test, and
  deploy (planning + pipeline foundation).

## Out of scope for V1

- **AI bot builder** — no conversational AI/bot construction tooling.
- **Full billing automation** — no automated invoicing/payment processing
  (plan metadata only).
- **Full SLA engine** — no complete SLA tracking/escalation system.
- **Native Dialog/Hutch deep integration** — no carrier-specific deep
  integrations.
- **Replacing the Chatwoot inbox UI** — agents use Chatwoot's inbox in V1.
- **Custom mobile app** — no native mobile client.

## Scope principle

Keep V1 a thin, working SaaS layer on top of a working Chatwoot. Anything that
duplicates Chatwoot data, depends on Chatwoot Enterprise, or expands beyond the
list above is out of scope until explicitly approved.
