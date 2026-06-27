# REVIEW.md

Review guidance for AI and human reviewers working in this repository.

Read `AGENTS.md` first. It is the source of truth for engineering, safety, and
validation rules. This file focuses on PR review behavior.

---

## Review focus

When reviewing PRs, pay special attention to:

- authentication and authorization changes,
- role/permission checks,
- database migrations and data compatibility,
- API contract changes and response DTO safety,
- background jobs and webhook behavior,
- UI behavior that affects production users,
- performance regressions,
- missing, weak, or implementation-only tests,
- hidden behavior changes behind broad guards, caches, retries, or fallbacks,
- secrets, tokens, raw provider IDs, phone numbers, or internal IDs being exposed.

---

## Review rules

- Do not approve PRs that change security-sensitive behavior without clear tests
  and validation evidence.
- Flag large unrelated rewrites.
- Flag hidden behavior changes.
- Confirm the PR description includes validation evidence.
- Confirm risky changes include rollback notes or clear reasoning.
- Confirm Bloomwire OFF / feature-toggle OFF behavior remains backward
  compatible when the PR claims it does.
- Confirm server-side authorization exists before accepting UI-only hiding for a
  security-sensitive restriction.
- Confirm runtime proof exists when the change affects user-visible behavior,
  webhooks, background jobs, data mapping, or deployment/runtime config.
- Confirm no `.env`, secrets, tokens, private keys, provider credentials, or
  production credentials are committed or printed.
- Confirm the PR does not merge itself, deploy to production, or start CI/CD /
  release work unless that exact phase was explicitly approved.

---

## Review method

1. Read the PR title, description, scope, and validation evidence.
2. Inspect the changed files and nearby owners/callers.
3. Check whether the tests protect the business contract, not just the current
   implementation.
4. For security-sensitive PRs, trace the route/controller/policy/service path and
   look for bypasses.
5. Check feature-toggle behavior: ON behavior, OFF behavior, default state, and
   master-gating where relevant.
6. Check side effects: DB writes, jobs enqueued, external calls, token writes,
   cache changes, and webhook behavior.
7. Run or verify the most relevant tests where possible.
8. Give a clear verdict: PASS, PASS with non-blocking notes, or FAIL with exact
   blockers.

---

## Review output format

A useful review should include:

- verdict,
- reviewed scope,
- files/areas inspected,
- tests or commands run,
- security/auth assessment where relevant,
- blocking findings with file/action evidence,
- non-blocking notes,
- remaining risks,
- final recommendation: merge, request changes, or hold.

Do not approve with vague statements like "looks good". Explain the evidence.
