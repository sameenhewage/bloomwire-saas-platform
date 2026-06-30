# Bloomwire — Project Context (durable)

> **Read this first** for any Bloomwire work, so future sessions understand the project correctly.
> This is the durable "what the project is + the rules." For **current live state + recent sessions**
> see `docs/bloomwire/SESSION-LOG.md`. For deeper per-phase history see `implementation-ledger.md` +
> `change-log.md`. Project contract: `projects/bloomwire-chatwoot-platform/CONTEXT.md`.
> Documentation-only file — no code behavior depends on it.

---

## 1. What Bloomwire is  *(foundational framing — do not re-frame)*

**Bloomwire is a managed business messaging SaaS platform built additively on the Chatwoot engine.**
- **Chatwoot is the current technical / code engine and source-of-truth platform base** (the `app/`
  codebase is literally `@chatwoot/chatwoot`; see ADR `projects/bloomwire-chatwoot-platform/docs/adr/0001-technical-baseline.md`).
  It owns accounts, users, account_users, inboxes, contacts, conversations, and messages.
- **Bloomwire is our product layer** on top of that engine: managed channel **setup / binding / control-plane**
  (not a duplicate account/user/message system), the platform console, workflows, branding, access controls,
  and operational rules.
- **WhatsApp is the first go-to-market managed channel** (the initial target market heavily uses WhatsApp
  Business) and the **current implementation priority** — it is **not** the permanent product boundary (see §2).
- **WhatsWay / WhatsAway are product inspiration / reference / benchmark ONLY — not the current
  codebase base.** Do **not** copy WhatsWay/WhatsAway code or architecture.
- **Do not** frame this as "a generic Chatwoot project," and **do not** contradict the ADR/code
  evidence (the engine is Chatwoot; the product is Bloomwire — managed business messaging, WhatsApp-first to market).

## 2. Product priority & scope
- **WhatsApp is the first go-to-market managed channel and the current implementation priority** — the
  initial target market heavily uses WhatsApp Business. **WhatsApp is not the permanent product boundary.**
- **Future channels (SMS, Microsoft channels, Instagram, Telegram, …) may be added later — without
  replacing the Chatwoot foundation.**
- **Do NOT overbuild for future channels now.** Build the smallest correct thing for the WhatsApp slice in
  front of you (current channel scope = WhatsApp).

## 3. Identity, access & roles  *(auth model — verify against code before changing)*
- **`/super_admin`** is the **internal Bloomwire / platform console** (not a tenant surface).
- **`users.type = 'SuperAdmin'`** is required for the **Rails / Chatwoot STI Devise super_admin
  identity** (this is the engine's existing auth mechanism).
- **Platform access** is controlled by **`bloomwire_platform_admins.role` ∈ {`owner`, `admin`,
  `support`}**, and must be **active / approved**.
- **Business roles are account-scoped** via **`account_users.role` ∈ {`administrator`, `agent`}**.
- **Do NOT introduce a `BusinessOwner` role** unless it is separately designed and approved.

## 4. Data source-of-truth invariants  *(do not break without a separate approved design)*
- **The chat / message source remains the existing source; do NOT duplicate chat / message tables.**
  Chatwoot stays the source of truth for conversations / messages / contacts; Bloomwire registries
  hold only non-secret routing/ownership/status data.
- Do **not** use `users.type` for business/customer roles. No `BusinessOwner` without design.
- No Enterprise dependency. Keep the **WhatsApp-first** scope unless explicitly expanded.

## 5. Operating rules  *(engineering + ops — enforce on every task)*
- **Evidence-first:** no `PASS` without runtime / dev evidence (DOM/MCP/network/DB/spec output as the
  change warrants). "Tests pass" or "build green" alone is **not** PASS.
- **Deploy target is DEV only** by default. **Deploy branch is `version_1`.** PR branches are for
  **CI / review only** (never the deploy source).
- **Do NOT production deploy unless explicitly approved.**
- **No volume prune. No DNS changes** unless explicitly approved. **No SMTP credential changes**
  unless explicitly approved. **No WhatsApp / Meta / provider credential changes.**
- **Never print / log / commit secrets, passwords, tokens, or hashes.**
- **Do NOT create a throwaway owner / user unless explicitly approved.**
- **MCP / browser:** prefer the **existing authenticated owner browser session**. If it is not
  authenticated, **request owner-assisted screenshots / checks** — do not create an owner or handle
  passwords/cookies to force a session.
- **Docs governance:** any **behavior / security / ops** change updates the **change log +
  implementation ledger** (md + html) in the **same PR**; stamp the exact merge SHA + DEV PASS after.
- **Exact-SHA review gate:** before merging a PR whose head SHA changed (e.g. after a rebase),
  **re-verify head == the approved SHA** and re-run the review gate; a changed SHA needs fresh approval.
- **Branch/PR:** one branch per slice/phase off `version_1` → PR into `version_1`; never push directly
  to `version_1`/`main`; open the PR and **stop — do not self-merge** without explicit approval.

## 6. Current Project Status  *(milestone snapshot — live values live in `SESSION-LOG.md` §A)*
- **Dev deployed SHA:** `88e0701` (Phase 15F.6 + 15F.UI code).
- **`version_1` SHA:** `88e0701` was the 15F.UI code merge (PR #90); `version_1` has since advanced to
  **`6cf23b4`** via PR #91 (the docs-only 15F.UI DEV-PASS stamp). _This context PR advances it again._
- **Phase 15F.UI is technically DEV PASS** (responsive grid rules verified live on dev).
- **Owner visual check is still recommended** (before/after screenshots are owner-assisted — the MCP
  browser has no authenticated owner session).
- **The docs-only DEV-PASS stamp for 15F.UI is already merged** (PR #91 → `6cf23b4`).
- **Next step:** owner visual approval of 15F.UI, then **Phase 16 must start with discovery only — no
  code** until a scope is agreed.

## 7. How future sessions should start
1. **Inspect** the current repo + docs first (this file, `SESSION-LOG.md`, `implementation-ledger.md`,
   `AGENTS.md`/`CLAUDE.md`, and the relevant code via the graphify graph). Do not rely on memory.
2. **Summarize the current state** (from `SESSION-LOG.md` §A + the ledger) back to the owner.
3. **Recommend the next step based on evidence**, not assumption.
4. **Do not start coding unless explicitly asked.** Discovery / planning first; implement only the
   agreed slice.
