# Research — Telecom Use Cases

Telecom support teams (Dialog/Hutch-style operators) handle very high
conversation volumes. This documents representative use cases, not a carrier
integration design.

## Typical conversation types

- **Billing & payments** — bill queries, payment confirmation, plan charges.
- **Activation & provisioning** — SIM/eSIM activation, number porting status.
- **Plan & package changes** — upgrades, add-ons, data packs.
- **Complaints & faults** — network issues, outage reports, escalation.
- **Retention** — cancellation requests, win-back offers.

## Operational characteristics

- **High volume, spiky load** — promotions and outages cause surges.
- **Tiered support** — front-line agents + supervisors + escalation teams.
- **Strict compliance** — identity verification, data privacy, audit needs.
- **SLA pressure** — response/resolution time targets.

## How Bloomwire (on Chatwoot) fits

- **WhatsApp as a primary channel** for billing/activation/complaints.
- **Teams + supervisors** map to Chatwoot teams and Bloomwire supervisor roles.
- **Industry preset (telecom)** seeds labels (billing, activation, complaint),
  team structure, and canned responses.
- **Audit logs + usage analytics** support compliance and volume reporting.

## Out of scope (V1)

- Native deep integration with Dialog/Hutch carrier systems.
- Full SLA engine (only basic metrics in V1).
- Automated billing actions.
