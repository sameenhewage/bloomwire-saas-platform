# Bloomwire — S-01 Multiple WhatsApp Inboxes Under One Account (Runtime Report)

> **Status:** Runtime spike / evidence report only. **No** product code, branches, migrations, PRs, or feature
> toggles were created; **no** Chatwoot behavior was modified. **S-02…S-06 not started.** Pricing/billing out of scope.
> **Spike:** S-01 from the decision register (`bloomwire-evidence-review-and-decision-register.md` §3) — unblocks **P-01**.
> **Sources:** [`bloomwire-evidence-collection-report.md`](./bloomwire-evidence-collection-report.md) ·
> [`bloomwire-evidence-review-and-decision-register.md`](./bloomwire-evidence-review-and-decision-register.md) ·
> [`bloomwire-runtime-analysis-and-rCA-report.md`](./bloomwire-runtime-analysis-and-rCA-report.md) ·
> [`bloomwire-s07-live-ui-runtime-smoke-report.md`](./bloomwire-s07-live-ui-runtime-smoke-report.md) ·
> [`bloomwire-feature-toggle-managed-whatsapp-onboarding-plan.md`](./bloomwire-feature-toggle-managed-whatsapp-onboarding-plan.md).

## Proof labels

- **[RUNTIME-PROVEN]** — verified live in the running app (Rails runner against `chatwoot_dev` + browser DOM/API).
- **[CODE-PROVEN]** — verified by reading source.
- **[NOT PROVEN]** — out of S-01 scope (deferred to a later spike).

---

## 1. Goal

Prove whether **one Chatwoot `Account` can hold multiple `Channel::Whatsapp` records + their own `Inbox`es** without
uniqueness collisions, and whether both inboxes are **listed correctly** in the account workspace — **without** making
any real Meta/WABA call. This unblocks **P-01** ("Multiple WA inboxes per account at runtime").

## 2. Setup / environment

| Component | Detail |
|---|---|
| Code baseline | branch `develop` @ `56c98c8` (pure Chatwoot / Feature-OFF baseline) |
| App version | Chatwoot **4.15.1**, Rails **7.1.5.2**, Ruby **3.4.4** (rbenv) |
| Database | PostgreSQL `chatwoot_dev` @ `127.0.0.1:5432` |
| Redis | `127.0.0.1:6379` |
| Rails server | up `127.0.0.1:3000` (pid 67926) |
| Vite dev server | up `127.0.0.1:3036` (pid 68656) |
| Sidekiq worker | not started (not required; no jobs needed to execute) |
| Method of record creation | `bundle exec rails runner` (script via stdin) — **no product code added** |

**Pre-state [RUNTIME-PROVEN]:** `Channel::Whatsapp.count == 0` globally; account 1 had 1 inbox; accounts 1,2,3,4,17 exist.

## 3. Account used

**Existing dev account `#1 "Acme Inc"`** (permitted "existing dev account if safe"). Chosen over a fresh
`S01 Multi WA Runtime Test` account because cleanup is then a precise 2-inbox + 2-channel delete (no account-teardown
FK cascade), and account 1 has a known admin (`john@acme.inc`) for the UI screenshot. Test records were **clearly
named** (`S01 Multi WA Test A/B`) and tagged (`provider_config.source = 's01_runtime_test'`). Account `#2 "Acme Org"`
was used only as the target of the global-uniqueness collision attempt.

## 4. Method

### 4.1 Safety-first callback inspection (before creating anything)

`Channel::Whatsapp` (`app/app/models/channel/whatsapp.rb`) has callbacks that make **real Meta calls** — these were
identified and **deliberately avoided**:

| Callback | External effect | Avoidance |
|---|---|---|
| `validate :validate_provider_config` (`:33`) → `WhatsappCloudService#validate_provider_config?` (`whatsapp_cloud_service.rb:56-59`) | `HTTParty.get(graph.facebook.com/...)` | `insert_all!` skips validations |
| `after_create :sync_templates` (`:35`) → `sync_templates` (`whatsapp_cloud_service.rb:34-39`) | `HTTParty.get(...)` | `insert_all!` skips callbacks |
| `after_commit :setup_webhooks, on: :create` (`:37`) → `WebhookSetupService` | Meta webhook registration | `insert_all!` skips callbacks |
| `before_destroy :teardown_webhooks` (`:36`) → `WebhookTeardownService` (`webhook_teardown_service.rb:16-31`) | `unsubscribe_waba_webhook` (only if `source == 'embedded_signup'`) | cleanup uses `delete_all` (no `before_destroy`) + `source != 'embedded_signup'` |

