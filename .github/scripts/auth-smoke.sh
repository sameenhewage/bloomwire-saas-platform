#!/usr/bin/env bash
#
# Phase 15G.3 — Auth smoke (dev/staging ONLY). Verifies that a DEDICATED test SuperAdmin can log in and that
# the deployed SHA matches. This is an OPTIONAL, operator-run check (not wired into the auto-deploy, so no
# test-admin secret has to live in CI). See deployment-runbook.md §7.
#
# HARD RULES:
#   - NEVER use the real owner (sameen@bloomwire.lk) — use a dedicated, disposable dev/staging test admin.
#   - NEVER hardcode credentials. Pass them via env (a dev/staging secret), never on the command line.
#   - HOST ALLOWLIST (default-deny): only known dev/staging hosts are allowed; production + any unknown host
#     are refused. Default allowlist is `dev.unecast.com` (extend with SMOKE_ALLOWED_HOSTS when staging exists).
#   - The password is read from a file/env and url-encoded from a file, so it never appears in argv/`ps`.
#   - No secret is ever printed.
#
# Required env:
#   SMOKE_BASE_URL   e.g. https://dev.unecast.com (host must be in the allowlist)
#   SMOKE_EMAIL      dedicated test SuperAdmin email (NOT the owner)
#   SMOKE_PASSWORD   that test admin's password (dev/staging secret)
# Optional:
#   SMOKE_ALLOWED_HOSTS  extra allowed hosts (space/comma-separated), e.g. a staging host once configured
#   SMOKE_VALIDATE_ONLY  if set, run only the safety guards (allowlist + owner refusal) and exit (no login)
#   EXPECTED_SHA         deployed git SHA to assert
#   SMOKE_SSH            ssh target (e.g. contabo-dev) used to read /app/.git_sha for the SHA assertion
set -euo pipefail

: "${SMOKE_BASE_URL:?set SMOKE_BASE_URL (dev/staging base URL)}"
: "${SMOKE_EMAIL:?set SMOKE_EMAIL (dedicated test admin, NOT the owner)}"
: "${SMOKE_PASSWORD:?set SMOKE_PASSWORD (dev/staging secret)}"

# Allowlist (DEFAULT-DENY): only known non-production dev/staging hosts may be smoked. Production and any
# unknown host are refused. The default allowlist is `dev.unecast.com`; add a staging host when one exists via
# SMOKE_ALLOWED_HOSTS (space/comma-separated). This is intentionally an allowlist, not a production denylist.
SMOKE_HOST="${SMOKE_BASE_URL#*://}"   # strip scheme
SMOKE_HOST="${SMOKE_HOST%%/*}"        # strip path
SMOKE_HOST="${SMOKE_HOST%%:*}"        # strip port
ALLOWED_HOSTS="dev.unecast.com ${SMOKE_ALLOWED_HOSTS:-}"
ALLOWED_HOSTS="${ALLOWED_HOSTS//,/ }"
host_ok=0
for h in $ALLOWED_HOSTS; do
  if [ "$SMOKE_HOST" = "$h" ]; then host_ok=1; break; fi
done
if [ "$host_ok" -ne 1 ]; then
  echo "REFUSING: host '$SMOKE_HOST' is not in the dev/staging allowlist (allowed: $ALLOWED_HOSTS)."
  exit 2
fi

# Never smoke with the real owner account — use a dedicated, disposable test admin.
if [ "$SMOKE_EMAIL" = "sameen@bloomwire.lk" ]; then
  echo "REFUSING: do not smoke with the real owner account; use a dedicated test admin."
  exit 2
fi

# Validation-only mode: run just the safety guards (allowlist + owner refusal) with no login/network.
# Used by the guard test and for safe dry-runs. Never performs a login or reads the network.
if [ -n "${SMOKE_VALIDATE_ONLY:-}" ]; then
  echo "VALIDATION_OK: host '$SMOKE_HOST' is allowed and the account is not the owner."
  exit 0
fi

CJ="$(mktemp)"; PAGE="$(mktemp)"; TF="$(mktemp)"; PF="$(mktemp)"
trap 'rm -f "$CJ" "$PAGE" "$TF" "$PF"' EXIT
chmod 600 "$CJ" "$PAGE" "$TF" "$PF"
printf '%s' "$SMOKE_PASSWORD" > "$PF"   # password to a 600 file => never in argv/ps

# 1) Fetch the sign-in page + CSRF token (fresh session cookie jar).
curl -fsS -c "$CJ" "$SMOKE_BASE_URL/super_admin/sign_in" -o "$PAGE"
grep -oE 'name="authenticity_token"[^>]*value="[^"]+"' "$PAGE" | head -1 \
  | sed -E 's/.*value="([^"]+)".*/\1/' > "$TF"
if [ ! -s "$TF" ]; then echo "SMOKE_FAIL: no CSRF token on the sign-in page"; exit 1; fi

# 2) Submit credentials. Token + password are url-encoded from files (not from argv).
RESP="$(curl -fsS -b "$CJ" -c "$CJ" -o /dev/null -w '%{http_code} %{redirect_url}' \
  --data-urlencode "authenticity_token@$TF" \
  --data-urlencode "super_admin[email]=$SMOKE_EMAIL" \
  --data-urlencode "super_admin[password]@$PF" \
  "$SMOKE_BASE_URL/super_admin/sign_in" || true)"
echo "login_response_code_and_location: $RESP"
case "$RESP" in
  *"/super_admin/sign_in"*) echo "SMOKE_FAIL: login rejected (redirected back to sign-in)"; exit 1 ;;
  3[0-9][0-9]\ http*|200\ *)  echo "SMOKE_OK: login accepted" ;;
  *) echo "SMOKE_FAIL: unexpected login response"; exit 1 ;;
esac

# 3) Optional: assert the deployed SHA (requires SSH access to the host).
if [ -n "${EXPECTED_SHA:-}" ] && [ -n "${SMOKE_SSH:-}" ]; then
  DEPLOYED="$(ssh -o ConnectTimeout=20 "$SMOKE_SSH" 'docker exec app-rails-1 cat /app/.git_sha' | tr -d '\r\n')"
  if [ "$DEPLOYED" = "$EXPECTED_SHA" ]; then
    echo "SHA_OK: $DEPLOYED"
  else
    echo "SHA_FAIL: deployed=$DEPLOYED expected=$EXPECTED_SHA"; exit 1
  fi
fi

echo "AUTH_SMOKE_PASS"
