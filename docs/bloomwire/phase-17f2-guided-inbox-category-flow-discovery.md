<!--
  Bloomwire Phase 17F.2 — Guided "Add WhatsApp Inbox to Category" Flow — DISCOVERY & IMPLEMENTATION CONTRACT.
  DOCS ONLY. No runtime behavior, no code, no schema, no migration, no deploy. This document evaluates a candidate
  flow and defines the contract for a future implementation; it does NOT implement the write flow.
-->

# Phase 17F.2 — Guided "Add WhatsApp Inbox to Category" Flow — Discovery & Implementation Contract

- **Status:** DISCOVERY + CONTRACT only (docs-only). **No product code / tests / schema / migration / workflow /
  env changes. No implementation.**
- **Base branch / tip:** `version_1` @ `bb2a3d7d6c22b52627b6b17f747b64972e6ea609` (verified).
- **DEV deployed runtime SHA:** `7bc59c74ba5f96fc7ed394b0335dc216d4ab6529` (Phase 17F.1; `bb2a3d7` is a docs-only
  commit on top, so DEV runtime and `version_1` differ only by documentation).
- **Predecessor:** Phase 17F.1 (read-only "Categories & Inboxes" admin overview) — merged (PR #119) + DEV-validated.
- **Product foundation:** additive on the Chatwoot OSS engine. Reuse existing Chatwoot/Bloomwire models, services,
  routes, policies and screens. No new Chatwoot; no WhatsWay/WhatsAway; Enterprise unused; WhatsApp is the current
  channel scope; **feature OFF preserves stock-compatible Chatwoot OSS behavior.**

---

## 1. Executive summary + final recommendation

**Question posed:** can the guided "Administrator opens Categories & Inboxes → picks a category (Team) → Add WhatsApp
Inbox (Standard or Coexistence) → reuse the existing wizard → then assign staff → return to the overview showing the
final relationship/drift state" journey be implemented **safely without a new mapping and without a transaction
spanning external Meta operations**?

**Answer: YES — and it requires essentially no new backend.** Every step already exists as an admin-only,
account-scoped, backend-enforced primitive:

- WhatsApp inbox creation (Standard + Coexistence) is already an **atomic** operation: the setup service performs all
  Meta calls **first**, then wraps `Channel::Whatsapp → Inbox → credential → Bloomwire::WhatsappSetup` in **one
  `ActiveRecord::Base.transaction`** that rolls back cleanly on any failure (no orphans). This transaction **does not
  span** the Meta calls.
- Staff assignment is already two admin-only, transactional, idempotent, **reversible** endpoints (`TeamMember` and
  `InboxMember`).
- The 17F.1 overview already **surfaces partial completion explicitly** (unlinked inbox, category-with-no-inbox,
  ambiguous, drift) — so an interrupted flow is never corrupt or hidden; it is visible and recoverable.

**Final recommendation: PROCEED, with a scope revision — implement 17F.2 as a HYBRID "thin launcher", and split the
guided staff/dual-membership assist into a separate 17F.3 slice.** Concretely:

- **17F.2 = frontend-only thin launcher** (feature-gated, admin-only) that adds an **"Add WhatsApp Inbox"** affordance
  to each category in the existing 17F.1 overview and **deep-links into the existing Add-Inbox → WhatsApp wizard**
  (`settings_inboxes_page_channel` / `whatsapp` → `BloomwireWhatsapp.vue`). It introduces **no new backend endpoint,
  no new mapping, no writes of its own** beyond what the existing wizard already performs. On return, the existing
  overview shows the new inbox's relationship/drift state.
- **17F.3 = guided dual-membership assist** (separate slice): an **explicit, reversible, backend-enforced** step that
  helps the admin align the *same* staff across the selected **Team** (`TeamMember`) and the new **Inbox**
  (`InboxMember`) so the derived category↔inbox link forms with no drift — composing the existing membership
  endpoints (optionally behind one tiny **local-only** transaction helper; **never** a transaction that spans a Meta
  call).

**Why not one big guided screen with its own orchestration service?** Because a single backend orchestration that
created the inbox *and* assigned staff would either (a) wrap the Meta-bound setup and the membership writes in the
same transaction — which is impossible to do safely (you cannot roll back a Meta-side app-to-WABA subscription inside
a DB transaction), or (b) re-implement/duplicate the existing setup + membership services. Both violate the locked
architecture boundaries. The thin-launcher + separate-assist shape avoids all of this.

---

## 2. Current architecture & exact code paths (evidence)

All paths are under the Rails app root `app/` (i.e. `app/app/controllers`, `app/app/services`, `app/app/models`,
`app/app/policies`, `app/config/routes.rb`, `app/app/javascript/dashboard`, specs under `app/spec`).

### 2.1 Standard WhatsApp Embedded Signup
- **Route** (`app/config/routes.rb:354-356`): `POST /api/v1/accounts/:account_id/bloomwire/whatsapp/embedded_signup`.
- **Controller** `app/app/controllers/api/v1/accounts/bloomwire/whatsapp/embedded_signups_controller.rb`:
  - `before_action :ensure_managed_whatsapp_self_serve!` → `head :not_found` unless
    `Bloomwire::Features.restrict_native_whatsapp_setup? && Bloomwire::Features.enabled?(:managed_whatsapp_onboarding)`.
  - `before_action :check_admin_authorization?` (agents → Pundit not-authorized / 401).
  - Permitted params: `:code, :business_id, :waba_id, :phone_number_id, :display_phone_number`.
  - Delegates to `Bloomwire::WhatsappEmbeddedSignupService#perform`; renders `result.dto` (201) or a **safe** error
    (`SAFE_ERROR_MESSAGES`; `:meta_error → 502`, others `422`). **Never returns provider_config/tokens.**
- **Service** `app/app/services/bloomwire/whatsapp_embedded_signup_service.rb`:
  - **Meta steps FIRST (outside any DB transaction)**: `Whatsapp::TokenExchangeService`, `Whatsapp::PhoneInfoService`,
    `Whatsapp::FacebookApiClient#subscribe_app_to_waba` (app-to-WABA subscription only — the **global router**; never
    `setup_webhooks`/`override_waba_callback`/`subscribe_waba_webhook`). On any Meta failure → logs class only, returns
    `:meta_error`, **writes nothing**.
  - **Then `persist` in `ActiveRecord::Base.transaction`**: (1) `Channel::Whatsapp` shell (`source: 'bloomwire_managed'`),
    (2) `Inbox`, (3) `Bloomwire::WhatsappCredentialWriter` (encrypted `api_key`), (4) `Bloomwire::WhatsappSetupCreator`
    (the `Bloomwire::WhatsappSetup` router mapping). On mapping failure → `raise ActiveRecord::Rollback`; on unique
    violation → rescued `:phone_number_taken`. **No orphaned rows on partial failure.**

### 2.2 WhatsApp Business App Coexistence
- **Route** (`routes.rb:354-356`): `POST /api/v1/accounts/:account_id/bloomwire/whatsapp/coexistence_embedded_signup`.
- **Controller** `.../whatsapp/coexistence_embedded_signups_controller.rb`: identical gate/auth/safe-DTO pattern.
- **Service** `app/app/services/bloomwire/whatsapp_coexistence_embedded_signup_service.rb` **inherits** the Standard
  service; only overrides `create_channel_shell` to set `provider_config['connection_mode'] = 'coexistence'` and adds
  `connection_mode` to the DTO. Same transaction boundary + rollback + duplicate handling.

### 2.3 Inbox creation (stock Chatwoot)
- **Route** (`routes.rb:254`): `POST /api/v1/accounts/:account_id/inboxes`.
- **Controller** `app/app/controllers/api/v1/accounts/inboxes_controller.rb#create` (lines 54-67):
  `ActiveRecord::Base.transaction` → `create_channel` (via `account_channels_method`) then `Current.account.inboxes.build`.
  - Bloomwire guards run first: `restrict_native_whatsapp_setup!`, `restrict_external_provider_channel_setup!`,
    `restrict_inbox_creation!` (managed mode blocks native/self-serve inbox creation), then `check_authorization`.
  - **Admin-only** (`InboxPolicy#create? → administrator?`); agent → 401.

### 2.4 Channel creation
- `Inbox has_one :channel, polymorphic`. `Channel::Whatsapp` (`app/app/models/channel/whatsapp.rb`): provider
  `default`/`whatsapp_cloud`; `provider_config` **encrypted at rest** (ADR-0006); `EDITABLE_ATTRS =
  [:phone_number, :provider, {provider_config:{}}]`. The managed setup services build the channel directly (they do
  **not** go through the stock inboxes controller), which is why they can run while `restrict_inbox_creation!` blocks
  the stock path.

### 2.5 `Bloomwire::WhatsappSetup` creation
- Model `app/app/models/bloomwire/whatsapp_setup.rb`: references account/inbox/channel + **non-secret** routing ids
  (`phone_number_id`, `waba_id`, `display_phone_number`) + `setup_status` (`pending`/`configured`/`ready_for_webhook`/
  `blocked`). **No secrets stored here.** `phone_number_id` partial-unique index; `ready_for_webhook` requires
  phone_number_id + inbox + channel and router alignment.
- Service `app/app/services/bloomwire/whatsapp_setup_creator.rb`: `find_or_initialize_by(channel_whatsapp_id:)` →
  idempotent per channel; **makes no Meta calls**, **creates no channel/inbox**, **rejects any secret argument**
  (raises `ArgumentError` on `api_key`/`provider_config`).

### 2.6 Team / category creation & editing
- **Routes** (`routes.rb:299`): `POST/PATCH/DELETE /api/v1/accounts/:id/teams(/:id)`.
- **Controller** `app/app/controllers/api/v1/accounts/teams_controller.rb` (create/update/destroy). Permitted:
  `team: [:name, :description, :allow_auto_assign]`. **Admin-only** (`TeamPolicy` → `administrator?`); agent → 401.
  Account-scoped via `Current.account.teams`. Team **name is downcased + unique per account**.

### 2.7 `TeamMember` assignment/removal
- **Routes** (`routes.rb:300,302`): `POST` / `PATCH` / `DELETE` `/api/v1/accounts/:id/teams/:team_id/team_members`.
- **Controller** `app/app/controllers/api/v1/accounts/team_members_controller.rb`. Body `{ user_ids: [] }`.
  `before_action :validate_member_id_params` (user_ids must belong to the account). Each action wraps
  `ActiveRecord::Base.transaction`. **Admin-only** (`check_authorization` → `TeamPolicy`); agent → 401.
  Semantics: `POST` = add-only, `PATCH` = replace (diff add+remove), `DELETE` = remove-only; **all idempotent**.
  Maps to `Team#add_members` / `Team#remove_members`.

### 2.8 `InboxMember` assignment/removal
- **Routes** (`routes.rb:278,280,281`): `POST` / `DELETE` / `PATCH` `/api/v1/accounts/:id/inbox_members`.
- **Controller** `app/app/controllers/api/v1/accounts/inbox_members_controller.rb`. Body `{ inbox_id, user_ids: [] }`.
  Each action `authorize @inbox, :create?/:update?/:destroy?` (**admin-only** via `InboxPolicy`) + wraps a transaction.
  Semantics add-only/replace/remove-only; **idempotent**. Maps to `Inbox#add_members` / `Inbox#remove_members`.
  Note: `InboxMember` create/destroy trigger round-robin queue callbacks.
- **Existing wizard step:** the stock new-inbox flow already includes an inbox-agent step —
  route `settings_inboxes_add_agents` → `AddAgents.vue` (calls `inbox_members` create) — reachable after inbox creation.

### 2.9 Existing Settings → Categories & Inboxes overview (17F.1)
- **Route** (`routes.rb`, bloomwire namespace): `GET /api/v1/accounts/:id/bloomwire/category_inbox_overview` →
  `Api::V1::Accounts::Bloomwire::CategoryInboxOverviewController#show` (`before_action :ensure_category_admin_ui!` →
  404 when `BLOOMWIRE_CATEGORY_ADMIN_UI` OFF; then `check_admin_authorization?`).
- **Service** `app/app/services/bloomwire/category_inbox_overview.rb`: **read-only** safe DTO. Categories = Teams; every
  inbox classified once as `linked` (member overlap with exactly one team), `ambiguous` (>1 team), or `unlinked`
  (0 teams); per-linked-pair `drift` (staff missing inbox access / collaborators not on team); WhatsApp badge
  (`connection_mode`) + `setup_status` with **`not_configured`** fallback. **Never serializes provider_config/secrets.**
- **Frontend** `app/app/javascript/dashboard/routes/dashboard/settings/categoryInboxes/`: `Index.vue` +
  `InboxSummary.vue`; API client `api/bloomwire/categoryInboxOverview.js`; route + `redirectIfCategoryAdminDisabled`
  guard; capability `canAccessCategoryAdmin` (`Bloomwire::Capabilities` + `useBloomwireCapabilities`, default false);
  sidebar nav entry. Error+retry state present. **No write controls.**

### 2.10 Existing Team, Inbox and Agents deep-links
- `Index.vue`/`InboxSummary.vue` deep-link to route names **`settings_teams_edit`** (`{ teamId }`),
  **`settings_inbox_show`** (`{ inboxId }`), and **`agent_list`**. The WhatsApp wizard is reachable at
  **`settings_inboxes_page_channel`** (`sub_page: 'whatsapp'`) → `ChannelFactory.vue` → `BloomwireWhatsapp.vue` when
  `canSelfServeManagedWhatsapp` is true (the Standard/Coexistence connection-choice screen). The stock inbox-agents
  step is **`settings_inboxes_add_agents`** → `AddAgents.vue`.

### 2.11 Admin vs agent backend policies
- `application_policy.rb` defaults create/update/destroy to `false`. `InboxPolicy` / `TeamPolicy` write actions →
  `@account_user.administrator?`. `api/base_controller.rb#check_admin_authorization?` raises `Pundit::NotAuthorizedError`
  (rendered 401 by `request_exception_handler`). **Every** write path above is admin-only; **frontend hiding is UX
  only — the controller/policy is the boundary.**

### 2.12 Account isolation
- `Current.account`/`Current.account_user` set per request (`ensure_current_account_helper.rb`). Every controller
  scopes through `Current.account.<association>.find(...)` → cross-account ids raise `RecordNotFound`. `team_members`
  additionally validates `user_ids ⊆ account.user_ids`. The overview service is `account`-scoped.

### 2.13 Feature flags & capabilities
- `app/lib/bloomwire/features.rb` SUB_FEATURES (master-gated by `BLOOMWIRE_MODE_ENABLED`): includes
  `category_admin_ui` (`BLOOMWIRE_CATEGORY_ADMIN_UI`), `managed_whatsapp_onboarding` (privacy-dependent),
  `restrict_native_whatsapp_setup`, `restrict_provider_setup`, `restrict_bot_management`, etc.
- `app/lib/bloomwire/capabilities.rb` derives camelCase booleans for the FE (`Bloomwire::Capabilities.for`): e.g.
  `canAccessCategoryAdmin = managed_capability(admin, Features.enabled?(:category_admin_ui))`;
  `canSelfServeManagedWhatsapp = managed_capability(admin, restrict_native_whatsapp_setup? &&
  Features.enabled?(:managed_whatsapp_onboarding))`. Consumed by `useBloomwireCapabilities` (opt-in caps default false).

### 2.14 Existing transaction boundaries (summary)
| Operation | Transaction? | Scope |
|---|---|---|
| WhatsApp setup (Standard/Coex) | **YES** | channel + inbox + credential + setup — **after** the Meta calls (Meta is outside the txn) |
| Stock inbox create | YES | channel + inbox |
| `team_members` create/update/destroy | YES | membership diff |
| `inbox_members` create/update/destroy | YES | membership diff |
| `Bloomwire::WhatsappSetupCreator` | single `save` | one setup row (idempotent per channel) |
| Team create/update/destroy | none needed | single AR op |

### 2.15 Validation & rollback behavior
- WhatsApp setup: pre-flight fail-closed (`not_ready`/`encryption_not_configured`/`missing_code`) before any Meta/DB
  work; Meta failure → sanitized `:meta_error`, no DB writes; DB failure inside txn → full rollback (no orphans);
  duplicate → `:phone_number_taken`/`:phone_number_id_conflict`.
- Membership: per-request transaction; invalid/foreign user_ids rejected (422/401) before mutation; idempotent.

### 2.16 Behavior in the specified edge situations
| Situation | Current behavior (evidence) | 17F.2 implication |
|---|---|---|
| WhatsApp setup succeeds but staff assignment fails | Inbox exists (atomic setup txn committed); membership is a **separate** later call — its failure leaves the inbox as **unlinked** (no team overlap) in the overview. No corruption. | Decouple the two steps; rely on overview visibility + retry. |
| Inbox membership succeeds but team membership fails (or vice versa) | Two **separate** transactional endpoints; a partial pair produces **drift** (member on one side only), shown explicitly in the overview. | 17F.3 may wrap the two **local** membership writes in one local txn for atomicity (safe — no Meta), or keep separate + rely on drift. |
| Duplicate phone number / phone_number_id | Setup service returns `:phone_number_taken` / `:phone_number_id_conflict` (422); channel unique index + setup partial-unique index; rolled back. | Surface the existing safe error; no new handling. |
| Inbox overlaps multiple teams | Overview `relationship_status='ambiguous'`, shown in a dedicated ambiguous section with matched team names. | Adding from one category reduces but cannot prevent ambiguity; overview surfaces it. |
| Team has no inbox | Overview `has_inbox=false` + "no inbox" warning on the category. | This is exactly the entry point for "Add WhatsApp Inbox". |
| Inbox has no matching team | Overview `unlinked` section. | 17F.3 dual-membership assist resolves it. |
| Setup row missing | `whatsapp_summary.setup_status = 'not_configured'` fallback. | Surface; existing setup/reauth flow owns it. |
| Feature disabled (`BLOOMWIRE_CATEGORY_ADMIN_UI` OFF) | Overview endpoint 404; page/nav absent; **stock Chatwoot** preserved. | 17F.2 launcher must live behind the same capability/gate → OFF ⇒ launcher absent. |
| Agent calls the APIs directly | Every setup + membership + team/inbox write endpoint is **admin-only** → 401. | 17F.2 adds **no** new agent-reachable write surface. |

---

## 3. Current request/response contracts (reused as-is)

| Endpoint | Method | Auth/gate | Request | Response (success) | Failure |
|---|---|---|---|---|---|
| `.../bloomwire/whatsapp/embedded_signup` | POST | admin + managed-WA gate | `{code, business_id, waba_id, phone_number_id, display_phone_number}` | `201` safe DTO (`inbox`, `channel{source}`, `setup{status}`, masked phone) | `422`/`502` safe `{error, code}` |
| `.../bloomwire/whatsapp/coexistence_embedded_signup` | POST | admin + managed-WA gate | same | `201` safe DTO + `connection_mode='coexistence'` | same |
| `.../teams` | POST/PATCH/DELETE | admin | `{team:{name,description,allow_auto_assign}}` | team JSON | 401 (agent) / 422 |
| `.../teams/:team_id/team_members` | POST/PATCH/DELETE | admin | `{user_ids:[]}` | team members JSON | 401 / 422 (bad user_ids) |
| `.../inbox_members` | POST/PATCH/DELETE | admin | `{inbox_id, user_ids:[]}` | inbox members JSON | 401 / 422 |
| `.../bloomwire/category_inbox_overview` | GET | admin + `category_admin_ui` | — | read-only safe DTO (`categories`, `ambiguous_inboxes`, `unlinked_inboxes`, `derivation`) | 404 (OFF) / 401 (agent) |

---

## 4. Failure & rollback matrix (candidate flow)

The candidate flow is a **sequence of already-atomic steps**, not one atomic super-operation. Each step's failure is
contained and surfaced:

1. **Create inbox (Standard/Coex)** — atomic (Meta then DB txn). Fail ⇒ nothing created (or `:phone_number_taken`);
   safe error shown. **No compensation needed.**
2. **Assign inbox members** (`inbox_members`) — atomic. Fail ⇒ inbox stays `unlinked`/`not_configured` in overview.
3. **Assign team members** (`team_members`) — atomic. Fail ⇒ drift shown.
- **Cross-step partial completion is always visible + recoverable** via the 17F.1 overview; **never a corrupt or
  hidden state.** No new "orchestration transaction" is introduced. A Meta-spanning transaction is **explicitly
  rejected** as unimplementable/unsafe (cannot roll back a Meta subscription inside a DB txn).

---

## 5. Security & authorization matrix

| Actor / state | Overview | Launcher (17F.2) | WA setup | team/inbox members |
|---|---|---|---|---|
| Admin, feature ON | 200 read-only | visible | 201 (managed gate on) | 200 |
| Agent, feature ON | 401 | absent (capability false) + backend 401 | 401 | 401 |
| Any role, `category_admin_ui` OFF | 404 | absent | unaffected (own gate) | unaffected |
| Cross-account | scoped-out | n/a | cross-account denied | `RecordNotFound`/401 |
- **No secrets** (`provider_config`, tokens, Meta/Shopify credentials) are ever returned or logged by any reused path.
- **Frontend hiding is not the boundary** — every write is admin-enforced server-side.

---

## 6. Feature ON/OFF behavior
- **`BLOOMWIRE_CATEGORY_ADMIN_UI` OFF ⇒** overview 404, no page/nav, **and** the 17F.2 launcher is absent → stock
  Chatwoot (admins still create inboxes/teams via the normal stock screens). The managed WhatsApp wizard has its **own**
  gate (`restrict_native_whatsapp_setup? && managed_whatsapp_onboarding`) which is independent and unchanged.
- No new master toggle is required; 17F.2 rides the existing `canAccessCategoryAdmin` (page/launcher) +
  `canSelfServeManagedWhatsapp` (wizard availability) capabilities.

---

## 7. Recommended UX flow (evaluated, not implemented)
1. Admin opens **Settings → Categories & Inboxes** (existing 17F.1 page).
2. On a category row (esp. a `has_inbox=false` category), an **"Add WhatsApp Inbox"** button (admin-only,
   capability-gated).
3. Clicking it deep-links to the **existing** Add-Inbox → WhatsApp wizard (`settings_inboxes_page_channel` /
   `whatsapp` → `BloomwireWhatsapp.vue`) → Standard / Coexistence connection choice → existing wizard completes the
   atomic inbox creation (and the existing `settings_inboxes_add_agents` inbox-agent step remains available).
4. On return to the overview, the new inbox appears with its true `linked/unlinked/ambiguous` + `drift` state.
5. **(17F.3)** For an `unlinked` inbox / drifted pair, a **"Assign staff to this category"** guided assist presents the
   Team's members and the Inbox's collaborators side by side and lets the admin **explicitly** align them using the
   existing `team_members` + `inbox_members` endpoints (reversible).

---

## 8. Recommended backend orchestration
- **17F.2: none.** Reuse existing endpoints. No new controller/service/route/mapping.
- **17F.3 (optional, small, local-only):** *if* an atomic "align these users into both the Team and the Inbox" action
  is desired, a **thin admin-only, feature-gated** helper may wrap **two local DB writes** (`TeamMember` +
  `InboxMember`) in **one `ActiveRecord::Base.transaction`** (no Meta, no schema, no new mapping table, reversible via
  existing remove endpoints). This is the **only** place a new backend surface might be justified — and it must remain
  purely local. Alternative: no backend at all; the FE calls the two existing endpoints sequentially and relies on
  drift-visibility for the rare partial. **Default recommendation: start with the no-backend FE composition; add the
  local-transaction helper only if runtime evidence shows partial-pair drift is a real operational problem.**

---

## 9. Recommended frontend orchestration
- **17F.2:** add a capability-gated launcher (button + deep-link) to `categoryInboxes/Index.vue` (and/or a category
  detail affordance). No new API client. No writes. Optionally pass the selected `team_id` as context (query param or
  a lightweight store) so 17F.3 can pre-select the category for alignment — but **not required** for 17F.2 itself.
- **17F.3:** a small guided panel (reuse `AddAgents.vue`-style member pickers / existing `teams.js` + `inbox_members`
  API clients) that shows Team members vs Inbox collaborators and applies explicit, reversible alignment.

---

## 10. Flow shape decision — one screen vs thin launcher vs hybrid
**Recommendation: HYBRID (thin launcher + separate guided assist).**
- A single guided multi-step screen that *embeds* setup + membership would tempt a spanning orchestration and would
  duplicate the existing wizard — rejected.
- A pure thin launcher alone (deep-link only) is the safest first slice (17F.2) and delivers immediate value.
- The guided dual-membership assist (17F.3) adds the "make it linked/no-drift" convenience **without** new external
  transactions.

---

## 11. Safe handling of partial completion
- **Principle:** never introduce a state the 17F.1 overview cannot already explain. Inbox-without-staff ⇒ `unlinked`;
  one-sided membership ⇒ `drift`; missing setup ⇒ `not_configured`; ambiguous overlap ⇒ `ambiguous`. All are visible,
  labelled, and fixable by re-running the relevant existing endpoint. **No hidden/auto "repair".**
- **No automatic membership synchronization.** Any alignment is admin-initiated, explicit, reversible, and
  backend-enforced (locked boundary).

---

## 12. Staff assignment: 17F.2 or 17F.3?
**Recommendation: 17F.3 (separate slice).** Rationale: inbox creation is Meta-bound and atomic; staff/dual-membership
is local, reversible, and independently testable. Splitting keeps each slice small, keeps 17F.2 write-free
(frontend-only launcher), and lets the dual-membership design (and the optional local-transaction helper) get its own
RED→GREEN + review.

---

## 13. Proposed implementation slices
- **17F.2 — Guided launcher (frontend-only).** Capability-gated "Add WhatsApp Inbox" from a category → deep-link to the
  existing WhatsApp wizard. No backend, no writes, no schema. Feature OFF ⇒ absent.
- **17F.3 — Guided dual-membership assist.** Explicit, reversible alignment of the same staff across Team + Inbox via
  existing endpoints; optional thin **local-only** transaction helper. No schema, no new mapping.
- **17F.4 (parked, owner-approval-gated) — persistence, if and only if runtime proves convention-only insufficient.**
  A reversible `Inbox↔Team` mapping/data-tag remains **out of scope** and requires a **separate owner-approved design +
  ADR** (per 17F.0). **Not authorized here.**

---

## 14. Proposed RED→GREEN tests (per future slice)
**17F.2 (frontend, Vitest):**
- RED: launcher button hidden when `canAccessCategoryAdmin=false` (agent / feature OFF) → GREEN when true.
- RED: clicking launcher navigates to `settings_inboxes_page_channel` (`sub_page='whatsapp'`) with the account context
  → GREEN.
- RED: launcher renders **no** write control and issues **no** overview mutation → GREEN (read-only preserved).
- Route-guard/capability parity with 17F.1 (reuse `redirectIfCategoryAdminDisabled`).

**17F.3 (backend request specs + Vitest):**
- RED: admin aligns staff → both `TeamMember` and `InboxMember` reflect the users; overview flips `unlinked→linked`
  and drift clears → GREEN.
- RED: agent calls the alignment endpoint(s) → 401 (no mutation) → GREEN.
- RED: feature OFF ⇒ endpoint/inert (404) and assist absent → GREEN.
- RED (if local helper): partial failure (invalid user_ids) rolls back **both** writes (no one-sided drift) → GREEN;
  cross-account user_ids rejected → GREEN.
- RED: no secrets in any response; account isolation preserved → GREEN.

---

## 15. Risks, parked items, explicit non-goals
- **Risks:** (a) tempting scope-creep into a spanning orchestration — mitigated by the thin-launcher decision; (b)
  ambiguity/drift are inherent to convention-only mapping — mitigated by explicit overview surfacing (already shipped);
  (c) round-robin queue callbacks fire on `InboxMember` changes — expected, existing behavior.
- **Parked (owner-approval + ADR required):** any persistent `Inbox↔Team` mapping, data tag, `team_id` on inboxes, join
  table, or automatic membership sync.
- **Explicit non-goals:** new `Category` entity/model/table; replacing Standard/Coexistence setup services; duplicating
  conversations/messages/contacts/channels; agent-accessible inbox/WhatsApp creation; any real Meta/WhatsApp/Shopify
  call; any schema/migration; any production deploy/config change; exposing/logging provider secrets.

---

## 16. Final recommendation
**PROCEED — with the revised scope:** implement **17F.2 as a frontend-only thin launcher** (deep-linking the existing
WhatsApp wizard from a category, capability-gated, no writes, no backend, no schema), and **defer guided
dual-membership to 17F.3** (explicit, reversible, backend-enforced, local-only). This satisfies the intended user
journey, stays entirely within the locked architecture boundaries (no new mapping, no Meta-spanning transaction, no
schema), preserves stock-compatible behavior when the feature is OFF, and keeps every write admin-enforced and
account-isolated. **No blocker.** Implementation remains **not started** pending review.
