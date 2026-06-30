# AGENTS.md

Operating rules for AI agents working in this repository.

This file is the single source of truth for **how** AI agents behave here. Every
agent and every AI-assisted session must follow these rules. When in doubt,
re-read this file before acting.

---

## Core principles

- **Context before code.** Always understand the current task, the affected
  area, and existing conventions before making any change.
- **No random coding.** Do not write, refactor, or "improve" code that is not
  part of an explicit, agreed task.
- **Controlled autonomy.** For an approved implementation or validation task,
  agents may investigate, edit, test, push a feature branch, and open a PR
  without asking for every small step. They must still stop for risky decisions,
  scope changes, production changes, destructive operations, or merges.
- **Ask when unclear.** If requirements are ambiguous, ask clarifying questions
  before implementing. A short question now beats a wrong implementation later.
- **Small, reversible changes.** Prefer the smallest change that fully solves
  the task. Large changes must be split.
- **Vertical slices.** Deliver complete, working slices (UI + API + validation +
  data + tests when relevant) rather than horizontal half-features.
- **Explain assumptions.** State any assumption you make before acting on it.

---

## Branch, commit, and PR rules

- Work on the current branch unless the task explicitly asks for a new feature
  branch or the current branch is a protected/base branch.
- Never push directly to `main`, `master`, `version_1`, or any release/version
  branch unless the user explicitly instructs it for that exact action.
- For approved implementation work, agents may create commits on the current
  feature branch or a task-specific feature branch.
- Do not create commits for pure analysis/review tasks unless the user asks for
  a file change.
- Do not merge PRs unless the user explicitly approves the exact PR merge.
- Do not start CI/CD, production deployment, release tagging, or versioning work
  unless the user explicitly starts that phase.
- If a PR is opened, stop after reporting the PR URL and evidence. Do not merge.

---

## What every agent MUST do

1. **Graph-first — read the graphify code graph before acting**
   - Before **any** analysis, design, bugfix, or implementation, establish the
     current situation from the **graphify** code graph — never from memory or
     assumption. *Read the graph, understand reality, then act.*
   - **Read** the relevant slice for what you will touch:
     `graphify explain "<Symbol>"`, `graphify query "<intent>"`, or
     `graphify path "<A>" "<B>"` (quick map: grep node labels in
     `app/graphify-out/graph.json`).
   - **No manual updates needed.** The graph **auto-refreshes** via git hooks
     (`graphify hook` — post-commit + post-checkout, incremental, cached, **$0**;
     redirected to the `app/` graph root via `graphify-out/.graphify_root`). Do
     **not** run `graphify update` by hand. Only if you suspect the graph is stale
     — e.g. large *uncommitted* changes in the area you will touch — confirm
     against source (or, as a one-off, run `graphify update .` from `app/`).
   - **Ground-truth caveat** — the graph is AST-only (code symbols, not string
     literals) and the `projects/<name>/docs` are **not** in it unless ingested.
     Confirm against source, and ingest docs with `graphify add projects/<name>/docs`
     when the task depends on them.

2. **Read context first**
   - Read `AGENTS.md` (this file) and `CLAUDE.md`.
   - **For Bloomwire work, read `docs/bloomwire/SESSION-LOG.md` first** — the living continuity
     journal (current state · how-we-work conventions · recent sessions), so context is never lost
     across chats. **Update its "Current State" and prepend a journal entry when you finish a
     slice/phase.**
   - Read the relevant task brief, issue, or PRD.
   - **When the work touches a project under `projects/<name>/`, read that
     project's `CONTEXT.md` first** — it carries project-specific contracts that
     *extend* (never override) the global engineering rules below.
   - Inspect the existing code in the affected area.

3. **Work in vertical slices**
   - One slice = one thin, end-to-end piece of value that can be tested.
   - Keep each slice independently reviewable.

4. **Keep changes small**
   - If a task grows beyond a small slice, stop and split it.
   - Avoid unrelated edits in the same change.

5. **Use the right validation mode**
   - For implementation tasks, write or update failing tests first where
     practical, prove the failure is for the right reason, then implement the
     smallest safe change.
   - For runtime-validation-only tasks, do not add unnecessary tests. Validate
     the already-implemented behavior on the real target stack and report
     evidence.