`Inbox` creation has **no** Meta-calling callbacks (`inbox.rb:80-83`: only internal event dispatch), so inboxes were
created with plain `Inbox.create!`. **Conclusion: a callback-free path exists with no code changes → no blocker.**

### 4.2 Steps (all via `rails runner`)

1. Read-only baseline counts.
2. Create 2 `Channel::Whatsapp` under account 1 via `Channel::Whatsapp.insert_all!` (distinct `phone_number` +
   distinct `provider_config.phone_number_id`, `provider = 'whatsapp_cloud'`, fake `api_key`, `source = 's01_runtime_test'`).
3. Create 2 `Inbox` via `Inbox.create!` linked to those channels.
4. Read back ownership, provider_config independence, Meta-side-effect markers, and the account inbox list.
5. **Collision test:** attempt a duplicate `phone_number` under account 2 → expect a DB unique violation.
6. UI: load the account workspace inbox list (logged in as `john@acme.inc`) + screenshot.
7. Cleanup via `delete_all`; verify DB + API return to baseline.

## 5. Records created

| Record | id | Key fields |
|---|---|---|
| `Channel::Whatsapp` A | **2** | `phone_number = +19990000001`, `provider = whatsapp_cloud`, `provider_config.phone_number_id = 100000000000001`, `business_account_id = WABA_100000000000001`, `source = s01_runtime_test` |
| `Channel::Whatsapp` B | **3** | `phone_number = +19990000002`, `provider = whatsapp_cloud`, `provider_config.phone_number_id = 100000000000002`, `business_account_id = WABA_100000000000002`, `source = s01_runtime_test` |
| `Inbox` A | **9** | `name = "S01 Multi WA Test A"`, `channel_type = Channel::Whatsapp`, `channel_id = 2`, `account_id = 1` |
| `Inbox` B | **10** | `name = "S01 Multi WA Test B"`, `channel_type = Channel::Whatsapp`, `channel_id = 3`, `account_id = 1` |

All temporary; all removed in §10.

## 6. Runtime / UI evidence

**Runner output (create) [RUNTIME-PROVEN]:**

```
BEFORE acct_wa=0 acct_inbox=1 wa_global=0
Q1_TWO_CHANNELS_ONE_ACCOUNT: chA=#2(acct 1) chB=#3(acct 1) same_account=true
Q2_EACH_HAS_INBOX: inbA=#9->Channel::Whatsapp#2 inbB=#10->Channel::Whatsapp#3
Q6_PROVIDER_CONFIG_INDEPENDENT: A.pnid=100000000000001 B.pnid=100000000000002 distinct=true
Q7_NO_META_SIDEEFFECTS: A.templates={} A.templates_synced_at=nil (nil => sync_templates/Meta call did NOT run)
Q3_INBOX_LIST(acct1)=[[1,"Acme Support","Channel::WebWidget"],[9,"S01 Multi WA Test A","Channel::Whatsapp"],[10,"S01 Multi WA Test B","Channel::Whatsapp"]]
AFTER_CREATE acct_wa=2 acct_inbox=3 wa_global=2
Q5_GLOBAL_UNIQUE: ActiveRecord::RecordNotUnique -> PG::UniqueViolation: ERROR: duplicate key value violates unique constraint "index_channel_whatsapp_on_phone_number"
POST_COLLISION wa_global=2 (unchanged => duplicate rejected)
```

**UI evidence [RUNTIME-PROVEN]:** Account workspace → Settings → Inboxes (as `john@acme.inc`, "Acme Inc") showed
**"3 inboxes"**: `Acme Support` (Website) + `S01 Multi WA Test A` (**WhatsApp**, inbox 9) + `S01 Multi WA Test B`
(**WhatsApp**, inbox 10). Screenshot: [`s01-evidence/01-account1-two-whatsapp-inboxes.png`](./s01-evidence/01-account1-two-whatsapp-inboxes.png).

## 7. What is proven [RUNTIME-PROVEN]

1. **One account can hold two `Channel::Whatsapp` records** (ids 2 & 3, both `account_id = 1`; `same_account = true`).
2. **Each WhatsApp channel has its own `Inbox`** (inbox 9 → channel 2; inbox 10 → channel 3) via the 1:1
   `Channelable.has_one :inbox` mapping.
3. **Both inboxes are listed in the account workspace** (DB list query + live UI both show A and B).
4. **No account-scoped uniqueness collision** — two WhatsApp channels coexist under one account with no error.
5. **`phone_number` uniqueness is GLOBAL** — a duplicate `phone_number` inserted under a *different* account (2) was
   rejected with `ActiveRecord::RecordNotUnique` / `PG::UniqueViolation` on `index_channel_whatsapp_on_phone_number`
   (not scoped to `account_id`). **[also CODE-PROVEN]** by the unique index in `channel/whatsapp.rb:16-17`.
