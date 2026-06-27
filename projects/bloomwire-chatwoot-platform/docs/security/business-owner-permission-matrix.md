# Bloomwire Business-Owner Permission Matrix (Phase 11B.7)

Canonical **product permission contract** for Bloomwire **managed mode**. It corrects the permission *model*
that Phase 11B (PR #43–#48 + the 11B.6 UI hiding) hardened: that lockdown treated the business
owner/admin as a near-fully-restricted user (account control-plane blocked ⇒ agent management blocked too).
The product intent is the opposite for **people/visibility inside the business's own workspace**:

> The business owner/admin must have **100% transparency and people-management inside their own account**.
> Only **platform / provider / channel / bot / integration SETUP** is **Bloomwire Ops-owned**.

**Hard rule (unchanged).** The backend `403` is the security boundary (see `backend-guard-map.md`); UI hiding
is cosmetic / UX + defense-in-depth (see `ui-hiding-source-of-truth.md`). This matrix is the **source of
truth for which side of that boundary each surface belongs on** after Phase 11B.7.

- **Baseline:** `version_1 @ 3526efa` (PR #52 merge), runtime-validated on `dev.unecast.com`.
- **Toggle seam:** `Bloomwire::Features` (all OFF by default; master AND-gates). OFF ⇒ stock Chatwoot.

---

## Roles

| Role | Chatwoot identity |
|---|---|
| **Business Owner / Business Admin** | account user with role `administrator` |
| **Bloomwire SuperAdmin / Ops** | `SuperAdmin` (STI `User`, `/super_admin` console) |
| **Agent** | account user with role `agent` |

---

## 1. Business Owner / Admin — ALLOWED (inside their own account)

| Capability | Status today | Slice |
|---|---|---|
| View **all inboxes / conversations** in their account | allowed | — |
| View **all agents / team members** | allowed | — |
| **Create / manage agents** (add / edit / delete / invite) — *subject to Bloomwire plan limits* | **BLOCKED today (must be restored)** | **11B.7B** |
| **Create / manage teams** — *subject to Bloomwire plan limits* | allowed (stock) — confirm not regressed | **11B.7B** |
| 100% transparency inside their own workspace (read everything in their account) | allowed | — |
| Self-service kept from prior phases: `reset_secret`, `sync_templates`, WhatsApp **health read**, conversations/contacts reads, live-call/conference | allowed (Tier-B) | — |

## 2. Business Owner / Admin — BLOCKED (Bloomwire Ops-owned)

| Restricted capability | Backend boundary today | UX gap | Slice |
|---|---|---|---|
| Change the **registered business / account name** after registration | `accounts#update` blocked (PR #43) | name field still **looks editable**; only the save button is hidden (PR #50) | **11B.7A** |
| Create **inboxes / channels** — **any** type, including `web_widget` / `api` | provider/WhatsApp create blocked (PR #40/#44/#46); **`web_widget` / `api` create is still ALLOWED** | "Add Inbox" still reachable for self-service types | **11B.7C** |
| Configure **provider channels** (FB/IG/X/TikTok/Google/MS/Twilio/Shopify/email/SMS/LINE/Telegram/voice) | blocked (PR #44/#46) + UI hidden (11B.6C) | — | done |
| Configure **WhatsApp** setup / webhooks / provider credentials / reconfigure | blocked (PR #40/#48) + UI hidden (11B.6C/D) | — | done |
| Add / manage **bots** (agent bots) | **NOT blocked today** | "Add Bot" / bot management still visible & usable | **11B.7D** |
| Access / manage **integrations** | connect/config mutation blocked (PR #47); **catalog/detail pages still reachable** | Integrations sidebar entry + routes still accessible | **11B.7E** |
| Manage Bloomwire / platform-owned setup | Ops/SuperAdmin only | — | — |
| Account **webhooks** add/edit/delete (platform integration plumbing) | blocked (PR #43) + UI hidden (11B.6B) — **stays Ops-owned** | — | unchanged |

> **Account control-plane split (correction to PR #43).** PR #43 currently treats `accounts#update`,
> `agents#*`, and `webhooks#*` as one "account control-plane" block. Phase 11B.7 splits it: **`agents#*`
> moves to ALLOWED** (with plan limits, 11B.7B); **`accounts#update` (name) and `webhooks#*` stay BLOCKED**.

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

## 5. Plan-limit requirement (agents / teams)

Agent and team creation are **"subject to Bloomwire plan limits."** However:

- **`CONTEXT.md` states pricing/billing is out of scope**, and **no plan-limit / billing model exists today**.
- **11B.7B must NOT invent a fake billing/plan system.** Acceptable approaches, decided **before** coding:
  1. **Minimal enforcement hook** that reads an existing or explicitly-placeholder limit source (e.g. an
     installation/account config value) and 403s past it, with an **audit-log** of agent/team mutations; or
  2. if no credible source exists, ship the **management restore without a hard limit**, behind a clearly
     documented **placeholder hook + risk note** ("plan-limit not yet enforced — Ops trusts the business").
- Either way: **do not silently allow unbounded creation while claiming a limit exists.** State the chosen
  option and its risk in the 11B.7B PR.

---

## 6. Current gaps — guards / PRs needing correction

| Surface | Current behavior | Required correction | Slice |
|---|---|---|---|
| **Agents** create/update/destroy/bulk_create | Backend **403** (PR #43); UI add/edit/delete **hidden** (PR #50) | **Un-block** for business admin; restore UI; add plan-limit hook + audit | **11B.7B** |
| **Teams** management | Stock-allowed; not Bloomwire-touched | Keep allowed; confirm UI not regressed; apply plan-limit hook | **11B.7B** |
| **Account name** | `accounts#update` **403** (PR #43); save button hidden (PR #50) | Make the name field **readonly / managed-by-Bloomwire** (clear UX, not a hidden save) | **11B.7A** |
| **Inbox creation** (`web_widget` / `api`) | **Allowed** (PR #46/#48 deliberately leave self-service create) | **Block all** inbox creation in managed mode; hide "Add Inbox"; block direct route + API | **11B.7C** |
| **Bots** | **Allowed** — no guard; "Add Bot" visible | Add backend **403** for bot create/update/destroy; hide bot management UI | **11B.7D** |
| **Integrations** | Connect/config **403** (PR #47), but catalog/detail **pages reachable**; sidebar entry visible | Hide Integrations sidebar entry; route-block with safe managed state; decide catalog-read = 403 vs read-only (document first) | **11B.7E** |

> **Important nuance for 11B.7C vs PR #52.** PR #52 (11B.6D) hides **delete** for managed/provider inboxes and
> keeps **web_widget/API delete visible**. 11B.7C changes **creation** only. Unless the product owner decides
> otherwise, **self-service web_widget/API *delete* stays as PR #52 shipped** — 11B.7C does **not** silently
> change delete behavior.

---

## 7. Implementation slices (one branch + one PR each; no mega-PR)

| Slice | Scope | Touches |
|---|---|---|
| **11B.7-DOC** (this doc) | Permission matrix + correction plan | docs only |
| **11B.7A** | Account name immutable UX (readonly / managed message) | frontend only (backend already blocks) |
| **11B.7B** | Restore agents/teams management for business admin + plan-limit hook/audit | backend (relax PR #43 agents; add limit hook) + frontend (restore PR #50 agent UI) |
| **11B.7C** | All inbox creation Ops-owned | backend (block web_widget/api create) + frontend (hide Add Inbox, route/API block) |
| **11B.7D** | Bots Ops-owned | backend (403 bot create/update/destroy) + frontend (hide bot management) |
| **11B.7E** | Integrations Ops-owned | frontend (hide sidebar + route-block) + backend decision on catalog read |
| **11B.7R** | Combined runtime / security validation after merges | validation only |

## 8. Target corrected guard map (end state)

| Surface | Business Admin (managed mode) | Agent | Ops |
|---|---|---|---|
| View inboxes/conversations/agents/teams (own account) | **allow** | scoped | structure-visible |
| Agents create/manage | **allow (plan-limited)** | block | manage |
| Teams create/manage | **allow (plan-limited)** | block | manage |
| Account name change | **block** | block | manage |
| Account webhooks | **block** | block | manage |
| Inbox/channel create (any) | **block** | block | manage |
| Provider / WhatsApp setup/reconfigure | **block** | block | manage |
| Bots add/manage | **block** | block | manage |
| Integrations access/manage | **block** | block | manage |
| Customer conversation content | allow (own account) | scoped | **block by default** |

---

*Stage 1 is documentation only — no app/runtime behavior changes. Each slice (11B.7A–E) lands as its own PR
with failing-test-first, backend request specs for every block, frontend unit tests for every UI change, and
`11B.7R` validates the deployed result.*
