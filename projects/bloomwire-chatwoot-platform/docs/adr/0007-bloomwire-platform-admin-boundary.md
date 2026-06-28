# ADR-0007 — Bloomwire Platform-Admin Boundary (`/super_admin` hardening)

- Status: **Accepted — implemented in Phase 15A.** Adds an explicit Bloomwire platform-admin approval table
  (`bloomwire_platform_admins`) and gates the `/super_admin` console on it **when Bloomwire Mode is ON**.
- Extends: ADR-0001…ADR-0006 (never overrides). Builds on the Phase 11B.7 role contract
  (`docs/security/business-owner-permission-matrix.md`).
- Scope: **authorization boundary only.** No WhatsApp credential changes, no S2/S3 behavior change except
  permission safety, no Meta calls, no WhatsApp sends, no Enterprise code, no deploy.

## Context — identity vs role today

| Concern | Mechanism | Notes |
|---|---|---|
| Platform identity (internal Bloomwire/Chatwoot admin) | `users.type = 'SuperAdmin'` (**Rails STI**, `SuperAdmin < User`) | Only STI subclass of `User`; the `type` column is the STI discriminator. |
| Tenant business role | `account_users.role` enum `{ agent, administrator }` (**per-account**) | Enforced by ~25 Pundit policies via `@current_account_user.administrator?`. A user can hold different roles in different accounts. |
| `/super_admin` access (before 15A) | Devise `:super_admin` scope only (`authenticate_super_admin!` + STI-scoped login `SuperAdmin.find_by!`) | **Any** `SuperAdmin` could reach the whole console + the Sidekiq mount. |

**Decision driver.** "Business Owner/Admin" must stay tenant-scoped (`account_users.role = administrator`) and
**must not** be modeled as a `users.type`. `users.type` is reserved for `SuperAdmin` only. Putting business
meaning into `users.type` would (a) share the privilege discriminator with `SuperAdmin` (escalation surface
if `type` ever becomes mass-assignable), (b) be semantically wrong (global value vs per-account role), and
(c) couple to Devise/STI behavior. See the role-architecture investigation for the full risk analysis.

A second gap: a `SuperAdmin` record created accidentally (seed, console slip, or the Administrate Users page,
whose form exposes `type`) immediately grants **full** platform access. We want a deliberate, auditable
approval step on top of `SuperAdmin` so identity ≠ authorization.

## Decision

When **Bloomwire Mode is ON**, `/super_admin` requires **both**:

1. a `SuperAdmin` session (`users.type = 'SuperAdmin'`, unchanged), **and**
2. an **explicit Bloomwire platform-admin approval** — an active row in a new `bloomwire_platform_admins`
   table (or a bootstrap-allowlisted email, see below).

When **Bloomwire Mode is OFF**, behavior is **stock Chatwoot** (only `SuperAdmin` is required) so the gate is
inert in non-Bloomwire installs.

### Source of truth — `bloomwire_platform_admins`

| Column | Type | Purpose |
|---|---|---|
| `user_id` | bigint, NOT NULL, **unique**, FK→users (`on_delete: cascade`) | the approved `SuperAdmin` user |
| `role` | integer enum `{ owner:0, admin:1, support:2 }`, default `admin` | metadata only (does **not** vary access in 15A) |
| `enabled` | boolean, NOT NULL, default `true` | soft enable/disable |
| `approved_by_id` | bigint, FK→users (`on_delete: nullify`) | who approved |
| `approved_at` | datetime | when approved |
| `revoked_at` | datetime | when revoked (NULL = active) |
| `reason` | text | audit note |
| timestamps | | |

**Active approval** = `enabled = true AND revoked_at IS NULL`.

### Approval predicate (single seam)

`Bloomwire::PlatformAdmin.approved?(user)` ⇒ `true` iff the user has an **active** row **or** the user's email
is in the bootstrap allowlist. This is the only definition of "platform admin", consumed by every seam.

### Bootstrap (self-lockout escape hatch)

`BLOOMWIRE_BOOTSTRAP_PLATFORM_ADMIN_EMAILS` (comma-separated, **ENV-only**, case-insensitive) is treated as
approved even with an empty table. It is **ENV-only on purpose** — it must not be settable from the in-app
SuperAdmin config UI, otherwise the gate could be bypassed from inside the console it protects. Use it to grant
the first platform admin, then record real approvals in the table and remove the env var.

### Protected seams (fail-closed when Mode ON)