6. **Report after every task**
   Every completed task must end with the **Final PASS Report Standard**
   (Engineering rule 11 below): requirement understood, root cause (for fixes),
   files read, files changed, tests added/updated, proof the tests failed before
   the fix (or an honest reason they could not), runtime/browser/network proof
   where relevant, security proof where relevant, what was **not** changed,
   remaining risks, and the next recommended step.

7. **Preserve conventions**
   - Match existing structure, naming, and style.
   - Do not introduce new patterns, libraries, or tools without approval.

---

## What every agent MUST NOT do

- **Do not modify architecture without explicit approval.** Boundaries, data
  ownership, auth model, and tech stack are not changed casually.
- **Do not create product or architecture docs at the repo root.**
  Root `docs/` is for AI team / workflow docs only — never create root-level
  `docs/product/` or root-level `docs/adr/`. A project's product docs, ADRs, and
  `CONTEXT.md` live inside that project under `projects/<project-name>/`
  (see "Documentation layout" under Agent skills).
- **Do not implement features without a clear issue or task.**
- **Do not install packages or add dependencies** without explicit approval.
- **Do not invent requirements.** If it is not specified, ask.
- **Do not leave the codebase in a broken state.**
- **Do not expose secrets.** Never print, log, commit, or echo `.env` values,
  tokens, passwords, private keys, app secrets, provider credentials, access
  tokens, or production credentials.
- **Do not run destructive data operations** without explicit approval. This
  includes `db:reset`, `db:schema:load`, `docker compose down -v`, volume
  deletion, data deletion, or production/customer-data mutation.
- **Do not mask a bug with a defensive patch before the root cause is proven**
  (see Engineering rule 3).
- **Do not return / claim PASS** on "tests pass", "build green", or "I added a
  guard" alone — PASS requires user-visible/runtime truth (Engineering rule 1).

---

## Engineering rules (global, mandatory)

These apply to **all** work — features, bugfixes, UI, API, DB, and agent
workflows — across **every** project. They are **generic** engineering standards;
project-specific contracts live in each project's `CONTEXT.md` (rule 12). No task
is **PASS** unless these gates are satisfied. Every agent and workflow inherits
these rules by reading this file first.

### 1. Product Truth Gate
Validate the real product/user requirement **before** coding. A feature is **not**
done because tests pass, types pass, the build passes, the API responds, docs were
updated, or a guard/cache/de-dupe was added. It is done **only** when:
- the browser / runtime / **user-visible behavior** matches the actual requirement,
- the **data source of truth** is correct, and
- the end-to-end **workflow behaves correctly**.

Before coding, write the acceptance truth in plain language:
**"User expects X. Current system does Y. Done means Z."**

### 2. Root Cause Gate
Before fixing any bug, **prove** the root cause. Every bugfix must report:
1. current flow, 2. the **exact owner** of the behavior, 3. **why** the bug
happens, 4. whether it happens in **dev, production, or both**, 5. the **smallest
correct root fix**, 6. what was deliberately **not** changed. Never patch a
symptom first.

### 3. No Symptom Masking
Do not hide lifecycle, data-flow, state, or architecture bugs with broad
defensive patches **unless the root cause is first proven**. Not acceptable as a
**primary** fix: global request de-dupe, generic caches, broad guards, retries,
timeouts, silent fallbacks, extra loaders, duplicate state, extra sync jobs, new
tables. These are allowed **only** as supporting safety **after** the root cause
is fixed and the choice is justified.

### 4. Ownership
Every behavior has **one** clear owner — one owner loads a list, one selects the
default item, one loads the selected detail, one owns pagination, one owns sync,
one owns source-of-truth mapping. If two effects/services/components can trigger
the same action, **resolve ownership**; do not mask the duplicate outcome.

### 5. TDD Means Business Truth
Tests protect the **business contract**, not the current implementation.
- **Bad:** "current table has 4 rows → UI shows 4"; "the fetch was duplicated →
  de-dupe hides it"; "the component renders → test passes".
- **Good:** "8 valid source sessions → dashboard maps all 8 **or** explains safe
  exclusions"; "56 messages, page size 20 → initial load returns the latest 20,
  scroll-up loads the older 20"; "a filter change updates **exactly** the right
  surface, not the whole app".

Tests must **fail before** implementation where practical. If a failing test
cannot be produced because the behavior already works, **say so honestly** and
provide **runtime** proof instead.