6. **`phone_number_id` values are stored independently** in each channel's `provider_config` jsonb (`…0001` vs `…0002`).
7. **No external/Meta call was triggered** by creation (see §9).

## 8. What is NOT proven (out of S-01 scope)

- **Inbound message routing to the correct inbox** for two different `phone_number_id`s — that is **S-02**. S-01
  proves creation/listing/uniqueness, not live inbound delivery. **[NOT PROVEN — S-02]**
- **The real product creation paths** (manual `POST /inboxes` and embedded `POST /whatsapp/authorization`), which
  invoke the Meta-calling callbacks, were **intentionally not exercised** (no real credentials; safety). Their
  contracts remain **[CODE-PROVEN / RUNTIME-PROVEN in S-07]** only. **[NOT PROVEN here — by design]**
- **Auto webhook setup** (`after_commit :setup_webhooks`) behavior — bypassed by `insert_all!`. **[NOT PROVEN — S-03]**

## 9. External-call safety check

- **Creation:** `Channel::Whatsapp.insert_all!` is a single SQL `INSERT` that **bypasses all validations and
  callbacks**, so `validate_provider_config?`, `sync_templates`, and `setup_webhooks` (the three Meta-calling paths)
  **did not run**. Concrete proof: created channel A had `message_templates == {}` and `message_templates_last_updated
  == nil` — i.e., `sync_templates` (a `HTTParty.get` to Meta) **never executed**. **[RUNTIME-PROVEN]**
- **Inbox creation:** `Inbox.create!` has no Meta-calling callbacks (`inbox.rb`). **[CODE-PROVEN]**
- **Cleanup:** `delete_all` bypasses `before_destroy :teardown_webhooks`; additionally `source = 's01_runtime_test'`
  (≠ `embedded_signup`) means `WebhookTeardownService#should_teardown_webhook?` would be `false` anyway. **No Meta call.**
- **Note (Sidekiq):** the runner initialized a Sidekiq *client* (Redis) to enqueue an internal inbox-created event;
  this is **not** an external/Meta call and no worker processed it.

## 10. Cleanup result [RUNTIME-PROVEN]

```
TO_DELETE inboxes=[9, 10] channels=[2, 3]
DELETED inboxes=2 channels=2 (delete_all => no before_destroy/teardown_webhooks => no Meta call)
AFTER_CLEANUP acct_wa=0 acct_inbox=1 wa_global=0
RESIDUE wa_test=0 inbox_test=0
```

- DB returned to the **exact pre-state** (account 1 = 1 inbox; `Channel::Whatsapp.count = 0`; zero residue).
- **Authoritative API confirmation:** `GET /api/v1/accounts/1/inboxes` → **1 inbox** (`Acme Support`, `Channel::WebWidget`).
- **Client-cache caveat (expected):** the SPA briefly still rendered "3 inboxes" after cleanup because `delete_all`
  bypasses the `AccountCacheRevalidator` callback (`inbox.rb:46`), so the account cache key was not bumped and the
  workspace served its cached inbox list. The **DB and API are the source of truth and are clean**; this is a
  client-cache artifact of the raw-SQL cleanup, not a data-integrity issue.
- **No product code changed.** Only this report, the screenshot under `docs/research/s01-evidence/`, and throwaway
  runner scripts (piped via stdin, nothing written to the repo) were used.

## 11. Decision impact on P-01

**P-01 — "Multiple WA inboxes per account at runtime" → CONFIRMED** for its core dimensions: an account can hold
multiple WhatsApp channels + inboxes, with **no collision**, **global** `phone_number` uniqueness, **independent**
`phone_number_id` storage, and **correct listing** in the workspace UI. This satisfies the create/list/uniqueness
portion of the register's S-01 pass criteria. The remaining S-01 pass criterion — *inbound messages land in the
correct inbox* — is the **routing** concern owned by **S-02** and is **not** claimed here.

**Plan impact:** validates the feasibility assumptions behind the routing-registry (§6) and multi-number tenant model
in the feature-toggle plan; the registry's per-`phone_number_id` resolution rests on exactly this multi-inbox-per-
account capability, now runtime-proven.

## 12. Recommended next step

**S-02 — Multi-WABA webhook routing** (POST sample `whatsapp_business_account` webhooks for two distinct
`phone_number_id`s and confirm each lands in the correct account/inbox with no cross-tenant leakage). It is the direct
follow-on: S-01 proved the inboxes can **exist** and **list**; S-02 proves inbound events **route** to the right one —
the pivotal proof for the global webhook/router (plan §7) and the routing registry (plan §6).

**Stop after S-01.** S-02 is **not** started in this report.
