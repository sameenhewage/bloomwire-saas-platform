# 02 — Core Flows

High-level user flows for V1. Each will later be delivered as a vertical slice.
Chatwoot remains the source of truth for conversation/contact/channel data;
Bloomwire adds SaaS metadata and control around these flows.

---

## 1. Business onboarding
1. Bloomwire Ops (or self-serve signup) creates a business tenant.
2. A Chatwoot account is provisioned to represent the tenant
   (1 account = 1 tenant).
3. Bloomwire captures business profile metadata (name, industry, plan, status).
4. Onboarding steps are tracked (channel setup, staff invite, preset selection).

## 2. Channel setup
1. Business Admin connects a customer channel (e.g. WhatsApp number).
2. Each channel maps to one Chatwoot inbox (1 inbox = 1 channel).
3. Channel status is reflected in the Bloomwire onboarding/usage surfaces.

## 3. Staff invitation
1. Business Owner/Admin invites staff by email.
2. Each invite is assigned a tenant role (Supervisor, Support Agent, etc.).
3. Roles are backend-enforced; staff map to Chatwoot users/account_users.

## 4. Customer conversation handling
1. Customer messages arrive on a connected channel → Chatwoot inbox.
2. Agents handle conversations in the Chatwoot inbox UI (not replaced in V1).
3. Bloomwire reads usage/metrics from Chatwoot reporting; it does not duplicate
   message history.

## 5. Campaign response handling
1. Campaign Manager runs a campaign (Chatwoot campaigns).
2. Inbound responses land as conversations in the relevant inbox.
3. Agents handle responses; Bloomwire tracks campaign-related usage metrics.

## 6. Audit and usage review
1. Auditor/Analyst reviews audit logs (Bloomwire-owned) and usage analytics.
2. Audit logs capture Bloomwire control-plane actions (role changes, plan
   changes, onboarding events).
3. Usage analytics summarize activity sourced from Chatwoot data, without
   copying raw conversation content.

## 7. Industry preset onboarding
1. During onboarding, the tenant selects an industry preset
   (telecom, retail/e-commerce, marketing agency).
2. The preset seeds sensible defaults (suggested labels, team structure,
   canned responses, onboarding checklist) appropriate to the industry.
3. Presets accelerate setup; they configure Chatwoot via supported mechanisms,
   they do not fork Chatwoot.
