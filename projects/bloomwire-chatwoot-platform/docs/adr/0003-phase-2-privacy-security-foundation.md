# ADR 0003 — Phase 2: Privacy / Security Foundation

- **Status:** Accepted (Phase 2A implementation slice; Phase 2B+ decisions deferred)
- **Date:** 2026-06-26
- **Context source:** `../research/bloomwire-final-feature-toggle-architecture-plan.md` (§11 Privacy/Security
  Architecture, §12 Phase 2), `../research/bloomwire-s05-s06-privacy-security-runtime-report.md` (§7 Privacy Hardening
  Insertion Points), ADR-0001, and ADR-0002. **Extends — never overrides — ADR-0001 / ADR-0002.**

## Context

Phase 1 (ADR-0002) established the feature-toggle infrastructure (`Bloomwire::Features`, `InstallationConfig` keys,
master AND-gate, SuperAdmin bootstrap page). Phase 2 implements privacy/security hardening behind the
`BLOOMWIRE_PRIVACY_HARDENING` toggle. S-05/S-06 confirmed real risks (impersonation/self-add reach tenant data, CE
audit inert, message-body/token leakage in logs + Sidekiq args, `provider_config` exposed in DTOs, and the SuperAdmin
WhatsApp Embedded **App Secret rendered in cleartext**).

The full Phase 2 objective (plan §12) is large. To keep changes small and reversible, Phase 2 is split into slices.
This ADR records **Phase 2A** (the first slice) and **explicitly defers** the heavier security decisions so they are
not made silently.

## Decision

### Phase 2A — LOCKED (implemented in this slice)

Phase 2A masks the SuperAdmin **App Secret** (`InstallationConfig` key `WHATSAPP_APP_SECRET`) on **every** SuperAdmin
console surface that renders it. The masked-key set + the gate live in **one seam** (ADR-0002 §2 single feature-read
seam): `Bloomwire::Features::MASKED_SECRET_KEYS` + `Bloomwire::Features.masked_secret_key?(name)`, which is
master-AND-gated via `enabled?(:privacy_hardening)`. No scattered `ENV`/Features reads.

1. **App Config surface** (`/super_admin/app_config?config=whatsapp_embedded`):
   - render the App Secret input as `type="password"` (not `type="text"`) and **never echo** the stored value (blank on
     load, with a "leave blank to keep current" hint);
   - a **blank** submit must **not** overwrite the stored secret; a non-blank submit updates it.

2. **Generic Administrate surface** (`/super_admin/installation_configs` index / show / `:id/edit`):
   - **index & show**: render a redacted placeholder instead of the stored value (`SerializedField` `_index` / `_show`);
   - **edit / new form**: render a `type="password"` field with **no echoed value** (`SerializedField` `_form`);
   - **update / create**: a **blank** value for a masked key is dropped from `resource_params` so it **cannot wipe** the
     stored secret; the existing managed-data privacy-prerequisite guard is unchanged.

**Gate / OFF = stock:** every behavior above is active only when `Bloomwire::Features.masked_secret_key?(name)` is true
(master ON **and** privacy hardening ON). With privacy hardening OFF **or** master OFF, both surfaces render
byte-for-byte stock Chatwoot (S-07 baseline). **No tenant-facing change.**

**Scope:** only keys in `MASKED_SECRET_KEYS` (currently `WHATSAPP_APP_SECRET`). Other secret fields are out of 2A scope.

### Phase 2B+ — DEFERRED (NOT decided here; open gates)

These are recorded as **open decisions**, not silently made:

2. **`provider_config` secret-at-rest mechanism** — encrypt (`encrypts` / external custody) **or** formally
   accept + document. Plan §11 marks it a blocking decision gate before real managed data. **DEFERRED.**
3. **Impersonation policy** — gate/restrict SuperAdmin impersonation and the exact policy (allow/deny/approval).
   **DEFERRED.**
4. **Support-access audit model** — a Bloomwire-owned, CE-safe audit (independent of the inert enterprise
   `audit_logs`) for impersonation / self-add / cross-tenant reads. **DEFERRED.**
5. **Sidekiq payload redaction/encryption strategy** — non-mutating only (log/display redactor, encrypted job args,
   or out-of-band encrypted payload + reference); never strip `text.body` the worker consumes (plan §11). **DEFERRED.**

Also still in Phase 2 but outside 2A: `provider_config` DTO scrub (`_inbox.json.jbuilder`), explicit-log token/error
scrubbing, and self-add controls.

## Consequences

- Phase 2A ships **dark**: with `BLOOMWIRE_PRIVACY_HARDENING` OFF (or master OFF) the App Config page is byte-for-byte
  stock Chatwoot. Rollback = toggle OFF.
- The masking is a UI/echo control only; it does **not** change how/where the secret is stored (secret-at-rest is the
  deferred gate #2).
- Managed-data toggles remain fail-closed (ADR-0002 §5) until the remaining Phase 2 controls land.
- The four deferred decisions (#2–#5) are tracked here and must be resolved in their own slices/ADR updates before the
  managed-data phases that depend on them.

## Alternatives rejected

- **Add `type: secret` to `WHATSAPP_APP_SECRET` in `installation_config.yml`** instead of gating in the view: rejected
  for 2A — it would change stock behavior unconditionally (OFF would no longer equal stock) and the stock `secret`
  branch still echoes `value:`, so it would not satisfy "never echo".
- **Implement secret-at-rest encryption / impersonation / audit now:** rejected as scope creep; each is a separate
  decision requiring its own slice (gates #2–#5).
- **Mutating Sidekiq job args to strip bodies:** rejected per plan §11 (breaks `Message#content` creation).
