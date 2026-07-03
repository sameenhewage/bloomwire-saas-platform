# Phase 17E.0 — Multiple WhatsApp Inbox per Account Discovery

Status: **PR PRNUM_PLACEHOLDER — open, non-draft, ready for review (NOT merged); head `HEADSHA_PLACEHOLDER`.** Docs-only discovery + ADR — no code, no route, no frontend, no migration, no production, no real Meta/WhatsApp calls. Locks the Bloomwire **multiple WhatsApp inbox per account** business model and its guardrails **before** the 17E hardening slices.

Base: `version_1` @ `ea305792dc83f864f8e1374ce0ca832f99f7d8f9` (after Phase 17D.3 / PR #111 merged — Coexistence frontend enabled).

Companion ADR: [`projects/bloomwire-chatwoot-platform/docs/adr/0009-multi-whatsapp-inbox-category-model.md`](../../projects/bloomwire-chatwoot-platform/docs/adr/0009-multi-whatsapp-inbox-category-model.md).

---

## A. Executive verdict

**SUPPORTED.** One Bloomwire/Chatwoot account can already own **multiple WhatsApp inboxes/numbers** today, with **no code change required** to the create path, routing, or the team/assignment model. The Bloomwire feature toggle / channel-control work did **not** remove or block this: the WhatsApp "Add Inbox" card is gated only by **role + managed mode**, never by "how many WhatsApp inboxes already exist," so it never disappears after the first. The managed embedded-signup services create a **new `Channel::Whatsapp` + `Inbox` + `Bloomwire::WhatsappSetup` on every call** and reject only a **duplicate phone number / `phone_number_id`** (which are globally unique — the correct routing key). The global webhook router resolves inbound strictly by `phone_number_id → exactly one setup → that setup's own inbox`, fail-closed. The "Category = Team + Inbox + 10 agents" model maps cleanly onto **native** Chatwoot primitives.

This phase is **evidence/report only**. It does not add endpoints, tests, routes, migrations, credentials, deploys, or Meta calls. It records the two hardening caveats (contacts visibility; missing multi-inbox tests) and the phased plan (17E.1 → 17E.2 → 17E.3).

---

## B. Business requirement

A single business (one Chatwoot **Account** / tenant) runs several **categories/departments**, each with its own WhatsApp number and its own staff:

| Category | WhatsApp number | Team | Agents |
|---|---|---|---|
| Category 1 | WhatsAppNumber_1 | Team 1 | 10 |
| Category 2 | WhatsAppNumber_2 | Team 2 | 10 |
| Category 3 | WhatsAppNumber_3 | Team 3 | 10 |
| Category 4 | WhatsAppNumber_4 | Team 4 | 10 |
| Category 5 | WhatsAppNumber_5 | Team 5 | 10 |

- **Admin / main agent** can view, manage, and assign conversations across **all** categories.
- **Category agents** should ideally see only **their own** category/inbox conversations.
- Total ≈ 50 employees across 5 categories.

We are **not rebuilding WhatsWay** inside Chatwoot. We customize Chatwoot for Bloomwire using **native primitives only**.

---

## C. Supported model (mapping)

| Bloomwire business concept | Chatwoot primitive |
|---|---|
| Business / tenant | **Account** |
| Category / department | **Team** + **Inbox** (one each, paired) |
| Category WhatsApp number | **`Channel::Whatsapp`** + **`Inbox`** + **`Bloomwire::WhatsappSetup`** (`phone_number_id` mapping) |
| Employee | **User** / **AccountUser** (role `agent`) |
| Admin / main agent | **AccountUser** (role `administrator`) |
| Category staff (10) | **TeamMember**s + **InboxMember**s (the same 10 users on both) |
| Customer message thread | **Conversation** |
| Assignment to a person | `conversation.assignee_id` |
| Assignment to a category | `conversation.team_id` |
| Visibility / access | Chatwoot **policies** + inbox membership (backend-scoped) |

---

## D. Multiple inbox support — evidence summary

Every call to the managed signup service creates a **new** channel + inbox and blocks only a duplicate number:

- `app/app/services/bloomwire/whatsapp_embedded_signup_service.rb` — `#persist` (lines 80–101): returns `:phone_number_taken` **only** when a `Channel::Whatsapp` with that `phone_number` already exists (line 82); otherwise creates a new channel shell (`#create_channel_shell`, 106–119), a new `Inbox` (`#create_inbox`, 121–123), and a new setup mapping (`#create_mapping`, 129–138). No "account already has WhatsApp" check anywhere.
- **No per-account WhatsApp uniqueness** in the schema (`app/db/schema.rb`):
  - `channel_whatsapp`: `index_channel_whatsapp_on_phone_number … unique` (line 727) — **global** per-number, `account_id` is **not** unique → an account may own many WhatsApp channels. (Mirrored by the model validation `validates :phone_number, presence: true, uniqueness: true` — `app/app/models/channel/whatsapp.rb:40`.)
  - `bloomwire_whatsapp_setups`: `…_on_account_id` is a **plain, non-unique** index (line 376); `…_on_channel_whatsapp_id` unique (one setup per channel, line 377); `…_on_phone_number_id` unique **partial** `where phone_number_id IS NOT NULL` (line 379) — **global** per-number-id.
  - `contact_inboxes`: `…_on_inbox_id_and_source_id` unique (line 755) → a customer can exist across several of the tenant's inboxes.
- The only uniqueness is **global** on `phone_number` / `phone_number_id` — exactly what routing correctness requires (one Meta line → one inbox), **not** a per-account cap.

**Conclusion:** multiple WhatsApp inboxes per account are supported by construction; there is no blocker.

---

## E. Bloomwire feature toggle impact — summary

- The controlling guard is `canSelfServeManagedWhatsapp` = **administrator AND** (`restrict_native_whatsapp_setup?` **AND** `Bloomwire::Features.enabled?(:managed_whatsapp_onboarding)`) — `app/lib/bloomwire/capabilities.rb:39-41`. Agents → always `false`.
- It is a **role + managed-mode** guard, **not** a count-based one. `ChannelList.vue#isChannelSetupAllowed` (`app/app/javascript/dashboard/routes/dashboard/settings/inbox/ChannelList.vue:123-137`) shows the WhatsApp card whenever `canSelfServeManagedWhatsapp` is true — so the card **stays visible after the 1st, 2nd, … inbox**. `ChannelFactory.vue` (44–80) routes it to the managed wizard the same way each time.
- **The toggle did not block multi-inbox.** Agents remain correctly blocked (card hidden; the endpoints are admin-only + 404 unless managed). Side effect (not a blocker): in managed mode every *other* Add-Inbox card is hidden, so the Add-Inbox screen shows **only** the WhatsApp card.

---

## F. Standard / Coexistence endpoint behavior — summary

- **Standard** `POST /api/v1/accounts/:account_id/bloomwire/whatsapp/embedded_signup` — supports multiple numbers: **YES**. Callable repeatedly; each distinct number → new channel + inbox + setup. Controller (`…/bloomwire/whatsapp/embedded_signups_controller.rb`) has no per-account block.
- **Coexistence** `POST /api/v1/accounts/:account_id/bloomwire/whatsapp/coexistence_embedded_signup` — supports multiple numbers: **YES**. `Bloomwire::WhatsappCoexistenceEmbeddedSignupService` (`…/whatsapp_coexistence_embedded_signup_service.rb:13-41`) inherits `#persist` unchanged, overriding only `#create_channel_shell` (adds `connection_mode: 'coexistence'`) and `#dto_for`.
- **Duplicate `phone_number` / `phone_number_id`** stays globally blocked → HTTP 422 `:phone_number_taken` ("This WhatsApp phone number is already connected."), via a pre-check plus a DB-unique `ActiveRecord::RecordNotUnique` rescue (service lines 82, 99–100), and `:phone_number_id_conflict` when a *different* channel already claims a `phone_number_id` (`app/app/services/bloomwire/whatsapp_setup_creator.rb:110-116`).
- **Neither overwrites nor blocks on prior WhatsApp inboxes.** The setup mapping is idempotent per `channel_whatsapp_id` (`find_or_initialize_by`, setup creator line 46). Duplicate protection is correct: keyed on the true identity of a WhatsApp line.

---

## G. Routing behavior — summary

- `Bloomwire::Webhooks::WhatsappRouter.resolve` (`app/app/services/bloomwire/webhooks/whatsapp_router.rb:17-28`) reads `metadata.phone_number_id` from the payload, finds the **single** `ready_for_webhook` setup for it (`matches.one?`), and returns that setup's own `inbox_id` / `channel_whatsapp_id`. `#resolve_handoff_safe_setup` + `#channel_aligned_with_payload?` (35–52) additionally require the channel's `provider_config['phone_number_id']` and `phone_number` to match the payload.
- **Same account, many numbers:** each number has its own globally-unique `phone_number_id` → its own setup row → Number-1 → Inbox-1, Number-2 → Inbox-2. No cross-talk is possible because the lookup key is unique.
- **Wrong / unknown `phone_number_id` fails closed:** no match → `matches.one?` false → returns `nil`.

---

## H. Team / category assignment behavior — summary

Native Chatwoot already supports the whole "Category = Team + Inbox, 10 agents" model:

- **Team** belongs to account, has members through team_members (`app/app/models/team.rb:21-24`); **InboxMember** join (`app/app/models/inbox.rb:66-67`, `app/app/models/inbox_member.rb:25-36`, which also enqueues the round-robin queue); **Conversation** has `assignee_id` and `team_id` (`app/app/models/conversation.rb:103-109`).
- **Per-inbox round-robin** auto-assignment to inbox members; **team-filtered** assignment so only category agents get category conversations — `app/app/services/auto_assignment/assignment_service.rb#filter_agents_by_team` (59–67) and `app/app/models/concerns/assignment_handler.rb#ensure_assignee_is_from_team` (12–28).
- Admin can manually assign to any assignable agent (inbox members + admins). Inbox cap is effectively unlimited (100k — `app/app/models/account.rb:149-154`, `app/lib/chatwoot_app.rb:10-12`).
- **Thin, optional customization** only: (a) a convenience step that pairs each new WhatsApp inbox with a Team and copies the same members onto both; (b) optionally auto-setting `conversation.team_id` for a WhatsApp inbox. Neither is required for correctness — inbox membership alone already isolates conversations.

---

## I. Permission / visibility model

- **Admin:** sees **all** inboxes & conversations — `app/app/models/user.rb#assigned_inboxes` (admin → `Current.account.inboxes`, lines 138–140); `Conversations::PermissionFilterService#perform` returns all for administrators (`app/app/services/conversations/permission_filter_service.rb:10-14`).
- **Agent (conversations & inboxes):** **isolated at the backend SQL layer** — `InboxPolicy::Scope#resolve → user.assigned_inboxes`; `ConversationFinder#set_inboxes` restricts to `assigned_inboxes` (`app/app/finders/conversation_finder.rb:91-97`); `PermissionFilterService#accessible_conversations` = `where(inbox: user.inboxes…)` (lines 18–20); `ConversationPolicy#inbox_access?` (`app/app/policies/conversation_policy.rb:28-30`). A Category-1 agent **cannot** list or open Category-2 conversations. This is enforced server-side, not frontend-only.
- **No Bloomwire override** weakens these scopes; the Bloomwire capability layer governs *creation/deletion*, not *visibility*.

---

## J. Contacts visibility caveat (stock Chatwoot — the one real isolation gap)

The **contacts index / search / filter is account-wide, not inbox-scoped**:

- `app/app/controllers/api/v1/accounts/contacts_controller.rb#index → #resolved_contacts` and `app/app/services/contacts/filter_service.rb#base_relation` apply **no** inbox filter; `app/app/policies/contact_policy.rb#index?` returns `true`.
- Effect: a Category-1 agent can **enumerate** name/email/phone of contacts who only ever messaged Category-2. The **conversations** under those contacts remain hidden (the contacts→conversations endpoint uses `PermissionFilterService`), so this is **contact-record** leakage, not conversation leakage.
- This is **stock Chatwoot behavior** (contacts are account-global), **not** caused by Bloomwire. Whether to close it is a **product decision** for Phase 17E.2 (accept vs. add an inbox-scoped contacts finder/policy).

---

## K. Missing tests caveat

There is **no** automated coverage for the multi-inbox-per-account path:

- No test creates 2+ WhatsApp inboxes for one account, calls either signup endpoint twice with different `phone_number_id`, or routes two numbers **in the same account** to two inboxes.
- No test asserts a Category-1 agent cannot see Category-2 conversations/contacts.
- Existing coverage proves only: single-inbox signup; **global** `phone_number_id` uniqueness (`app/spec/models/bloomwire/whatsapp_setup_spec.rb` "rejects a duplicate phone_number_id"); cross-channel pnid conflict (`app/spec/services/bloomwire/whatsapp_setup_creator_spec.rb` "fails closed when the phone_number_id is already claimed by a different channel"); multi-**account** routing (`app/spec/services/bloomwire/webhooks/whatsapp_router_spec.rb` "is account-scoped …"). The intended multi-inbox-same-account scenario is **untested**. Phase 17E.1 turns today's implicit support into a guaranteed, regression-locked contract.

---

## L. Recommended next phases

```text
17E.1 backend contract tests  →  17E.2 UI / permission / contact-isolation polish  →  17E.3 runtime E2E (owner-operated, mocked Meta)
```

- **17E.1 — Multiple-inbox backend contract tests (RED→GREEN; no product change expected).** Request specs calling Standard **and** Coexistence twice per account with different `phone_number_id` → two inboxes/channels/setups; duplicate number → 422; router spec: two numbers in **one** account → two inboxes; wrong pnid → nil; agent-A(inbox-1) cannot read inbox-2 conversations.
- **17E.2 — UI / permission polish + contacts decision.** Wizard: show connected numbers + a clear "Connect another number"; optional "attach to Category/Team + copy members" step. **Decide & (if chosen) implement contact isolation** (inbox-scoped contacts finder/policy) with tests. Preserve all native guards.
- **17E.3 — Runtime E2E (owner-operated, mocked Meta, no real calls).** In a running managed-mode instance: add 2 WhatsApp inboxes; create 2 teams + 2 sets of agents; simulate inbound per `phone_number_id` → verify correct inbox + category-only visibility + admin-sees-all + the 17E.2 contacts decision.

---

## M. Guardrails / non-goals (all 17E work)

- **Do not rebuild WhatsWay** — use Account / Inbox / Team / InboxMember / TeamMember / Conversation / `assignee_id` / `team_id` / policies.
- **Do not duplicate the chat/message source of truth** — Chatwoot conversations/messages remain authoritative.
- **Do not bypass Chatwoot inbox/conversation primitives** (no custom routing tables beyond the existing non-secret `Bloomwire::WhatsappSetup` mapping).
- **Do not weaken global webhook routing** (ADR-0005) or native `/whatsapp/authorization` / `Whatsapp.vue`; keep the global-router-only, app-to-WABA-subscribe boundary.
- **Do not weaken native security** — keep `InboxPolicy` / `ConversationPolicy` / `PermissionFilterService` scoping; only *add* scoping (contacts) if chosen.
- **Do not expose secrets** — tokens stay in encrypted `provider_config` (ADR-0006); safe DTOs only.
- **Keep the global-unique `phone_number` / `phone_number_id`** constraint (do not relax to per-account).
- **No deploy · no production · no migrations · no real Meta/WhatsApp calls.** Dev remains `9b09f9e` until an explicit deploy.

---

## N. Open questions before 17E.1

1. **Contacts isolation:** accept account-wide contact visibility (stock) or scope contacts to an agent's inboxes? (Drives whether 17E.2 ships a contacts finder/policy.)
2. **Category ↔ Team/Inbox pairing:** do we add a convenience "create category" flow (inbox + team + shared members in one step), or keep them separate native steps for now?
3. **Auto `team_id` on WhatsApp conversations:** set automatically per inbox, or leave assignment to inbox-member round-robin (already isolated)?
4. **Reports/search surfaces:** confirm agent-facing reports/overview/search do not aggregate cross-inbox data (audit in 17E.2).
5. **Go-live gate:** which of the 5 numbers/categories is the first owner-operated runtime E2E target (17E.3)?
