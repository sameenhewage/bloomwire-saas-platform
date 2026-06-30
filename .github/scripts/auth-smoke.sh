#!/usr/bin/env bash
#
# Phase 15G.3 — Auth smoke (dev/staging ONLY). Verifies that a DEDICATED test SuperAdmin can log in and that
# the deployed SHA matches. This is an OPTIONAL, operator-run check (not wired into the auto-deploy, so no
# test-admin secret has to live in CI). See deployment-runbook.md §7.
#
# HARD RULES:
#   - NEVER use the real owner (sameen@bloomwire.lk) — use a dedicated, disposable dev/staging test admin.
#   - NEVER hardcode credentials. Pass them via env (a dev/staging secret), never on the command line.
#   - dev/staging only — refuses anything that looks like production.
#   - The password is read from a file/env and url-encoded from a file, so it never appears in argv/`ps`.
#   - No secret is ever printed.
#
# Required env:
#   SMOKE_BASE_URL   e.g. https://dev.unecast.com
#   SMOKE_EMAIL      dedicated test SuperAdmin email (NOT the owner)
#   SMOKE_PASSWORD   that test admin's password (dev/staging secret)
# Optional:
#   EXPECTED_SHA     deployed git SHA to assert
#   SMOKE_SSH        ssh target (e.g. contabo-dev) used to read /app/.git_sha for the SHA assertion
set -euo pipefail

: "${SMOKE_BASE_URL:?set SMOKE_BASE_URL (dev/staging base URL)}"
: "${SMOKE_EMAIL:?set SMOKE_EMAIL (dedicated test admin, NOT the owner)}"
: "${SMOKE_PASSWORD:?set SMOKE_PASSWORD (dev/staging secret)}"

case "$SMOKE_BASE_URL" in
  *prod*|*production*) echo "REFUSING: auth smoke is dev/staging only."; exit 2 ;;
esac
if [ "$SMOKE_EMAIL" = "sameen@bloomwire.lk" ]; then
  echo "REFUSING: do not smoke with the real owner account; use a dedicated test admin."; exit 2
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
