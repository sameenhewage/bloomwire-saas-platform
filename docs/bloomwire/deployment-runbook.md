<!-- Docs only. Bloomwire-owned deployment runbook. Kept current per AGENTS.md -> "Bloomwire Documentation Governance". -->

# Bloomwire Deployment Runbook (CI + manual Dev/Staging CD)

Operational guide for the Phase 15G CI/CD foundation: **PR validation** for changes targeting
`version_1`, and a **manually-triggered** Dev/Staging deploy over SSH. This runbook is the source of
truth for *how to run* the pipelines.

**Never paste secrets into this file, chat, logs, PRs, or commits.** Report presence/masked only
(e.g. `present`, `missing`, `****1234`). `.env` and the server-local
`docker-compose.bloomwire-production.yaml` overlay are gitignored and must never be committed.

Related docs:
[`implementation-ledger.md`](./implementation-ledger.md) ·
[`change-log.md`](./change-log.md) ·
WhatsApp/dev ops detail: `projects/bloomwire-chatwoot-platform/docs/ops/whatsapp-webhook-deployment-runbook.md`.

Hard rules (from `AGENTS.md`): **no automatic production deploy**, **no secrets printed**, **no live
Meta/WhatsApp calls in CI**, **Enterprise code not exercised**, **Postgres/Redis volumes never destroyed**.

---

## 1. Files

| File | Purpose |
| --- | --- |
| `.github/workflows/ci.yml` | PR validation for pull requests targeting `version_1`. |
| `.github/workflows/build-image.yml` | Build and push SHA-pinned + `version_1` application images to GHCR after a `version_1` push (or manual dispatch). |
| `.github/workflows/deploy-dev.yml` | Manual (`workflow_dispatch`) Dev/Staging deploy over SSH. |
| `.github/scripts/deploy-remote.sh` | The remote deploy logic executed on the server (piped over SSH), including guarded GHCR pull with server-build fallback. |

The Rails app lives in `app/`; CI jobs run with `working-directory: app` except the repo-root
governance/secret jobs.

---

## 2. CI — PR validation (`ci.yml`)

**Triggers:** `pull_request` targeting `version_1`, plus manual `workflow_dispatch`.
**Runner:** GitHub-hosted `ubuntu-latest` only (no self-hosted runner in this phase).
**Token:** `permissions: contents: read` (no deploy/write scope). **No secrets are read.**

Jobs (all independent, run in parallel):

| Job | What it does |
| --- | --- |
| `rubocop` | `bundle exec rubocop --parallel` (Ruby 3.4.4). |
| `eslint` | `pnpm run eslint` (Node 24, pnpm 10.2.0). |
| `frontend-tests` | `pnpm run test` (Vitest). |
| `assets-build` | `bundle exec rake assets:precompile` with `SECRET_KEY_BASE=precompile_placeholder` (mirrors the production Docker asset build; no DB/secrets). |
| `bloomwire-rspec` | Curated Bloomwire RSpec scope against ephemeral Postgres (pgvector pg16) + Redis, with `DISABLE_ENTERPRISE=true` (the OSS path Bloomwire runs). Specs stay WebMock-blocked — **no live Meta calls.** |
| `migration-check` | `db:schema:load` then `db:abort_if_pending_migrations`; fails if a migration isn't reflected in the committed `db/schema.rb`. |
| `docs-governance` | Fails if root `docs/product` or `docs/adr` exist, or if a required Bloomwire doc is missing. |
| `secret-scan` | Self-contained high-signal scan of PR-added content; blocks committed real `.env` files and obvious keys/tokens. Never prints full values. |

**Bloomwire RSpec scope:** every spec under a `bloomwire/` path (services, controllers, lib, models,
mailers, integration, requests, and the `super_admin/*bloomwire*` specs) **plus** the WhatsApp webhook
job specs (`spec/jobs/webhooks/whatsapp_events_job*`). The list is computed dynamically, so new
Bloomwire specs are picked up automatically.

> Enterprise code is **not stripped** but is **disabled** in `bloomwire-rspec` via `DISABLE_ENTERPRISE=true`
> — the documented Bloomwire runtime (locally supplied via `.env`). The enterprise tree ships in the
> deployed artifact but is disabled at runtime; CI mirrors that. The curated specs assume the OSS path
> (e.g. stubbing `Account#usage_limits`, which the enterprise prepend would otherwise own).

