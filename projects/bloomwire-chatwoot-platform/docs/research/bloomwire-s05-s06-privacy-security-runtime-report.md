# Bloomwire — S-05 / S-06 Privacy + Security Runtime Inventory (Report)

> **Status:** Runtime spike / evidence report only (Sub-agent B of the parallel orchestration). **No** product code,
> branches, migrations, PRs, feature toggles; **no** Chatwoot behavior modified. Pricing/billing out of scope.
> **Spikes:** S-05 (impersonation/privacy) + S-06 (token/log/job-arg/DTO leakage) — inform **P-05**.
> **Isolation:** all temporary records used the `S05S06` prefix; this workstream did **not** touch any `S02` records.
> **Sources:** evidence-collection-report · evidence-review-and-decision-register · runtime-analysis-and-rCA-report ·
> s07-live-ui-runtime-smoke-report · feature-toggle-managed-whatsapp-onboarding-plan.

## Proof labels
- **[RUNTIME-PROVEN]** — verified live (Rails runner against `chatwoot_dev`).
- **[CODE-PROVEN]** — verified by reading source.

---

## 1. Goal

Measure the real privacy/security risk surface around SuperAdmin access, impersonation, self-add, audit trail, token
logging, message-body logging, Sidekiq job args, and `provider_config` exposure — using fake tokens/data only and a
disposable `S05S06` test user, with full cleanup.

## 2. Setup / environment

- `develop` @ `56c98c8`, Chatwoot 4.15.1, Rails 7.1.5.2, `chatwoot_dev`, Redis up; Sidekiq worker not running.
- **Important env signal:** `ChatwootApp.enterprise?` returned **falsy/nil** at runtime → this dev stack runs in
  **CE mode** (`DISABLE_ENTERPRISE` effectively set). This matches the Bloomwire CE target (prior ADR 0002) and is
  central to the audit finding below. **[RUNTIME-PROVEN]**
- Method: `bundle exec rails runner` (script via stdin) — **no product code added**. Temp user/membership created and
  removed inside a `begin/ensure`.

## 3. Raw runner evidence [RUNTIME-PROVEN]

```
=== S-05 PRIVACY ===
ENTERPRISE?=                                  # ChatwootApp.enterprise? => nil (CE mode)
SUPERADMIN_MODEL=exists count=2 emails=["sameen.android@gmail.com", "john@acme.inc"]
S05_1 sameen type="SuperAdmin" account_memberships=0 (0 => SuperAdmin NOT auto account admin)
ACCT1 conversations=1 inboxes=1 members_before=2
S05_2 self_add: AccountUser#15 user#15 role=administrator admin?=true permissions=["administrator"]
S05_4_5 admin_member account_conversations=1 show?(conv#1)=true (true => can read tenant conversation)
S05_3 impersonation: link_generated=true token_present=true marked_impersonation=true
S05_8 audit_class=Enterprise::AuditLog table_total=0 writes_for_temp_account_user=0
S05_6 impersonation_audit_rows=0
S05_7 reads_audited=false (audit_before_read=0 after=0)
S05_8b acct1.feature_enabled?(:audit_logs)=false
=== S-06 LOGGING/DTO ===
FILTER_PARAMS=[:password, :secret, :_key, :auth, :crypt, :salt, :certificate, :otp, :access, :private,
  :protected, :ssn, :otp_secret, :otp_code, :backup_code, :mfa_token, :otp_backup_codes,
  /\A(?!.*\bwebsite_token\b).*token/i, "user.otp_secret", "user.otp_backup_codes"]
S06_4 filtered={"api_key"=>"[FILTERED]", "access_token"=>"[FILTERED]", "app_secret"=>"[FILTERED]",
  "password"=>"[FILTERED]", "webhook_verify_token"=>"[FILTERED]", "phone_number_id"=>"PNID",
  "content"=>"MSG BODY", "body"=>"RAW BODY", "text"=>{"body"=>"NESTED BODY"},
  "provider_config"=>{"api_key"=>"[FILTERED]", "business_account_id"=>"WABA"}}
S06_3 job=Webhooks::WhatsappEventsJob message_body_present_in_job_args=true
S06_5 provider_config_after_filter={"api_key"=>"[FILTERED]", "business_account_id"=>"WABA"} (DTO exposes full provider_config to admins)
CLEANUP temp_user#15: residual_user=0 residual_membership=0
CLEANUP audit_rows_purged=0 (id>0)
BASELINE acct1_members_after=2 (was 2)
```

