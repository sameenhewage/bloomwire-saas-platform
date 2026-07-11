#!/usr/bin/env bash
#
# Bloomwire remote deploy script (dev/staging).
#
# Executed ON the target server over SSH by .github/workflows/deploy-dev.yml.
# It is piped to `bash -s` via stdin, so the logic version always comes from the
# branch running the workflow (not the server's checkout).
#
# Positional args (all validated by the workflow before they reach here):
#   $1 REF             git branch or commit SHA to deploy
#   $2 RUN_MIGRATIONS  "true" to run db:migrate, anything else to skip
#   $3 SKIP_SMOKE      "true" to skip post-deploy verification
#   $4 PRUNE           "true" to prune stopped containers / dangling images / build cache
#   $5 DEPLOY_PATH     repo root on the server (contains .git and app/)
#   $6 HEALTH_URL      optional public health URL (e.g. https://dev.unecast.com/health)
#
# Safety contract (do NOT weaken):
#   - Only the rails + sidekiq services are recreated (--no-deps).
#   - postgres + redis containers are never recreated and their volumes are never
#     touched. No `down`, no `down -v`, no `volume prune`, no `system prune`.
#   - No secrets are printed. .env and the server-local compose overlay are
#     gitignored and never modified here.
set -euo pipefail

REF="${1:?REF (arg 1) is required}"
RUN_MIGRATIONS="${2:-false}"
SKIP_SMOKE="${3:-false}"
PRUNE="${4:-false}"
DEPLOY_PATH="${5:?DEPLOY_PATH (arg 5) is required}"
HEALTH_URL="${6:-}"
FORCE_BUILD="${7:-false}"

# Compose invocation mirrors the documented manual dev deploy. The
# docker-compose.bloomwire-production.yaml overlay is server-local + gitignored
# (adds the build context / image overrides) and must already exist on the host.
COMPOSE=(docker compose -p app
  -f docker-compose.production.yaml
  -f docker-compose.bloomwire-production.yaml)

IMAGE_REPO="ghcr.io/sameenhewage/bloomwire-app"

log() { printf '==> %s\n' "$*"; }

# --- 1. Update source to the requested ref ---------------------------------
log "Updating source in ${DEPLOY_PATH} to ref '${REF}'"
cd "${DEPLOY_PATH}"
git fetch --prune origin "${REF}" 2>/dev/null || git fetch --all --prune
git checkout "${REF}"
# Fast-forward when REF is a branch; harmless no-op for a detached commit SHA.
git pull --ff-only origin "${REF}" 2>/dev/null || true
DEPLOY_SHA="$(git rev-parse HEAD)"
log "Deploy SHA: ${DEPLOY_SHA}"

cd app

# --- 2. Obtain the image: pull the CI-built image, else build on server ----
IMAGE_REF="${IMAGE_REPO}:${DEPLOY_SHA}"
if [ "${FORCE_BUILD}" != "true" ] \
  && grep -q 'BLOOMWIRE_IMAGE' docker-compose.bloomwire-production.yaml 2>/dev/null \
  && docker pull "${IMAGE_REF}" >/dev/null 2>&1; then
  export BLOOMWIRE_IMAGE="${IMAGE_REF}"
  log "Using prebuilt image ${IMAGE_REF}"
else
  log "Building image on server (GIT_SHA=${DEPLOY_SHA})"
  "${COMPOSE[@]}" build --build-arg GIT_SHA="${DEPLOY_SHA}"
fi

# --- 3. Optional migrations (run with the freshly built image) -------------
if [ "${RUN_MIGRATIONS}" = "true" ]; then
  log "Running database migrations (db:migrate)"
  # `-T` + `</dev/null` are REQUIRED: this script is piped to the server via `bash -s` over SSH, so any
  # command that attaches stdin (docker compose run does by default) would CONSUME the rest of the script.
  # Without this, db:migrate swallowed steps 4-6 (recreate + smoke) and the deploy exited 0 — a false success.
  "${COMPOSE[@]}" run --rm -T rails bundle exec rails db:migrate </dev/null
else
  log "Skipping migrations (run_migrations=false)"
fi

# --- 4. Recreate ONLY rails + sidekiq, preserving postgres/redis -----------
log "Recreating rails + sidekiq (--no-deps; postgres/redis untouched)"
"${COMPOSE[@]}" up -d --no-deps rails sidekiq

# Best-effort: tag the running rails image with the SHA for rollback provenance.
RAILS_IMG="$("${COMPOSE[@]}" images -q rails 2>/dev/null | head -n1 || true)"
if [ -n "${RAILS_IMG}" ]; then
  docker tag "${RAILS_IMG}" "bloomwire-app:${DEPLOY_SHA}" 2>/dev/null || true
  log "Tagged image bloomwire-app:${DEPLOY_SHA} (rollback reference)"
fi

# --- 5. Post-deploy verification -------------------------------------------
if [ "${SKIP_SMOKE}" != "true" ]; then
  log "Smoke: container status"
  "${COMPOSE[@]}" ps

  log "Smoke: waiting for app health on http://127.0.0.1:3000/health"
  HEALTHY=0
  for i in $(seq 1 40); do
    CODE="$(curl -fsS -o /dev/null -w '%{http_code}' http://127.0.0.1:3000/health 2>/dev/null || true)"
    if [ "${CODE}" = "200" ]; then
      log "Local health 200 OK"
      HEALTHY=1
      break
    fi
    printf '    waiting for health (%s/40), got "%s"\n' "${i}" "${CODE}"
    sleep 3
  done
  if [ "${HEALTHY}" -ne 1 ]; then
    echo "::error::Local health check did not return 200 in time" >&2
    "${COMPOSE[@]}" logs --tail 80 rails >&2 || true
    exit 1
  fi

  log "Smoke: verifying deployed SHA inside container"
  DEPLOYED_SHA="$("${COMPOSE[@]}" exec -T rails cat /app/.git_sha | tr -d '\r\n')"
  printf '    /app/.git_sha = %s\n' "${DEPLOYED_SHA}"
  if [ "${DEPLOYED_SHA}" != "${DEPLOY_SHA}" ]; then
    echo "::error::SHA mismatch: expected ${DEPLOY_SHA}, container reports ${DEPLOYED_SHA}" >&2
    exit 1
  fi

  if [ -n "${HEALTH_URL}" ]; then
    log "Smoke: public health (${HEALTH_URL})"
    PUB_CODE="$(curl -fsS -o /dev/null -w '%{http_code}' "${HEALTH_URL}" 2>/dev/null || true)"
    printf '    public health = %s\n' "${PUB_CODE}"
    if [ "${PUB_CODE}" != "200" ]; then
      echo "::error::Public health check (${HEALTH_URL}) did not return 200" >&2
      exit 1
    fi
  fi

  log "Smoke: confirming postgres + redis still running (volumes preserved)"
  "${COMPOSE[@]}" ps postgres redis
else
  log "Skipping smoke checks (skip_smoke=true)"
fi

# --- 6. Optional, conservative cleanup (NEVER volumes/running containers) ---
if [ "${PRUNE}" = "true" ]; then
  log "Cleanup: stopped containers, dangling images, build cache >7d (volumes NOT touched)"
  docker container prune -f
  docker image prune -f
  # Only remove build cache older than 7 days (168h); never aggressively wipe all cache.
  docker builder prune -f --filter "until=168h"
fi

log "Deploy complete — SHA ${DEPLOY_SHA}"
echo "DEPLOY_RESULT_SHA=${DEPLOY_SHA}"
