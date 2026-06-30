# CLAUDE.md

Instructions for Claude Code (and any Claude-based agent) working in this
repository.

> **Read `AGENTS.md` first.** It defines the operating rules for all AI agents.
> This file adds Claude-specific guidance on top of those rules.

---

## Before you do anything

1. **Graph-first.** **Read** the relevant slice of the graphify code graph to
   establish the current situation — *before* any analysis or implementation.
   The graph **auto-refreshes** via git hooks (post-commit + post-checkout), so
   you do **not** run `graphify update` by hand. This is `AGENTS.md` → "What
   every agent MUST do" step 1; follow it without exception.
2. **Read `AGENTS.md`.** Follow it without exception. **For Bloomwire work, also read
   `docs/bloomwire/PROJECT-CONTEXT.md`** (what the project is — a managed business messaging SaaS on the
   Chatwoot engine, WhatsApp-first to market — plus durable rules) **and `docs/bloomwire/SESSION-LOG.md`**
   (live state + journal) — and
   **update SESSION-LOG (Current State + a new entry) when you finish a slice/phase.**
3. **Understand the current task.** Find the issue, task brief, or PRD that
   authorizes the work. If there is none, stop and ask.
4. **Inspect the affected code** before editing. Know what exists and why.

---

## Claude operating mode

Use **Controlled Autonomy Mode** for approved tasks.

Claude may proceed without asking for every small step when the task scope is
clear and approved. Within that scope, Claude may inspect, edit, test, push a
feature branch, and open a PR.

Claude must stop and ask before:

- merging a PR,
- pushing directly to `main`, `master`, `version_1`, or any release/version
  branch,
- starting CI/CD, production deployment, release/versioning, or unrelated phase
  work,
- running destructive DB/container operations,
- changing production/customer data,
- exposing or committing secrets,
- changing authentication/authorization architecture beyond the approved slice,
- adding dependencies or broad new abstractions,
- expanding into UI/Tier-2/Tier-3/Enterprise/production work unless approved.

For implementation work, write or update failing tests first where practical,
prove RED for the right reason, then implement the smallest safe change. For
runtime-validation-only work, do not add unnecessary tests; validate the deployed
behavior and report evidence.

---

## Rules for Claude Code

- **Understand the task before editing.** No edits without a clear goal and a
  defined scope.
- **First explain the existing flow/root cause before editing.** For fixes,
  identify the behavior owner and why the bug happens. For features, explain the
  current flow and why the change is needed.
- **Do not create product or ADR docs unless explicitly asked.** Specifically,
  do not create `docs/product/` or `docs/adr/` on your own.
- **Do not implement features without a clear issue or task.** If the request
  is vague, ask clarifying questions first.
- **Prefer simple, maintainable solutions.** Choose the smallest change that
  fully solves the problem. Avoid clever abstractions and premature
  generalization.
- **Explain assumptions before acting.** If you must assume something to
  proceed, state it clearly and proceed only if low-risk; otherwise ask.
- **Preserve existing project conventions.** Match naming, structure, style,
  and tooling already in use. Do not introduce new dependencies or patterns
  without explicit approval.
- **Open PRs, do not merge them.** After opening a PR, report the URL, evidence,
  and merge status, then stop unless the user explicitly asks for more.

---

## Engineering rules (global, mandatory)

**`AGENTS.md` → "Engineering rules (global, mandatory)" is the canonical list.**
They are generic and apply to every project, feature, bugfix, UI, API, and DB
task. Do not restate or fork them here — read them there. In short:

1. **Product Truth Gate** — done = browser/runtime behavior + data source of truth
   + workflow are correct; *not* "tests/types/build/API/docs pass" or "I added a
   guard/cache/de-dupe". Write "User expects X / system does Y / done means Z"
   before coding.
2. **Root Cause Gate** — prove the root cause (flow, owner, why, dev/prod,
   smallest fix, what was not changed) before any bugfix.
3. **No Symptom Masking** — no global de-dupe / cache / guard / retry / timeout /
   silent fallback / extra loader / duplicate state / new table as a *primary* fix.
4. **Ownership** — one clear owner per behavior; resolve duplicates, don't mask them.
5. **TDD = business truth** — test the contract, fail-first where practical.
6. **Runtime Proof Gate** — Network tab / DOM / console / dev+prod / DB verifier
   as the feature warrants; "tests pass" alone is not PASS.
