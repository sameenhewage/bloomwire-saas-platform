# Bloomwire Business-Owner Permission Matrix (Phase 11B.7 — COMPLETE)

Canonical **product permission contract** for Bloomwire **managed mode**, now **implemented and
runtime-validated** (Phase 11B.7A–E + 11B.7R). It corrected the permission *model* that Phase 11B (PR #43–#48
+ the 11B.6 UI hiding) had hardened too broadly (account control-plane blocked ⇒ agent management blocked
too). The product intent — now realized — for **people/visibility inside the business's own workspace**:

> The business owner/admin has **100% transparency and people-management inside their own account**.
> Only **platform / provider / channel / bot / integration SETUP** is **Bloomwire Ops-owned**.

**Hard rule (unchanged).** The backend `403` is the security boundary (see `backend-guard-map.md`); UI hiding
is cosmetic / UX + defense-in-depth (see `ui-hiding-source-of-truth.md`). This matrix is the **source of
truth for which side of that boundary each surface belongs on**, as shipped through Phase 11B.7.

- **Baseline:** `version_1 @ a8023a78` (PR #58 merge — Phase 11B.7A–E complete), runtime-validated on
  `dev.unecast.com` (11B.7R PASS + exit gate). Prior planning baseline was `3526efa` (PR #52).
- **Toggle seam:** `Bloomwire::Features` (all OFF by default; master AND-gates). OFF ⇒ stock Chatwoot.

> **Phase 12 scope note.** With Phase 11B complete, the next phase — **Phase 12 — is WhatsApp E2E**, **not** an
> Ops Console / users-&-roles management page. This permission model is the foundation Phase 12 builds on; no
> further account-permission UI is in scope for Phase 12.

---

## Roles

| Role | Chatwoot identity |
|---|---|
| **Business Owner / Business Admin** | account user with role `administrator` |
| **Bloomwire SuperAdmin / Ops** | `SuperAdmin` (STI `User`, `/super_admin` console) |
| **Agent** | account user with role `agent` |

---

## 1. Business Owner / Admin — ALLOWED (inside their own account)

| Capability | Status (shipped) | Slice / PR |
|---|---|---|
| View **all inboxes / conversations** in their account | **allowed** | — |
| View **all agents / team members** | **allowed** | — |
| **Create / manage agents** (add / edit / delete / invite) — *subject to the stock Enterprise usage limit* | **ALLOWED — restored** | **11B.7B / PR #55** |
| **Create / manage teams** | **allowed (stock)** — confirmed not regressed | **11B.7B / PR #55** |
| 100% transparency inside their own workspace (read everything in their account) | **allowed** | — |
| Self-service kept from prior phases: `reset_secret`, `sync_templates`, WhatsApp **health read**, conversations/contacts reads, live-call/conference | allowed (Tier-B) | — |

## 2. Business Owner / Admin — BLOCKED (Bloomwire Ops-owned)

| Restricted capability | Backend boundary (shipped) | UI (shipped) | Slice / PR |
|---|---|---|---|
| Change the **registered business / account name** after registration | `accounts#update` blocked (PR #43) | name + locale/domain/support-email **readonly/disabled** + managed helper; Save hidden | **11B.7A / PR #54** |
| Create **inboxes / channels** — **any** type, including `web_widget` / `api` | **all** `inboxes#create` blocked (`restrict_inbox_creation!`, PR #56) on top of PR #40/#44/#46 | "Add Inbox" hidden; channel cards + direct create routes → managed-state | **11B.7C / PR #56** |
| Configure **provider channels** (FB/IG/X/TikTok/Google/MS/Twilio/Shopify/email/SMS/LINE/Telegram/voice) | blocked (PR #44/#46) | UI hidden (11B.6C) | done |
| Configure **WhatsApp** setup / webhooks / provider credentials / reconfigure | blocked (PR #40/#48) | UI hidden (11B.6C/D) | done |
| Add / manage **bots** (agent bots) + inbox-level bot set/disconnect | blocked (`BLOOMWIRE_RESTRICT_BOT_MANAGEMENT`, PR #57) | Bots sidebar hidden + page route-blocked; Add/Edit/Delete/reset hidden; BotConfiguration hidden | **11B.7D / PR #57** |
| Access / manage **integrations** | connect/config mutation blocked (PR #47); **catalog read intentionally open for runtime** | Integrations sidebar hidden; routes redirect to dashboard | **11B.7E / PR #58** |
| Manage Bloomwire / platform-owned setup | Ops/SuperAdmin only | — | — |
| Account **webhooks** add/edit/delete (platform integration plumbing) | blocked (PR #43) — **stays Ops-owned** | UI hidden (11B.6B) | unchanged |

> **Account control-plane split (PR #43 → corrected in 11B.7B/PR #55 — DONE).** PR #43 originally treated
> `accounts#update`, `agents#*`, and `webhooks#*` as one "account control-plane" block. Phase 11B.7B split it:
> **`agents#*` is now ALLOWED** (stock Enterprise usage limit applies); **`accounts#update` (name) and
> `webhooks#*` stay BLOCKED**.

## 3. Bloomwire SuperAdmin / Ops

| Capability | Status |
|---|---|
| Manage platform structure + setup, business setup status, channel/WhatsApp/inbox setup | Ops-owned (intended) |
| Know business structure: **owners, agents, teams, plan usage, limits** | Ops-visible (structure/metadata, not conversation content) |
| **Read customer conversations by default** | **MUST NOT** — privacy boundary (`PRIVACY_HARDENING`); any Ops conversation access must be explicit/audited, out of scope here |

## 4. Agent

| Capability | Status |
|---|---|
| Access only **assigned / allowed** inboxes & conversations per account rules | allowed (stock policies) |
| Admin / setup / platform controls | **not accessible** (stock role gating; unchanged by 11B.7) |

---

## 5. Plan-limit requirement (agents / teams) — resolved in 11B.7B

Agent creation is **subject to the existing stock Enterprise usage limit** — **no fake billing was invented**:

- 11B.7B kept the stock `AgentsController#validate_limit` / `validate_limit_for_bulk_create`, which read
  `Account#usage_limits[:agents]` (Enterprise `PlanUsageAndLimits`: `custom_attributes['subscribed_quantity']`
  → `account.limits['agents']` → `InstallationConfig['ACCOUNT_AGENTS_LIMIT']` → default). Over-limit ⇒ **402**.
- Removing the Bloomwire account-control guard from `AgentsController` simply lets this **pre-existing** limit
  hook apply; Ops can set a per-plan agent limit via `account.limits['agents']` / `ACCOUNT_AGENTS_LIMIT`.
- Teams have no stock numeric limit and are stock-allowed. No unbounded-creation-while-claiming-a-limit issue.

---

## 6. Corrections — RESOLVED (merged + validated)

| Surface | Pre-11B.7 behavior | Resolution (shipped) | Slice / PR |
|---|---|---|---|
| **Agents** create/update/destroy/bulk_create | Backend **403** (PR #43); UI add/edit/delete **hidden** (PR #50) | **Un-blocked** for business admin; UI restored; stock Enterprise usage limit applies (402) | **11B.7B / PR #55** |
| **Teams** management | Stock-allowed; not Bloomwire-touched | Kept allowed; UI confirmed not regressed | **11B.7B / PR #55** |
| **Account name** | `accounts#update` **403** (PR #43); save button hidden (PR #50) | Name (+ locale/domain/support-email) **readonly/disabled** + managed-by-Bloomwire helper | **11B.7A / PR #54** |
| **Inbox creation** (`web_widget` / `api`) | self-service create was **allowed** | **All** inbox creation blocked (`restrict_inbox_creation!`); Add Inbox hidden; cards/routes managed-state | **11B.7C / PR #56** |
| **Bots** | **unguarded**; "Add Bot" visible | Backend **403** (`BLOOMWIRE_RESTRICT_BOT_MANAGEMENT`) on reads/writes/reset + inbox set/disconnect; UI hidden/route-blocked | **11B.7D / PR #57** |
| **Integrations** | Connect/config **403** (PR #47), but catalog/detail pages reachable; sidebar visible | Sidebar hidden + routes redirect; catalog read **intentionally open** (runtime); writes stay 403 | **11B.7E / PR #58** |

> **Nuance preserved (11B.7C vs PR #52).** PR #52 (11B.6D) hides **delete** for managed/provider inboxes and
> keeps **web_widget/API delete visible**. 11B.7C changed **creation** only — self-service `web_widget`/`API`
> **delete stays as PR #52 shipped** (unchanged).

---

## 7. Implementation slices — all merged

| Slice | PR | Merge SHA | Status |
|---|---|---|---|
| **11B.7-DOC** (this doc) | #53 | — | merged |
| **11B.7A** — Account name immutable UX | #54 | `ea16eb6` | merged |
| **11B.7B** — Restore agents/teams management | #55 | `38b46bd` | merged |
| **11B.7C** — All inbox creation Ops-owned | #56 | `d8099de` | merged |
| **11B.7D** — Bots Ops-owned | #57 | `1872037` (feature `f8138de`) | merged |
| **11B.7E** — Integrations Ops-owned | #58 | `a8023a78` (features `de42d74` + `c49ea80`) | merged |
| **11B.7R** — Combined runtime/security validation | — | `a8023a78` | **PASS** |

## 8. Corrected guard map (END STATE — achieved on `a8023a78`)

| Surface | Business Admin (managed mode) | Agent | Ops |
|---|---|---|---|
| View inboxes/conversations/agents/teams (own account) | **allow** | scoped | structure-visible |
| Agents create/manage | **allow (stock usage limit)** | block | manage |
| Teams create/manage | **allow** | block | manage |
| Account name change | **block** | block | manage |
| Account webhooks | **block** | block | manage |
| Inbox/channel create (any) | **block** | block | manage |
| Provider / WhatsApp setup/reconfigure | **block** | block | manage |
| Bots add/manage (+ inbox-level set/disconnect) | **block** | block | manage |
| Integrations access/manage (admin surface) | **block** | block | manage |
| Integrations catalog read (runtime) | allow (open by design) | allow | allow |
| Customer conversation content | allow (own account) | scoped | **block by default** |

---

*Phase 11B.7 is **complete**: every slice (11B.7A–E) shipped as its own PR with failing-test-first backend
request specs for each block and frontend unit tests for each UI change; **11B.7R** validated the deployed
result on `dev.unecast.com` (`a8023a78`, PASS). This doc-sync brings the canonical docs to that merged
reality. **Next: Phase 12 = WhatsApp E2E** (not an Ops Console / users-&-roles page).*