### 6. Runtime Proof Gate
For UI/network/runtime behavior, unit tests are **not enough**. Provide the proof
the feature warrants: browser **Network tab** for API behavior; **DOM/screenshot**
for visual behavior; **console** check for frontend work; **dev *and* production**
build checks where lifecycle/build behavior can differ; **database verifier** for
DB/data-source work; **before/after counts** for analytics/data work; **security**
proof for API DTOs. **"Tests pass" alone is not PASS.**

### 7. Source-of-Truth Gate
Before any data feature, identify: which **table/API/service owns** the data;
which tables are **read-only**; which may be **written**; whether data is
**duplicated or indexed**; how **stale** data is detected; how **missing** data is
surfaced. Do **not** create duplicate tables or duplicate state without an
approved architecture decision (ADR).

### 8. Security / Safe DTO Gate
Browser/API responses must not expose raw sensitive/internal identifiers unless
explicitly approved. **Forbidden by default:** raw phone numbers, raw user IDs,
raw external contact IDs, raw vendor/session IDs, raw DB internals, raw transcript
source JSON, and raw `session_data`/`runs` not required by the UI. **Expose safe
DTOs only.**

### 9. No Over-Engineering
Use the **smallest correct fix**. Do not add new libraries, architecture, tables,
global abstractions, queues, caches, generic frameworks, or broad wrappers unless
the problem requires it **and** the decision is documented. If a simple ownership
fix solves it, do that.

### 10. Documentation / Decision Log Gate
Any meaningful behavior, architecture, data-source, workflow, or UX decision
updates the right level: root `AGENTS.md` / `CLAUDE.md` for global agent behavior;
project `CONTEXT.md` / project docs for project-specific rules; an **ADR /
technical-decision-log** for architecture decisions; workflow/template docs when
the process changes. **Never leave stale, contradictory docs.**

### 11. Final PASS Report Standard
Every final report includes: 1. requirement understood, 2. root cause, 3. files
read, 4. files changed, 5. tests added/updated, 6. proof the tests **failed before**
the fix (or an honest reason they could not), 7. runtime/browser/network proof
where relevant, 8. security proof where relevant, 9. what was **not** changed,
10. remaining risks, 11. next recommended step.
**Forbidden PASS:** "all tests pass" only; "build green" only; "I added a guard"
only; "looks good" without runtime proof.

### 12. Project-specific contracts live in the project
These global files hold **generic** engineering rules only. Project-specific
contracts (e.g. PEPPER ST. Chat Monitor WhatsApp behavior, realtime/sync rules)
live in that project's `CONTEXT.md` / project docs — **read it before working in a
project.** Keep at most a one-line illustrative example in the global files.

---

## Bloomwire Documentation Governance (mandatory)

Every Bloomwire-owned change must be **transparent and documented**. Future agents must not make
hidden or undocumented changes. _(Introduced in Phase 15E.1.)_

**When docs MUST be updated.** Any PR that changes **behavior, permissions, security, onboarding,
WhatsApp flow, APIs, UI flows, the data model, an operational process, or customer-facing behavior**
must update the relevant docs **in the same PR**:

- `docs/bloomwire/implementation-ledger.md`
- `docs/bloomwire/implementation-ledger.html`
- the Bloomwire change log (`docs/bloomwire/change-log.md`)
- the related **ADR / runbook** if the change affects architecture or operations (Bloomwire ADRs
  live under `projects/bloomwire-chatwoot-platform/docs/adr/`).

**A PR is NOT ready for approval if it changes Bloomwire behavior but does not update the
docs/changelog.** Docs-only PRs do not require a runtime deploy.

**Every ledger/changelog entry must include:** phase name · PR number · merge SHA (once known) ·
what changed · why it changed · what was intentionally **not** changed · validation evidence ·
residual risks / parked items.

**Security / permission / WhatsApp changes must explicitly state:** no secrets exposed · no
provider-credential mutation unless explicitly authorized · whether any WhatsApp/Meta **live** calls
were made · whether Enterprise code was touched.

**Invariants future agents must preserve** (do not break without a separate, approved design):

- do **not** use `users.type` for business/customer roles;
- do **not** add a `BusinessOwner` role without separate design;
- do **not** duplicate the chat/message source of truth;
- do **not** introduce an Enterprise dependency;
- keep the **WhatsApp-first** scope unless explicitly expanded.