## 4. S-05 verification matrix

| # | Question | Answer | Evidence |
|---|---|---|---|
| 1 | Is a SuperAdmin automatically an Account Administrator? | **No** | `sameen type="SuperAdmin" account_memberships=0` |
| 2 | Can a SuperAdmin self-add as `AccountUser`? | **Yes** | created `AccountUser#15` `role=administrator admin?=true` ([CODE-PROVEN] entry point `super_admin/account_users_controller.rb:12-18`) |
| 3 | Can a SuperAdmin impersonate a tenant user? | **Yes** | `generate_sso_link_with_impersonation` → token `marked_impersonation=true` (`sso_authenticatable.rb:27-31`) |
| 4 | After impersonation, what becomes visible? | **The impersonated member's full account workspace** | login becomes that user; for an admin member, all account data |
| 5 | Can conversations/messages be read? | **Yes** | admin-member `ConversationPolicy#show?(conv#1)=true` (`conversation_policy.rb:10-12,20-22`) |
| 6 | Server-side audit record for impersonation? | **No** | `impersonation_audit_rows=0`; impersonation only sets a Redis token + a FE `sessionStorage` flag — no audit write |
| 7 | Audit record for message/conversation reads? | **No** | `reads_audited=false` (audit count 0→0 across reads) |
| 8 | Is audit logging CE-safe or enterprise/premium-gated? | **Enterprise-gated AND inert in CE** | `ChatwootApp.enterprise?` falsy → `Enterprise::Audit::*` concerns not mixed in → **0** audit rows even for an audited model (`writes_for_temp_account_user=0`, `table_total=0`); viewing also premium-gated (`feature_enabled?(:audit_logs)=false`) |

**S-05 conclusion:** A platform SuperAdmin can reach any tenant's conversations/messages via **self-add** *or*
**impersonation**, and in CE mode there is **no audit trail whatsoever** (not for impersonation, self-add, or reads).
Audit logging **cannot** be relied on as the Bloomwire CE privacy control.

## 5. S-06 verification matrix

| # | Question | Answer | Evidence |
|---|---|---|---|
| 1 | Are WhatsApp/FB access tokens logged by explicit logger calls? | **Yes** | [CODE-PROVEN] `callbacks_controller.rb:25-30` logs raw `user_access_token`/`page_access_token` (debug); these bypass param-filtering (string interpolation) |
| 2 | Are provider error response bodies logged? | **Yes** | [CODE-PROVEN] `base_service.rb:44-45` `Rails.logger.error response.body` (full Meta response on send error) |
| 3 | Are webhook payload message bodies in Sidekiq job args? | **Yes** | `message_body_present_in_job_args=true` for `Webhooks::WhatsappEventsJob`; controller enqueues `params.to_unsafe_hash` (`whatsapp_controller.rb:13`) — args persist in Redis/Sidekiq UI |
| 4 | Are message bodies scrubbed by Rails filter parameters? | **No** | `content`, `body`, `text.body` all returned **cleartext**; only token/secret/key-named params are `[FILTERED]` |
| 5 | Are `provider_config` secrets exposed to account workspace APIs/DTOs? | **Yes** | [CODE-PROVEN] `_inbox.json.jbuilder:130-138` sends raw `provider_config` (incl. `api_key`, `business_account_id`, `phone_number_id`, `webhook_verify_token`) to any account **administrator** |
| 6 | Which fields must be masked/scrubbed for Bloomwire mode? | see §7 | — |

**Note on the filter test:** the `ParameterFilter` redacts `api_key`/`access_token`/`app_secret`/`password`/
`webhook_verify_token` (and nested `provider_config.api_key`) **by key name**, but leaves `phone_number_id`,
`business_account_id`, and **all message-body fields** in cleartext. Crucially, that filter only applies to Rails'
auto request-param logging — **not** to explicit `Rails.logger` calls, Sidekiq job args, or API DTOs.

## 6. What is proven vs not

