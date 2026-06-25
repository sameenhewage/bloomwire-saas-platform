# Bloomwire — S-07 Live UI Runtime Smoke Report

> **Status:** Runtime baseline / evidence collection only. **No** product code, branches, migrations, PRs, or
> Chatwoot behavior changes were made. **No** feature-toggle or managed-onboarding plan is written here.
> **Spike:** S-07 (UI runtime smoke) from
> [`bloomwire-runtime-analysis-and-rCA-report.md`](./bloomwire-runtime-analysis-and-rCA-report.md) §11.
> **Resolves / advances:** RCA §10 item 7 (UI secret masking), RCA Part 2 Areas **A**, **B**, **C** (Feature-OFF
> baseline), and decision-register linkage **C / Area A,B**.
> **Sources:** [`bloomwire-evidence-collection-report.md`](./bloomwire-evidence-collection-report.md) ·
> [`bloomwire-evidence-review-and-decision-register.md`](./bloomwire-evidence-review-and-decision-register.md).

## Proof labels

- **[RUNTIME-PROVEN]** — verified live in the running app (browser DOM / network / DB), evidence captured below.
- **[CODE-PROVEN]** — previously verified by reading source (see RCA); restated here only for context.
- **[NOT PROVEN]** — still open after S-07 (deliberately or out of scope).

---

## 1. Dev stack boot status

| Component | Status | Detail |
|---|---|---|
| PostgreSQL | **Up (pre-existing)** | `127.0.0.1:5432`, dev DB `chatwoot_dev`. |
| Redis | **Up (pre-existing)** | `127.0.0.1:6379`. |
| Rails backend (Puma) | **Booted by S-07** | Rails 7.1.5.2, `http://127.0.0.1:3000`. App version **Chatwoot 4.15.1**. |
| Vite dev server | **Booted by S-07 (after fix)** | Vite 6.4.2, `http://localhost:3036/vite-dev/`. |
| Sidekiq worker | **Not started** | Not required to render the pages under test; intentionally skipped to reduce noise. |