7. **Source-of-Truth Gate** — know who owns/read-only/writable before data work.
8. **Security / Safe DTO Gate** — no raw phone / user / contact / session id /
   `runs` / `session_data` in responses; safe DTOs only.
9. **No Over-Engineering** — smallest correct fix; new libs/tables/abstractions
   need a documented decision.
10. **Docs / Decision-Log Gate** — update the right level; no stale contradictory docs.
11. **Final PASS Report Standard** — see "After every task" below.
12. **Project-specific contracts live in the project** — read the project's
    `CONTEXT.md` before working in it.

---

## Strict QA gate (mandatory)

**`AGENTS.md` → "Strict QA gate (mandatory)" is the canonical gate.** Do not fork
it here — read it there. In short:

- **Task completion is not QA completion.** You may say **"IMPLEMENTATION
  COMPLETE"**; only an **independent** QA pass may say **"QA PASS"**; only after QA
  PASS may the orchestrator say **"phase PASS" / "merge-ready"**.
- **QA after every task/slice** (before commit) and **strict QA after every phase**
  (before push / PR / merge): source-diff, tests + **exact** command output,
  security / permission, no-secret, feature-OFF, no real Meta/WhatsApp call,
  runtime / MCP proof for UI, and regression checks.
- **Allowed final states only:** **IMPLEMENTATION COMPLETE**, **QA PASS**,
  **PASS-BUT-BLOCKED** (QA passed but branch protection / review / status blocks the
  merge), or **FAIL**.
- **No fake PASS:** no runtime PASS without runtime/MCP evidence; no live
  Meta/WhatsApp PASS without real human-operated evidence; no security PASS without
  backend authorization proof; never "merge-ready" when GitHub protection / review /
  status is blocked.

---

## Bloomwire Documentation Governance (mandatory)

**`AGENTS.md` → "Bloomwire Documentation Governance" is canonical.** Do not fork it here — read it
there. In short: every Bloomwire-owned PR that changes **behavior / permissions / security /
onboarding / WhatsApp flow / APIs / UI flows / data model / ops process / customer-facing behavior**
**must update docs in the same PR** — `docs/bloomwire/implementation-ledger.md` + `.html`, the
Bloomwire change log (`docs/bloomwire/change-log.md`), and any affected ADR/runbook. A PR that
changes Bloomwire behavior **without** updating docs/changelog is **not approval-ready**; docs-only
PRs need no deploy.

- Each ledger/changelog entry records: phase · PR · merge SHA · what/why · what was **not** changed ·
  validation · residual risks.
- Security/WhatsApp entries must state: **no secrets exposed**, **no provider-credential mutation
  unless authorized**, whether **live Meta/WhatsApp calls** were made, whether **Enterprise** was touched.
- Preserve invariants: no `users.type` for business roles · no `BusinessOwner` without separate design ·
  no duplicate chat/message source of truth · no Enterprise dependency · WhatsApp-first scope.
- **Definition of Done:** code · tests · runtime proof (when applicable) · **docs updated** ·
  **changelog updated** · residual risks recorded · exact merge SHA recorded after merge. _(Phase 15E.1.)_

---

## How to respond

- Be concise and practical. Lead with the action or answer.
- When proposing changes, describe the plan briefly, then implement the agreed
  slice.
- Work in **vertical slices** and keep changes small and reversible.
- If blocked, say exactly what is blocking progress and what decision or access
  is needed.

---

## After every task

End with the **Final PASS Report Standard** (`AGENTS.md` Engineering rule 11; see
also `.claude/templates/implementation-summary-template.md`):

1. **Requirement understood** (the "X / Y / Z" acceptance truth).
2. **Root cause** (for fixes) or feature reason/current flow (for features).
3. **Files read** and **files changed** (created / modified / deleted).
4. **Tests added/updated**, and **proof they failed before the fix** (or an honest
   reason they could not fail).
5. **Runtime / browser / network proof** where behavior is user-visible.
6. **Security proof** for any API/DTO/auth/secrets change.
7. **What was NOT changed**, **remaining risks**, **next recommended step**, and
   PR URL/merge status when applicable.

**Forbidden PASS:** "all tests pass" only, "build green" only, "I added a guard"
only, or "looks good" without runtime proof.

---

## Agent skills

Matt Pocock's skills are installed in `.claude/skills/`. Their repo
configuration and how they map to our agents and workflows live in the
**`## Agent skills`** section of `AGENTS.md` and the files under `docs/agents/`.

---

## When unsure

Ask. A short clarifying question is always cheaper than rework. If you are
blocked, say what you need to proceed.