**Definition of Done (Bloomwire change):** code implemented · tests passed · runtime/browser proof
when applicable · **docs updated** · **changelog updated** · residual risks recorded · **exact merge
SHA recorded after merge**.

---

## Strict QA gate (mandatory)

**No task, slice, phase, or PR is `PASS` / complete / merge-ready until an
independent strict-QA pass has verified it.** This gate sits on top of the
Engineering rules above and enforces the Final PASS Report Standard (rule 11). It
is **not optional** and applies to every project and every agent.

### 1. Task completion is not QA completion
- A builder / implementation agent may only say **"IMPLEMENTATION COMPLETE"** —
  never "PASS", "done", or "merge-ready".
- Only a **QA agent** may say **"QA PASS"**, and only after **independently**
  verifying the work — it must not trust the builder's claims.
- Only **after** QA PASS may the orchestrator declare **"phase PASS"** or
  **"merge-ready"**.

### 2. Mandatory QA after every task / slice
Before any commit, and before moving to the next slice, a QA gate must run and
cover:
- **Source / diff check** — read the real diff; every changed line is intended.
- **Tests + exact command output** — paste the real command and its result
  (e.g. `N examples, 0 failures`), not a paraphrase.
- **Security / permission check** — backend authorization proven for the change.
- **No-secret check** — no secret in diff, command output, logs, or docs.
- **Feature-OFF behavior check** — with the toggle OFF, behavior is stock/baseline.
- **No external / live-API-call proof** where applicable (no real Meta/WhatsApp).
- **Runtime / MCP or rendered-DOM proof** for any UI-visible change.
- **Regression impact check** — touched controllers / components / areas still pass.

### 3. Mandatory strict QA after every phase
Before pushing, opening a PR, or merging a PR, a **separate** QA pass must verify:
- PR / task scope matches the report.
- All changed files are expected.
- No unrelated or untracked files are included.
- Required specs reproduce locally.
- RuboCop / lint passes.
- UI / runtime evidence exists if UI changed.
- Backend authorization is proven.
- No secrets in diff / API / UI / docs / logs.
- No real Meta/WhatsApp calls unless explicitly approved.
- Bloomwire OFF behavior remains stock / inert.
- No duplicated Chatwoot conversations / messages / contacts.
- The report makes **no fake PASS claims**.
- The merge-gate status is described correctly — **conflict-free** and
  **review/status-blocked** are different states and must not be conflated.

### 4. QA sub-agents for large phases
For a large phase batch, the orchestrator must assign dedicated QA sub-agents:
- **Source / Diff QA Agent**
- **Test QA Agent**
- **Security / Privacy QA Agent**
- **Runtime / UI MCP QA Agent**
- **Docs / PR QA Agent**
- **Merge-Gate QA Agent**

### 5. PASS wording standard
The only allowed final states are:
- **IMPLEMENTATION COMPLETE** — code / docs done, QA not yet complete.
- **QA PASS** — independent QA passed.
- **PASS-BUT-BLOCKED** — QA passed, but branch protection / review / status blocks
  the merge.
- **FAIL** — any required evidence is missing, or a test / security / runtime check
  failed.

### 6. No fake PASS
Never claim:
- **runtime PASS** without runtime / MCP / rendered-DOM evidence,
- **live Meta/WhatsApp PASS** without real human-operated evidence,
- **security PASS** without backend authorization proof,
- **merge-ready** when GitHub branch protection / review / status is blocked.

### 7. QA report format
Every QA report must include:
- **Verdict:** QA PASS / PASS-BUT-BLOCKED / FAIL
- **Files read**
- **Files changed**
- **Commands run**
- **Test counts**
- **Runtime / MCP evidence** (or the reason it is not applicable)
- **Security proof**
- **No-secret proof**
- **Feature-OFF proof**
- **No-real-external-call proof**
- **Regression proof**
- **Remaining blockers**
- **What was not verified**

---

## Project bootstrap rule

Every generated project under `projects/<project-name>/` must start from a
required documentation skeleton, created **before any implementation begins**.
These files must exist inside the project folder:

- `projects/<project-name>/CONTEXT.md`
- `projects/<project-name>/README.md`
- `projects/<project-name>/docs/product/00-product-vision.md`
- `projects/<project-name>/docs/product/01-users-and-roles.md`
- `projects/<project-name>/docs/product/02-core-flows.md`
- `projects/<project-name>/docs/product/03-feature-scope.md`
- `projects/<project-name>/docs/product/04-prd-first-slice.md`
- `projects/<project-name>/docs/adr/0001-technical-baseline.md`