**Code baseline:** branch `develop` @ commit `56c98c8` ("Initial commit: bloomwire-saas-platform") — a **pure
Chatwoot** snapshot. All Bloomwire slices (PRs #19–#29) live on `version_1`, **not** on `develop`. So `develop` is
the Feature-OFF baseline by construction. **[RUNTIME-PROVEN]**

**Boot blocker encountered + resolution (environment, not product):**
- `bin/vite dev` failed because the default Node on PATH is **v10.24.1** (via nvm) and `pnpm` was not on PATH, but
  `vite@6.4.2` requires Node ≥18. `node_modules` (incl. `node_modules/.bin/vite`) was already installed.
- **Resolution:** ran the Vite dev server under **nvm Node v20.20.2** (which also has `pnpm`); backend + vite were
  started as **separate** background processes so a vite hiccup cannot SIGTERM the Rails backend (foreman couples
  them — when vite exited, foreman killed the whole stack).
- **Action for future spikes:** document that the dev stack must use Node ≥18 for vite; the default nvm Node (v10)
  will not boot the frontend.

---

## 2. Logins used (dev data; no memberships modified)

- **Account workspace + Super Admin console:** `john@acme.inc` / `Password1!` (Chatwoot dev seed).
  - `john@acme.inc` is a **SuperAdmin** *and* an **account administrator** of accounts **1 (Acme Inc)** and
    **2 (Acme Org)** via explicit `AccountUser` rows.
- **The Super Admin Console requires a separate sign-in** at `/super_admin/sign_in`, distinct from the account
  workspace session (`/app/...`). Logging into the account dashboard did **not** grant the super-admin panel; a
  second authentication was required. **[RUNTIME-PROVEN]**
- Read-only DB snapshot at smoke time: 7 users, **2 super admins** (`sameen.android@gmail.com`, `john@acme.inc`),
  5 accounts (`1 Acme Inc`, `2 Acme Org`, `3 Phase2 Verify Co`, `4 NoProfile Co`, `17 Dialog`), 7 account_users,
  **0 WhatsApp channels**, and the 4 `WHATSAPP_*` `InstallationConfig` keys already present.

---

## 3. URLs visited

```
http://127.0.0.1:3000/app/login
http://127.0.0.1:3000/app/accounts/1/dashboard
http://127.0.0.1:3000/super_admin                      (redirects -> /super_admin/sign_in)
http://127.0.0.1:3000/super_admin/users
http://127.0.0.1:3000/super_admin/settings
http://127.0.0.1:3000/super_admin/app_config?config=whatsapp_embedded
http://127.0.0.1:3000/app/accounts/1/settings/inboxes/new/whatsapp
http://127.0.0.1:3000/app/accounts/1/settings/inboxes/new/whatsapp?provider=whatsapp
http://127.0.0.1:3000/app/accounts/1/settings/agents/list
http://127.0.0.1:3000/app/accounts/1/settings/inboxes/list
```

## 4. Screenshots captured

Screenshots were captured locally during the live smoke test and are **intentionally not committed** to the repo —
one capture (`03-...-secret-not-masked`) shows an App Secret in cleartext, so committing it would leak a secret. The
table below is the **textual evidence of record** for what each capture showed:

| File | Shows |
|---|---|
| `01-account-dashboard.png` | Logged-in account workspace (Acme Inc) — SPA + vite rendering. |
| `02-superadmin-users.png` | Super Admin → Users: `Accounts` column (sameen = **0**, john = **2**) and `Type` = SuperAdmin. |
| `03-superadmin-whatsapp-embedded-secret-not-masked.png` | WhatsApp Embedded form with a typed App Secret shown in **cleartext** (not masked). |
| `04-account-whatsapp-provider-chooser.png` | Account → Inboxes → New → WhatsApp: provider chooser (WhatsApp Cloud / Twilio). |
| `05-account-whatsapp-manual-form.png` | Manual WhatsApp Cloud form — the 5 credential fields. |
| `06-account1-agents-list.png` | Account 1 members: `dev-admin@bloomwire.local` + `john@acme.inc`, both Administrator. |
| `07-account1-inboxes-list.png` | Native inbox manager (1 inbox "Acme Support" / Website, "Add Inbox"). |

## 5. Network endpoints observed (live)

| Action | Method + endpoint | Result |
|---|---|---|
| Open Super Admin WhatsApp Embedded page | `GET /super_admin/app_config?config=whatsapp_embedded` | `200`; **only** request — no XHR/fetch, **no webhook call**. |
| Super Admin embedded **save** target | `POST /super_admin/app_config?config=whatsapp_embedded` | Form `action` + CSRF token confirmed in DOM. **Not submitted** (see §6.1). |
| Account manual WhatsApp **create** | `POST /api/v1/accounts/1/inboxes` | Fired with fake creds; left `pending` on external Meta validation; **no channel created** (see §6.2). |

Account-workspace supporting XHRs seen on load (all `200`): `GET /auth/validate_token`, `GET /api/v1/accounts/1/`,
`GET .../labels`, `GET .../teams`, `GET .../custom_attribute_definitions`, `GET .../custom_filters`,
`PUT /api/v1/profile/set_active_account`.

---

## 6. Findings by focus area

### Focus 1 — Super Admin Console → Settings → WhatsApp Embedded

- **Page renders successfully.** Title "Configure Settings - Whatsapp Embedded". **[RUNTIME-PROVEN]**
- **All 4 fields visible.** `WhatsApp App ID`, `WhatsApp App Secret`, `WhatsApp Configuration ID`,
  `WhatsApp API Version` (pre-filled `v22.0`). Field names: `app_config[WHATSAPP_APP_ID|WHATSAPP_APP_SECRET|
  WHATSAPP_CONFIGURATION_ID|WHATSAPP_API_VERSION]`. **[RUNTIME-PROVEN]**
- **App Secret is NOT masked.** The input is `type="text"` (not `type="password"`); a typed value renders in
  cleartext (screenshot `03`). All 4 inputs are `type="text"`. App ID / App Secret / Configuration ID were empty
  (no value stored in this dev DB). **This resolves RCA §10 item 7 at runtime: the UI does not mask the secret.**
  **[RUNTIME-PROVEN]**
- **Save behavior.** Endpoint is `POST /super_admin/app_config?config=whatsapp_embedded` (form action + CSRF).
  **I deliberately did NOT submit** to avoid mutating `InstallationConfig`. Save semantics remain **[CODE-PROVEN]**
  only (RCA §5/§6.A: writes `InstallationConfig` rows; no webhook side-effect).
- **No webhook URL shown or generated; no webhook behavior changed.** The page has no webhook field, and loading it
  produced a single `GET` with no XHR/fetch and no outbound webhook registration. **[RUNTIME-PROVEN]** (consistent
  with RCA §6.A: webhook registration is a per-channel concern, not part of this page.)

### Focus 2 — Account Workspace → Settings → Inboxes → WhatsApp

- **Page renders successfully** and is the **normal account workspace** (left nav: Account Settings, Agents, Teams,
  Inboxes, …; account "Acme Inc") — **not** the Super Admin Console. **[RUNTIME-PROVEN]**
- **Provider chooser:** "WhatsApp Cloud (Quick setup through Meta)" and "Twilio". Selecting WhatsApp Cloud →
  `?provider=whatsapp` → the **manual credential form**. **[RUNTIME-PROVEN]**
- **All 5 fields visible:** `Inbox Name`, `Phone number`, `Phone number ID`, `Business Account ID`, `API key`
  (all `type="text"`), plus a "Create WhatsApp Channel" button. **[RUNTIME-PROVEN]**
- **Submit endpoint + contract (captured live):** `POST /api/v1/accounts/1/inboxes` with body:
  ```json
  {"name":"S07 SMOKE DO NOT KEEP","channel":{"type":"whatsapp","phone_number":"+19998887777",
   "provider":"whatsapp_cloud","provider_config":{"api_key":"FAKE_API_KEY_S07_DO_NOT_SAVE",
   "phone_number_id":"000000000000000","business_account_id":"000000000000000"}}}
  ```
  This matches the documented contract (RCA §3/§6.B). **[RUNTIME-PROVEN]**
- **This is account-level channel/inbox creation UI**, and the customer-facing technical setup **exists in the
  native Chatwoot baseline** — a plain account administrator (`john`) sees the full technical form with **no gating
  or hiding** on `develop`. **[RUNTIME-PROVEN]**
- **Safe-test note:** submitted with **fake** credentials only. Provider validation rejects them, so the request
  stayed `pending` on the external Meta Graph call and **no channel/inbox was created** — verified read-only:
  `Channel::Whatsapp.count == 0`, account 1 still has only its pre-existing `Acme Support` inbox. **[RUNTIME-PROVEN]**

### Focus 3 — SuperAdmin vs Account Administrator

- **A SuperAdmin is NOT automatically an Account Administrator.** In Super Admin → Users, `sameen.android@gmail.com`
  is `Type = SuperAdmin` with **`Accounts = 0`** (zero memberships). DB confirms memberships `[]`. **[RUNTIME-PROVEN]**
- **Membership is explicit.** `john@acme.inc` appears as an **Administrator of account 1** in the account's Agents
  list because he has an explicit `AccountUser` row (he also holds `Accounts = 2` and `Type = SuperAdmin`). Account 1
  members = `dev-admin@bloomwire.local` (Administrator) + `john@acme.inc` (Administrator); the super admin `sameen`
  is **not** in the list. **[RUNTIME-PROVEN]**
- **Separate auth boundary.** The Super Admin Console requires its own `/super_admin/sign_in` even with an active
  account-workspace session. **[RUNTIME-PROVEN]**
- Account **17 "Dialog"** (the Bloomwire test tenant) holds `dialog-admin@dialog.test` (administrator) and three
  `*-agent@dialog.test` agents — none are super admins. **[RUNTIME-PROVEN]**
- **No memberships were modified.**

### Focus 4 — Feature OFF baseline

- `develop` @ `56c98c8` is **pure Chatwoot**: a repo grep found **zero** `bloomwire` references in `app/app`,
  `app/lib`, and `app/enterprise`, and the `BloomwireChannelIntegration` model file is **absent**. **[RUNTIME-PROVEN]**
- **Super Admin WhatsApp Embedded settings are intact** (stock Chatwoot 4.15.1 administrate UI; 4 native fields;
  native endpoint). **[RUNTIME-PROVEN]**
- **Account-level WhatsApp channel setup UI is intact** (native provider chooser + manual form; native
  `/api/v1/accounts/:id/inboxes` endpoint), with **no tenant-side hiding/disabling** — i.e., exactly the surface that
  WA.2D hides for managed accounts on `version_1`. On `develop` it is fully visible = OFF baseline. **[RUNTIME-PROVEN]**
- **No Bloomwire wrapper, toggle, badge, or branding** was observed on any page. **[RUNTIME-PROVEN]**

---

## 7. What is proven live (summary)

1. Dev stack boots and serves both the server-rendered Super Admin Console and the Vue account-workspace SPA.
2. Super Admin WhatsApp Embedded page renders with the 4 expected fields; **the App Secret input is not masked**
   (cleartext `type="text"`) — closes RCA §10 item 7.
3. That page makes no webhook call and exposes no webhook URL (single `GET` on load).
4. Account WhatsApp manual setup renders with the 5 expected fields and submits the documented payload to
   `POST /api/v1/accounts/:id/inboxes`; it is account-level, customer-facing, and native to baseline Chatwoot.
5. A SuperAdmin is not automatically an account admin; account access is via explicit `AccountUser` membership; the
   super-admin panel is a separate login boundary.
6. `develop` is the pure Chatwoot Feature-OFF baseline (no Bloomwire code or UI over these flows).

## 8. What is still NOT proven

- **Super-admin embedded save round-trip** (`POST /super_admin/app_config`) — deliberately not executed to avoid
  mutating installation config. **[NOT PROVEN — by choice]**
- **Whether a *stored* App Secret is echoed back in cleartext** on reload — the field was empty in this DB; the
  controller returning raw values is **[CODE-PROVEN]** only.
- **Final HTTP status of the account WhatsApp create** with fake creds (left `pending` on the external Meta call);
  only the *no-channel-created* outcome was verified.
- **Embedded signup live flow** (needs a real Meta App + populated `whatsapp_embedded` config).
- **RCA §10 items 2–6** (multi-WABA inbound delivery, Bloomwire global ingress, outgoing injection, live
  impersonation visibility/audit, token/log leakage) — **out of S-07 scope**; these remain **S-01..S-06**.

## 9. Blockers / notes

- **Frontend Node version:** vite cannot run on the default nvm Node v10; must use Node ≥18 (used v20.20.2), and
  `pnpm` is only present under newer Node versions. Documented for future runtime spikes.
- **Account WhatsApp create blocks on an external Meta Graph call** during `provider_config` validation; with fake
  creds it fails closed (no channel). Real runtime creation needs valid credentials.
- The Rails backend and vite dev server were left **running** at report time (`:3000` / `:3036`).

## 10. Scope reminder (unchanged)

No product code, branches, migrations, or PRs were created; no Chatwoot behavior was modified; no feature toggle or
managed-onboarding plan was written. **Do not** proceed to S-01..S-06 or to the feature-toggle plan based on this
document alone — S-07 only establishes the live UI/runtime baseline.
