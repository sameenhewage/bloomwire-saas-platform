# Independent TDD Workflow

Use this workflow for coding slices where regressions, permissions, tenancy,
security, or data-source mistakes would be costly.

The goal is to prevent the same agent from writing convenient tests that merely
match its own implementation.

## Agent sequence

```text
1. WebApp Orchestrator
   -> confirms scope, acceptance truth, and active project context

2. Acceptance Test Agent
   -> writes failing tests for the core business contract

3. Edge & Security Test Agent
   -> writes failing tests for edge cases, tenant isolation, permissions, safe DTOs

4. Fullstack Builder Agent
   -> implements the smallest correct slice to satisfy the existing tests

5. QA Review Agent
   -> verifies product truth, runtime behavior, test quality, security, and scope

6. Code Review Agent
   -> reviews the PR diff before promotion/merge

7. Handoff Agent
   -> summarizes the merged/ready work and next step
```

## Builder guardrail

The builder must not delete, weaken, or rewrite tests from the independent test
agents without explicit approval.

If a test is wrong or out of scope, the builder must stop and report:

- which test is disputed,
- why it is wrong,
- what requirement or source-of-truth contract it conflicts with,
- what change is proposed.

Only after human/orchestrator approval may the test be changed.

## Required RED / GREEN proof

Every code slice using this workflow must report:

1. **Acceptance RED** — command and failing output from acceptance tests before implementation.
2. **Edge/security RED** — command and failing output from edge/security tests before implementation.
3. **GREEN** — command and passing output after implementation.
4. **Diff proof** — tests were not deleted, weakened, or rewritten to fit the implementation.
5. **Runtime proof** — browser/network/DB/API proof as the feature warrants.
6. **Security proof** — tenant isolation, permissions, and safe DTO proof where relevant.

## When to use this workflow

Use it by default for:

- multi-tenant behavior,
- permissions and roles,
- authentication/authorization,
- customer/contact/conversation/message data,
- API DTO changes,
- database write paths,
- analytics/counting/reporting logic,
- anything that could expose one tenant's data to another.

For docs-only or visual-explainer tasks, use an acceptance checklist and browser
verification instead of RED/GREEN code tests.

## Definition of PASS

PASS requires more than tests passing:

- the real product workflow matches the requirement,
- source of truth is correct,
- tenant/security boundaries hold,
- runtime behavior is verified,
- the Final PASS Report Standard is complete.
