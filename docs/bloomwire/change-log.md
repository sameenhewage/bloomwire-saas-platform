<!-- Docs only. Bloomwire-owned change log. Kept current per AGENTS.md -> "Bloomwire Documentation Governance". -->

# Bloomwire Change Log

Docs-first change log for **Bloomwire-owned** changes. The full implementation reference lives in
[`implementation-ledger.md`](./implementation-ledger.md); the rule that keeps this file current is
`AGENTS.md` → **"Bloomwire Documentation Governance"** (introduced in Phase 15E.1).

Every entry should record: **phase · PR · merge SHA (once known) · summary · why · what was NOT
changed · validation · residual risks**, and (for security/permission/WhatsApp changes) state
explicitly: **no secrets exposed · no provider-credential mutation unless authorized · whether live
Meta/WhatsApp calls were made · whether Enterprise code was touched.**

---

## Unreleased / Pending Merge

### Phase 15F — Owner-only Email Settings (DB-backed SMTP + templates)
- **PR:** #78
- **Merge SHA:** _pending merge_
- **Type:** Feature (SuperAdmin / Bloomwire owner console)
- **Summary:** Added an owner-only `Bloomwire → Email Settings` page (Overview / Configuration /
  Email Templates / Test Email / Email Logs) inside the existing SuperAdmin shell. Two Bloomwire-owned
  tables: `bloomwire_email_settings` (DB-backed SMTP config; ENV `SMTP_*` only as bootstrap defaults) and
  `bloomwire_email_templates` (6 seeded system templates with `{{variable}}` preview + create / edit /
  duplicate / deactivate / reactivate). Preflight-validated Test Email (real send when complete, honest
  "blocked" otherwise — never fakes success).
- **Why:** Phase 16 onboarding needs configurable outbound email + reusable transactional templates owned
  by the Bloomwire Platform Owner.
- **Access:** owner-only (`Bloomwire::PlatformAdmin` active owners); platform admin/support + customer/
  business users blocked; `/super_admin` boundary unchanged.
- **Not changed:** no WhatsApp/Meta/provider credentials, no Enterprise code, no `BusinessOwner` role, no
  `users.type` for business roles, no chat/message tables, Devise/password-reset mailers untouched.
- **Validation:** model + service + mailer + request specs (52 examples, 0 failures); RuboCop clean;
  existing SuperAdmin specs regression-green (39/0). Browser QA on dev pending (post-approval).
- **Review fixes (post-#78 review):** (1) Overview tab copy made honest — it no longer implies password
  resets/transactional emails already use the DB-backed SMTP; it states Devise/password-reset is unchanged
  and transactional sending is parked. (2) System-template **keys are immutable** — `:key` is not permitted
  on update and a model validation blocks changing a system template's key (future routing depends on stable
  keys); keys are auto-generated on create. (3) CTA URL scheme validation (http/https or `{{placeholder}}`
  only) — closes the previously-flagged non-blocking CTA href concern.
- **Security:** SMTP password is **write-only** in the UI (masked, never rendered/logged/printed). No live
  Meta/WhatsApp calls (tests never send real mail). No provider-credential mutation. No Enterprise touched.
- **Residual / SECURITY DEBT:** `smtp_password` is stored **plaintext** in DB because Active Record
  encryption is not configured on this install. **Encryption-at-rest is a parked Phase 15F follow-up.**
  Also parked: transactional wiring of business-invitation/welcome/plan-change/receipt/ticket mailers to
  the DB-backed config; per-message delivery logging (Email Logs shows the last test result only).
- **Runtime impact:** New owner-only page + 2 new tables (migration). **Deploy required:** Yes (after approval).

### Phase 15E.1 — Documentation Governance Guardrail
- **PR:** #77 (docs-only; amends the Phase 15E PR)
- **Type:** Docs / process
- **Summary:** Added a mandatory **Bloomwire Documentation Governance** rule to `AGENTS.md` and
  `CLAUDE.md`, a **Documentation Governance** section (§10) + Definition of Done to the implementation
  ledger (`.md` + `.html`), and created this change log.
- **Why:** Every Bloomwire-owned change must stay transparent and documented; future agents must not
  make hidden/undocumented changes.
- **Not changed:** no runtime application code, no migrations, no Enterprise, no provider/credentials.
- **Validation:** docs-only diff; HTML self-contained + well-formed; ledger and changelog agree.
- **Residual:** none.
- **Runtime impact:** None · **Deploy required:** No

### Phase 15E — Implementation Ledger
- **PR:** #77
- **Type:** Docs
- **Summary:** Added the Bloomwire Implementation Ledger (`docs/bloomwire/implementation-ledger.md`
  + `.html`): ownership, stable baseline, phase-by-phase log (13B–15D), permission model, WhatsApp
  architecture, OSS/Enterprise stance, intentionally-not-changed list, parked/residual items,
  operational rules.
- **Why:** A clear internal reference before Phase 16 customer onboarding.
- **Baseline documented:** `4084a23eb4a83b1ee41e298811a91d52d6fb6044` (after Phase 15C).
- **Not changed:** no runtime application code, no migrations, no Enterprise, no provider/credentials.
- **Validation:** docs-only diff; HTML self-contained (no CDN/JS).
- **Residual:** none.
- **Runtime impact:** None · **Deploy required:** No

---

## Released

_(none yet — entries move here when the `version_1` line is tagged/released, with their merge SHAs.)_

---

<sub>Bloomwire Change Log · docs only, no runtime behavior · baseline `4084a23eb4a83b1ee41e298811a91d52d6fb6044`.</sub>