**Proven [RUNTIME-PROVEN]:** self-add grants admin membership; impersonation token generation + marking; admin member
reads tenant conversations; zero audit writes in CE mode (impersonation, self-add, reads all unaudited);
`audit_logs` premium feature off; message bodies unscrubbed by param filter; message body present in job args; (with
[CODE-PROVEN]) token/error-body logging and DTO `provider_config` exposure.

**Not proven / not done (by design):** did not perform a full browser impersonation login session (mechanism proven at
model level); did not exercise the live `callbacks_controller` debug log or `base_service` error log at runtime (both
[CODE-PROVEN]); did not enqueue a real job to Sidekiq (used serialization to avoid residue).

## 7. Privacy hardening insertion points (S-05.9 + S-06.6)

| Risk | Insertion point | Bloomwire hardening |
|---|---|---|
| Impersonation unaudited / unrestricted | `sso_authenticatable.rb:27-31` + super-admin impersonate action | Gate/disable impersonation; **Bloomwire-owned audit** of every impersonation start/stop |
| SuperAdmin self-add | `super_admin/account_users_controller.rb:12-18` | Restrict + audit account self-add |
| No CE audit trail | (enterprise audit inert in CE) | Build a **Bloomwire CE audit** for support access + cross-tenant reads (do **not** depend on `Enterprise::AuditLog`/`audit_logs` premium) |
| `provider_config` in DTO | `_inbox.json.jbuilder:130-138` | Scrub `provider_config` from managed-tenant inbox DTO (never send `api_key`/tokens to tenant admins) |
| App Secret unmasked | super-admin WhatsApp Embedded form (S-07) | `type=password` + never echo stored secret |
| Tokens in explicit logs | `callbacks_controller.rb:25-30`, `base_service.rb:44-45` | Remove/scrub token + full-response-body logging |
| Message bodies in logs/job args | `whatsapp_controller.rb:13` (enqueues full payload); param filter gap | Redact message bodies in logs; keep the Sidekiq handoff **non-mutating** — the stock `WhatsappEventsJob` reads `text.body` via `IncomingMessageServiceHelpers#message_content` to set `Message#content`, so do **not** strip/minimize job args. Use a Sidekiq log/display redactor (worker still gets the full payload), encrypted job args (decrypted in-worker), or an encrypted out-of-band payload + minimal reference (final plan §11) |

**Fields to mask/scrub for Bloomwire mode:** message bodies (`content`, `body`, `text.body`, message text), full
inbound webhook payload in Sidekiq args, FB/WA access tokens in explicit logs, provider error response bodies,
contact PII (`wa_id`/phone, `display_phone_number`), routing identifiers where unnecessary (`phone_number_id`,
`business_account_id`), and the inbox DTO `provider_config`. (Token/secret/`*_key` params are already redacted in
Rails request-param logs but **not** elsewhere.) **Sidekiq-args items are redacted at the log/display layer or via
encryption — never by mutating the payload the worker consumes (final plan §11).**

## 8. Cleanup result [RUNTIME-PROVEN]

`temp_user#15` + its `AccountUser` membership removed (`residual_user=0 residual_membership=0`); audit residue purged
(`audit_rows_purged=0` — none were written); **account 1 membership restored `2 → 2`**. No `S02` records touched. No
product code changed (only this report + a throwaway runner piped via stdin).

## 9. Decision impact on P-05

**P-05 — "Platform admins prevented from reading tenant content" → CONFIRMED AS A REAL, OPEN RISK.** Both bypass
paths (self-add + impersonation) work, and in CE mode there is **no audit trail at all**. The feature-toggle plan's
privacy-hardening workstream (plan §8) is **required**, must include a **Bloomwire-owned CE audit**, and must redact
message bodies/tokens at the log/display layer and scrub the inbox DTO — **without mutating** the Sidekiq payload the
WhatsApp job consumes (non-mutating redaction / encrypted args / encrypted out-of-band handoff; final plan §11).

## 10. Recommended next step

Privacy hardening is a **design+implementation** workstream (not a further measurement spike); S-05/S-06 have produced
the decision-grade inventory needed. The next *runtime* gate in sequence is **S-03 (global webhook front-door)** and
**S-04 (outgoing injection)** — **not started** (per instructions).
