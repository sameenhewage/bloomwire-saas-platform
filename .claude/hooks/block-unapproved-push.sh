#!/usr/bin/env bash
set -euo pipefail

INPUT="$(cat)"
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
APPROVAL="$PROJECT_DIR/.claude/pre-push-approval.json"
CURRENT_HEAD="$(git -C "$PROJECT_DIR" rev-parse HEAD 2>/dev/null || true)"
CURRENT_BRANCH="$(git -C "$PROJECT_DIR" branch --show-current 2>/dev/null || true)"

extract_command() {
  if command -v jq >/dev/null 2>&1; then
    printf '%s' "$INPUT" | jq -r '.tool_input.command // .tool_input.CommandLine // .command // empty' 2>/dev/null || true
  else
    printf '%s' "$INPUT" | sed -n 's/.*"command"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p; s/.*"CommandLine"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1
  fi
}

is_git_push() {
  local command_text="$1"
  printf '%s' "$command_text" | grep -Eq '(^|[;&|])[[:space:]]*([A-Za-z_][A-Za-z0-9_]*=[^;&|[:space:]]+[[:space:]]+)*(env[[:space:]]+([^;&|[:space:]]+[[:space:]]+)*)?git[[:space:]]+([^;&|[:space:]]+[[:space:]]+)*push([[:space:]]|[;&|]|$)'
}

block() {
  {
    echo ""
    echo "================ BLOCKED by Pre-Push Code Review Gate ================"
    echo "git push refused: $1"
    echo ""
    echo "Current HEAD: ${CURRENT_HEAD:-unknown}"
    echo "Current branch: ${CURRENT_BRANCH:-unknown}"
    echo "Approval file: .claude/pre-push-approval.json"
    echo ""
    echo "Run implementation checks first, commit, then run the pre-push-code-review-agent."
    echo "The agent must return APPROVE and write an approval artifact pinned to this HEAD and branch."
    echo "Any new commit invalidates the approval automatically."
    echo "======================================================================"
    echo ""
  } >&2
  exit 2
}

COMMAND_TEXT="$(extract_command)"

if ! is_git_push "$COMMAND_TEXT"; then
  exit 0
fi

command -v jq >/dev/null 2>&1 || block "jq is not installed; cannot read approval artifact."
[ -f "$APPROVAL" ] || block "missing approval artifact."

verdict="$(jq -r '.verdict // empty' "$APPROVAL" 2>/dev/null || true)"
approved_sha="$(jq -r '.approved_head_sha // empty' "$APPROVAL" 2>/dev/null || true)"
approved_branch="$(jq -r '.branch // empty' "$APPROVAL" 2>/dev/null || true)"
approved_at="$(jq -r '.approved_at // empty' "$APPROVAL" 2>/dev/null || true)"
review_agent="$(jq -r '.review_agent // empty' "$APPROVAL" 2>/dev/null || true)"
tests_count="$(jq -r 'if (.tests_run | type) == "array" then (.tests_run | length) else -1 end' "$APPROVAL" 2>/dev/null || echo -1)"
mcp_count="$(jq -r 'if (.mcp_runtime_evidence | type) == "array" then (.mcp_runtime_evidence | length) else -1 end' "$APPROVAL" 2>/dev/null || echo -1)"
summary="$(jq -r '.summary // empty' "$APPROVAL" 2>/dev/null || true)"

[ "$verdict" = "APPROVE" ] || block "approval verdict is '${verdict:-none}', not APPROVE."
[ -n "$approved_sha" ] || block "approval artifact has no approved_head_sha."
[ -n "$approved_branch" ] || block "approval artifact has no branch."
[ -n "$approved_at" ] || block "approval artifact has no approved_at."
[ "$review_agent" = "pre-push-code-review-agent" ] || block "approval artifact review_agent is '${review_agent:-none}', not pre-push-code-review-agent."
[ "$tests_count" -gt 0 ] || block "approval artifact tests_run must be a non-empty array."
[ "$mcp_count" -gt 0 ] || block "approval artifact mcp_runtime_evidence must be a non-empty array."
[ -n "$summary" ] || block "approval artifact has no summary."
[ "$approved_sha" = "$CURRENT_HEAD" ] || block "approval is for $approved_sha, but current HEAD is $CURRENT_HEAD."
[ "$approved_branch" = "$CURRENT_BRANCH" ] || block "approval branch is '$approved_branch', current branch is '$CURRENT_BRANCH'."

exit 0