---

## 3. CD — manual Dev/Staging deploy (`deploy-dev.yml`)

**Trigger:** manual only — Actions tab → *Deploy Dev/Staging (manual)* → **Run workflow**.
**Targets:** `dev` or `staging` only. Production is not selectable and is hard-blocked in the job.

### 3.1 Inputs

| Input | Default | Meaning |
| --- | --- | --- |
| `environment` | `dev` | `dev` or `staging` (choice only). |
| `ref` | `version_1` | Branch or commit SHA to deploy (validated: `A-Z a-z 0-9 . _ / -`). |
| `run_migrations` | `true` | Run `db:migrate` during deploy. Uncheck to skip migrations explicitly (e.g. rollback). |
| `skip_smoke` | `false` | Skip post-deploy verification (not recommended). |
| `prune` | `false` | Prune stopped containers / dangling images / build cache (**never volumes**). |
| `force_build` | `false` | Force the existing server-side image build and skip the GHCR pull path. Use for registry incidents or explicit rollback diagnostics. |

### 3.2 Required GitHub Environment secrets

Configure under **Settings → Environments → `dev`** (and `staging`). Using GitHub Environments also lets
you add required-reviewer protection for auditable deploys.

| Secret | Required | Notes |
| --- | --- | --- |
| `SSH_HOST` | yes | Server hostname/IP (e.g. `dev.unecast.com`). |
| `SSH_USER` | yes | SSH login user. |
| `SSH_KEY` | yes | Private key (PEM) with deploy access. |
| `DEPLOY_PATH` | yes | Repo root on the server (contains `.git` and `app/`). |
| `SSH_PORT` | no | Defaults to `22`. |
| `SSH_KNOWN_HOSTS` | no | Pinned `known_hosts` entry. If unset, the runner uses `ssh-keyscan` (TOFU). Pinning is recommended. |
| `HEALTH_URL` | no | Public health URL (e.g. `https://dev.unecast.com/health`) for an extra end-to-end check. |

### 3.3 What a deploy does (in order)

