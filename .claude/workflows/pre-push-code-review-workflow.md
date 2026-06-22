---
description: Mandatory local pre-push review gate after implementation, tests, runtime proof, and commit
---

# Pre-Push Code Review Workflow

> Read `AGENTS.md` and `CLAUDE.md` first. This workflow is the final local gate
> before pushing code from this repository.

## Mandatory sequence

```text
Implement
-> run tests
-> run MCP/runtime validation
-> commit
-> run pre-push-code-review-agent
-> APPROVE writes approval artifact
-> git push allowed
```

## Setup

Install the tracked Git hook path once per clone:

```bash
git config core.hooksPath .githooks
```

The Claude Code / agent Bash hook is project-local in `.claude/settings.json` and
runs `.claude/hooks/block-unapproved-push.sh` for `PreToolUse(Bash)`.

## Approval artifact

The local approval file is:

```text
.claude/pre-push-approval.json
```

It is ignored by git and must never be committed. It must contain:

```json
{
  "verdict": "APPROVE",
  "approved_head_sha": "<current HEAD>",
  "branch": "<current branch>",
  "approved_at": "<UTC ISO-8601 timestamp>",
  "review_agent": "pre-push-code-review-agent",
  "tests_run": ["<commands and results>"],
  "mcp_runtime_evidence": ["<evidence or N/A with reason>"],
  "summary": "<short approval rationale>"
}
```

## Required behavior

- No approval -> push blocked.
- `BLOCK` verdict -> push blocked.
- Approval for an old commit -> push blocked.
- Approval for a different branch -> push blocked.
- `APPROVE` for current `HEAD` and current branch -> push allowed.
- Any new commit after approval -> push blocked until re-review.

## Running the review agent

Ask the `pre-push-code-review-agent` to review the exact current commit before
push. Provide:

- Task brief / acceptance truth.
- Current branch and `HEAD`.
- Changed files and full current commit diff.
- Test results.
- MCP/runtime proof or why runtime proof is not applicable.
- Security / safe DTO proof where relevant.

If the agent returns `BLOCK`, fix the listed file/line findings, run required
checks again, commit the fix, and re-run the agent.

If the agent returns `APPROVE`, it writes `.claude/pre-push-approval.json` pinned
to the current `HEAD` and branch. Only then should `git push` be attempted.

## Limits

This is local enforcement. It protects this clone and Claude/agent Bash workflows,
but it can be bypassed with disabled hooks, `git push --no-verify`, or pushes from
another machine. True server-side enforcement still requires GitHub branch
protection and required checks.