1. `SuperAdmin::ApplicationController` — `before_action :require_bloomwire_platform_admin!` **after**
   `authenticate_super_admin!` (covers every Administrate page incl. the Bloomwire S2/S3 surfaces, Users,
   Accounts, Dashboard, etc.).
2. `SuperAdmin::Devise::SessionsController#create` — an unapproved `SuperAdmin` is **refused login** (no
   session is established) with a non-secret message.
3. The Sidekiq/monitoring mount under `authenticated :super_admin` — gated by an approval lambda; an
   unapproved user does not match the route (no disclosure).
4. Any direct `/super_admin/*` URL — covered by (1).
5. Crafted params — `users.type` is **not** permitted by any business/customer user flow (verified); even if a
   `SuperAdmin` is minted via the Administrate Users page, it grants **no** platform access without an approval row.

Unapproved `SuperAdmin` on a console request ⇒ signed out of the `:super_admin` scope + redirected to the
super-admin login with `I18n.t('bloomwire.platform_admin_required')` (a non-secret message).

### Grant / revoke

`Bloomwire::PlatformAdmin.grant!(user:, approved_by:, role:, reason:)` and `.revoke!(user:, reason:)` are
**internal-only** (console/seed). **No management UI ships in 15A** (deliberately minimal slice); the
model/service/tests + the bootstrap path are the documented mechanism. A future slice may add an Ops UI.

## Consequences

- **Positive:** identity (`SuperAdmin`) is decoupled from authorization (approval row); accidental/legacy
  `SuperAdmin` records are inert; the boundary is one predicate reused across all seams; OFF == stock.
- **Cost:** one new table + a required approval step for platform admins; bootstrap env needed for first access.
- **Test-suite impact:** the `:super_admin` factory now creates an approval row by default (trait
  `:unapproved_platform_admin` opts out), so existing Mode-ON super-admin specs stay green and the gate is
  still explicitly tested.

## Non-goals (15A)

No Ops management UI, no per-`role` access differentiation, no change to tenant `account_users.role`
semantics, no WhatsApp/secret changes, no deploy.

---

## Phase 15A.1 — Ownership model + owner-only management UI (Accepted)

Adds the ownership/management layer on top of the 15A boundary. No new migration (schema-only table from 15A
is reused); no `users.type` business roles; no WhatsApp/S2/S3/Meta changes.

### Primary owner bootstrap (env-driven, not hardcoded)
- `BLOOMWIRE_PLATFORM_OWNER_EMAIL` (env/config) names the primary owner. **Never hardcode the email in a
  migration.**
- `Bloomwire::EnsurePlatformOwnerService` (+ rake `bloomwire:ensure_platform_owner`): find user by email →
  ensure `users.type = 'SuperAdmin'` → ensure an active `bloomwire_platform_admins` row with `role = owner`
  (`enabled = true`, `revoked_at = nil`). **Idempotent.** **Fail-safe**: raises (no create) if the email is
  unset or the user does not exist. Output prints `user_id`/`role`/`active` only — **no raw email/secret**.

### Ownership invariants (model)
- `role = owner` is the management role. `last_active_owner?` protects the **only** active owner from
  revoke/demote (`Bloomwire::PlatformAdmin::LastOwnerError`), covering both "revoke last owner" and
  "self-revoke leaving zero owners".
- **Soft revoke only** (`soft_revoke!`): `enabled = false` + `revoked_at`, row kept for audit; reversible via
  `reactivate!` (records the new role/reason). No hard delete in this slice.

### Owner-only management UI (`/super_admin/bloomwire_platform_admins`)
- Inherits the 15A auth chain **and** adds an owner-only gate (`require_platform_owner!`): only an active
  `owner` may list/grant/revoke/reactivate. `admin`/`support` are bounced to the dashboard.
- **Add = create + grant by email** (`Bloomwire::PlatformAdminInviter`):
  - new email ⇒ create a `SuperAdmin` + active approval row + role; send a Devise reset-password email so the
    new admin sets their own password (**no raw password** created in/returned to the UI);
  - existing `SuperAdmin` ⇒ (re)grant/reactivate + set role (refusing to demote the last owner);
  - **existing business/customer user (`users.type = nil`) ⇒ REFUSED** — never converted to `SuperAdmin`;
    business roles stay in `account_users.role`.
- Owner shown as **"Platform Owner"**; the last owner shows "Protected (last owner)" with no revoke control.

### Validation (specs + local; no deploy)
Setup task makes the owner a SuperAdmin + active owner; owner can access `/super_admin`; revoking/demoting the
last owner is blocked; unapproved SuperAdmins and business users are blocked; no WhatsApp/S2/S3/Meta change.