Rules:

- **All skeleton files live inside `projects/<project-name>/`.** Never create
  root-level `docs/product/` or root-level `docs/adr/`.
- **No implementation may begin until this skeleton exists.** The WebApp
  Orchestrator blocks build work until it is in place.
- Beyond the skeleton, further ADRs and glossary terms are added later, inside
  the project, as decisions get resolved.

---

## Workflow at a glance

```
clarify -> define scope -> shared context -> PRD (if needed)
        -> vertical slices -> prototype (if useful)
        -> implement one slice -> test (TDD where practical)
        -> review -> handoff
```

The **WebApp Orchestrator** decides the next step and routes work. No agent
jumps straight to implementation without scope and context.

---

## Agents in this repository

| Agent | Purpose |
|-------|---------|
| WebApp Orchestrator | Leads the workflow, decides next step, routes work, blocks random implementation. |
| Product Discovery Agent | Clarifies business/product needs, users, workflows, success criteria. |
| Solution Architect Agent | Thinks about boundaries, data ownership, auth, tenancy, scalability. |
| Prototype Agent | Builds disposable prototypes only when requested. |
| Fullstack Builder Agent | Implements one vertical slice at a time. |
| QA Review Agent | Independently verifies a slice/phase against the **Strict QA gate**; outputs **QA PASS / PASS-BUT-BLOCKED / FAIL** with evidence. A builder's own claim never counts as QA PASS. |
| Handoff Agent | Summarizes work, files, tests, risks, next steps. |

Full definitions: see `.claude/agents/`.
Workflows: see `.claude/workflows/`.
Templates: see `.claude/templates/`.
Team docs: see `docs/agents/`.

---

## Definition of done (per task)

- Scope was clear and agreed before coding; the acceptance truth was stated
  ("User expects X / system does Y / done means Z" — Engineering rule 1).
- Change is a small vertical slice; for a bugfix, the **root cause was proven**
  before the fix (rule 2) and no symptom was masked (rule 3).
- Tests protect the **business contract** and fail-first where practical (rule 5).
- **Runtime/browser/network proof** provided where behavior is user-visible
  (rule 6); **safe DTOs** verified for any API change (rule 8).
- Branch/commit/PR rules were followed; no direct protected-branch push and no
  merge without explicit user approval.
- Report follows the **Final PASS Report Standard** (rule 11).
- An **independent QA gate** verified the work (see "Strict QA gate"); a builder's
  own "implementation complete" is **not** QA PASS.

---

## Agent skills

Matt Pocock's skills are installed under `.claude/skills/`. They read repo
config from the files below.

### Issue tracker

Issues and PRDs are tracked in **GitHub Issues** via the `gh` CLI. See
`docs/agents/issue-tracker.md`.

### Triage labels

Five canonical triage roles map 1:1 to label strings (`needs-triage`,
`needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`). See
`docs/agents/triage-labels.md`.

### Domain docs

**Multi-project** layout — this is a master-factory repo. Each project owns its
own `CONTEXT.md`, `docs/product/`, and `docs/adr/` under
`projects/<project-name>/`; root `docs/` holds shared AI team docs only. See
`docs/agents/domain.md`.

### Skill ↔ agent alignment

How installed skills map to our agents and workflows. See
`docs/agents/skill-alignment.md`.

### Documentation layout

This repository is an **AI agent manager / master-factory** repo: it creates and
manages multiple separate web app projects under `projects/`.

- **Root `docs/` is for AI agent / team documentation only** (e.g.
  `docs/agents/`). It is shared across all projects.
- **Never create root-level `docs/product/` or root-level `docs/adr/`.**
- **Each generated project keeps its own docs**, scoped to that project:
  - `projects/<project-name>/docs/product/` — product vision, scope, PRDs
  - `projects/<project-name>/docs/adr/` — that project's architecture decisions
  - `projects/<project-name>/CONTEXT.md` — that project's domain context (part of the required bootstrap skeleton)
- Shared team assets (`AGENTS.md`, `CLAUDE.md`, `.claude/`, `docs/agents/`) stay
  at the repo root and are never copied into a project.