1. **Guard:** refuse any environment other than `dev`/`staging`; validate the `ref`.
2. **SSH setup:** write the key (chmod 600), populate `known_hosts` (pinned or keyscan).
3. **Remote source update (over SSH):** in `DEPLOY_PATH` — fetch the requested ref with prune (fall back to a full fetch only when needed), `git checkout <ref>`, fast-forward if it's a branch, then record `DEPLOY_SHA = git rev-parse HEAD`.
4. **Obtain the SHA image:** derive `ghcr.io/sameenhewage/bloomwire-app:<DEPLOY_SHA>`. Use it only when `force_build=false`, the server-local overlay explicitly references `BLOOMWIRE_IMAGE`, and `docker pull` succeeds. Otherwise run the existing server-side Compose build with `GIT_SHA=<DEPLOY_SHA>`. A registry failure therefore falls back to today's build path; `force_build=true` always selects that path.
5. **Migrations (optional):** `... run --rm -T rails bundle exec rails db:migrate </dev/null` when `run_migrations=true` (the `-T </dev/null` is required so the SSH-piped script isn't consumed — see §6).
6. **Recreate app only:** `... up -d --no-deps rails sidekiq` — **postgres/redis are not recreated; their volumes are preserved.**
7. **Tag for rollback:** best-effort `docker tag <rails image> bloomwire-app:<DEPLOY_SHA>`.
8. **Smoke (unless `skip_smoke`):** container status → wait for `http://127.0.0.1:3000/health` = 200 → verify container `/app/.git_sha` == `DEPLOY_SHA` → optional public `HEALTH_URL` = 200 → confirm postgres + redis still `Up`.
9. **Cleanup (optional):** `docker container prune -f`, `docker image prune -f`, `docker builder prune -f --filter "until=168h"` (build cache older than 7 days only).
10. **Summary:** written to the job summary (ref, migrations, smoke, prune, result). **No secrets.**

### 3.4 How to deploy (typical)

1. Ensure the target `ref` is green in CI.
2. Actions → *Deploy Dev/Staging (manual)* → **Run workflow**.
3. Set `environment=dev`, `ref=version_1` (or a specific SHA), `run_migrations` as needed, and normally leave `force_build=false`.
4. Watch the run; confirm whether it reports `Using prebuilt image` or the safe `Building image on server` fallback, then confirm health 200 + SHA match + postgres/redis `Up`.
5. Confirm provenance independently if desired: `docker exec app-rails-1 cat /app/.git_sha`.

### 3.5 GHCR image path and one-time server activation

A push to `version_1` runs `build-image.yml`, which builds `app/docker/Dockerfile` with the merge SHA and pushes both `<sha>` and `version_1` tags using GitHub's built-in token. The deploy speedup is intentionally **inert until the target server opts in**; merging the workflow alone does not switch a server away from its existing build path.

One-time activation per target server:

1. Ensure `ghcr.io/sameenhewage/bloomwire-app` exists after a successful image workflow and is readable by the server. Make the package public or authenticate Docker with a least-privilege `read:packages` token via `--password-stdin`; never paste or log that token.
2. Update only the gitignored server-local `docker-compose.bloomwire-production.yaml` so both `rails` and `sidekiq` use `image: ${BLOOMWIRE_IMAGE:-bloomwire-app:latest}`. Do not commit the overlay.
3. Run a normal DEV deploy with smoke enabled and prune disabled. Verify `Using prebuilt image`, exact `/app/.git_sha`, local/public health 200, and PostgreSQL/Redis preservation.
4. If activation or registry access is uncertain, use `force_build=true`; no overlay, failed pull, or forced build retains the server-build path.

Activation is an ops phase separate from merging this workflow. It must not change production, volumes, provider credentials, SMTP, DNS, or Meta configuration.

---

## 4. Rollback

Deploys are SHA-addressable, so rollback = redeploy a previous good SHA.

1. Identify the last-good SHA (previous green deploy, or `git log` on `version_1`).
2. Run *Deploy Dev/Staging (manual)* with `ref=<previous-good-sha>`.
3. **Migrations:** rolling **back** a migration is **not** automatic. `run_migrations` defaults to
   **true**, so on a rollback **uncheck it** unless you have a verified down-path; handle schema changes
   deliberately. Prefer expand/contract migrations so old code runs against the new schema.
4. If the previous SHA exists in GHCR and the server is opted in, redeploying that SHA pulls the immutable tag. Otherwise use `force_build=true` to rebuild it from the checked-out source.
5. Fast manual path (image already built/tagged on the host):
   `docker tag bloomwire-app:<previous-sha> <rails-image-name> && docker compose -p app -f ... up -d --no-deps rails sidekiq`.

---

## 5. Do NOT

- Do **not** deploy to production from these workflows (dev/staging only, hard-blocked).
- Do **not** run `docker compose down -v`, `docker volume prune`, or `docker system prune --volumes`
  (destroys Postgres/Redis data). Cleanup is limited to stopped containers, dangling images, and build
  cache **older than 7 days** (`docker builder prune -f --filter "until=168h"`).
- Do **not** print/echo `.env`, SSH keys, DB passwords, Meta app secret, access tokens, or verify tokens.
- Do **not** commit `.env` or `docker-compose.bloomwire-production.yaml` (both gitignored, server-local).
- Do **not** make live Meta/WhatsApp Graph calls from CI.
- Do **not** add a self-hosted runner in this phase.

---

## 6. Troubleshooting

| Symptom | Check |
| --- | --- |
| `Missing SSH_* / DEPLOY_PATH secret` | The selected environment has no secrets configured (§3.2). |
| SSH host-key failure | Set `SSH_KNOWN_HOSTS`, or confirm the host fingerprint for keyscan. |
| Health never reaches 200 | `docker compose -p app -f ... logs --tail 80 rails` on the host; Postgres reachable? entrypoint waits for it. |
| SHA mismatch in smoke | The obtained image does not match the checked-out ref — confirm the requested ref/SHA, GHCR SHA tag, server checkout, and overlay image/build configuration. Never bypass the SHA smoke. |
| Deploy logs `Building image on server` instead of using GHCR | Expected when `force_build=true`, the overlay has not opted in with `BLOOMWIRE_IMAGE`, or the SHA image pull failed. Verify package/workflow status and presence-only Docker login state; never print registry credentials. |
| Deploy reports **success** but the app is still on the OLD SHA (recreate + smoke silently skipped) | The deploy script is piped to the server via `bash -s` over SSH, so a `docker compose run` that attaches stdin (no `-T`) **consumes the rest of the script** — `db:migrate` then ate steps 4–6 and bash exited 0 (false success). Fixed: `db:migrate` runs as `compose run --rm -T rails … </dev/null`. Always verify independently: `docker exec app-rails-1 cat /app/.git_sha` equals the target SHA. |
| `migration-check` red in CI | Run `bundle exec rake db:migrate` locally and commit the updated `db/schema.rb`. |
| `docs-governance` red in CI | A required Bloomwire doc is missing, or a forbidden root `docs/product`/`docs/adr` was added. |
| Devise/transactional email (password reset, **business-owner activation 16C**, platform-admin invite) **does not deliver** on dev | The **global ActionMailer** uses `delivery_method=sendmail` with **no working MTA** → `Errno::EPIPE (Broken pipe)` in the `ActionMailer::MailDeliveryJob` (Sidekiq). This is **separate** from the per-account Bloomwire *Email Settings* SMTP (which can work independently). The action still runs correctly (sets `reset_password_sent_at`, writes the audit row) — only delivery fails. **Fix:** point the global ActionMailer at SMTP (the `SMTP_*` env is already present on the host) — a mail-config change made deliberately by the owner; **do not** change SMTP credentials to work around it. Note: Sidekiq logs ActiveJob args, so Devise reset **tokens appear in worker logs** for all Devise emails (pre-existing Chatwoot behavior). |

---

## 7. Auth go-live guardrails (Phase 15G.2 / 15G.3)

### 7.1 Password changes — rules
- **Never** change a password via the generic SuperAdmin **Users → Edit** form. That form no longer renders a
  password (or `confirmed_at`) field, and the controller strips auth-sensitive params on update (15G.2).
- **Password changes go only through the Devise reset/password flow** (the "Forgot password?" link / reset
  email), or, for an explicit recovery, a deliberate one-user `rails runner` reset with hidden terminal input
  (`read -s`) — never a temp password file, never a printed password.
- New SuperAdmins are created via **Bloomwire → Platform Admins** (the inviter sends a reset email so the new
  admin sets their own password). Platform-admin grant/revoke/reactivate never touch user auth fields.

### 7.2 Admin user-edit audit (Phase 15G.3)
Every admin edit of a user via `super_admin/users#update` writes one `bloomwire_admin_audit_logs` row.
**Recorded (NAMES only, never values):** `actor_id`, `target_user_id`, `controller`, `action`,
`changed_fields` (columns that changed), `blocked_fields` (auth-sensitive params that were submitted but
stripped). **Never stored:** `password`, `password_confirmation`, `encrypted_password`, reset tokens, secrets,
or raw hashes. Query example: `Bloomwire::AdminAuditLog.recent.where(target_user_id: <id>)`.

### 7.3 Auth smoke (dev/staging only)
Optional, operator-run login smoke using a **dedicated, disposable dev/staging test admin** — never the real
owner. Set up a throwaway test SuperAdmin once (via Bloomwire → Platform Admins, or a dev seed), keep its
password in the environment's secret store, then after a deploy run:
```
SMOKE_BASE_URL=https://dev.unecast.com \
SMOKE_EMAIL=<dedicated-dev-test-admin> \
SMOKE_PASSWORD=<dev/staging secret> \
EXPECTED_SHA=<deployed sha> SMOKE_SSH=contabo-dev \
bash .github/scripts/auth-smoke.sh
```
It verifies the sign-in route accepts the test admin (`SMOKE_OK`) and, when `EXPECTED_SHA`+`SMOKE_SSH` are set,
that the in-container `/app/.git_sha` matches (`SHA_OK`). The script enforces a **host allowlist (default-deny)**
— only `dev.unecast.com` (plus any host listed in `SMOKE_ALLOWED_HOSTS`, e.g. a staging host once one exists)
is permitted; **every unknown host, including production, is refused.** It also **refuses the owner account**,
reads the password from a file (never argv/`ps`), prints no secret, and supports `SMOKE_VALIDATE_ONLY=1` to run
just the guards (no login/network). It is **not** wired into the auto-deploy, so no test-admin secret has to
live in CI; run it manually post-deploy (the deploy already does the health + SHA smoke automatically).

---

<sub>Bloomwire Deployment Runbook · docs only · Phase 15G CI/CD foundation + 15G.2/15G.3 auth guardrails · dev/staging only, no production.</sub>
