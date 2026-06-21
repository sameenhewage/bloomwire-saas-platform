# ADR 0002 — Bloomwire Enterprise Boundary & ChatwootHub Telemetry

- **Status:** Accepted (decision) — **implementation parked / future**
- **Date:** 2026-06-21
- **Supersedes / extends:** ADR 0001 (Technical Baseline), specifically its rule
  "No Chatwoot Enterprise dependency."
- **Scope:** documentation-only. **No code, configuration, migration, schema,
  spec, or runtime behavior is changed by this ADR.** It records a decision and a
  set of parked future tasks.

## Context

A focused source-code audit of the vendored Chatwoot build (`app/`) established:

- The build is **Chatwoot `4.15.1`** (`app/package.json`), MIT core plus an
  **Enterprise overlay** under `app/enterprise/`.
- **Twilio Voice** and **WhatsApp Business Calling** are implemented, but the
  backend lives **entirely under `app/enterprise/`** and is gated by the
  **`channel_voice`** premium feature flag (`app/config/features.yml`,
  `premium: true`, `enabled: false`). Routes mount only `if ChatwootApp.enterprise?`.
- The `app/enterprise/LICENSE` is the **Chatwoot Enterprise License**: the
  Enterprise code "may only be used **in production** if you … have a valid
  Chatwoot Enterprise License / subscription." Development/testing is permitted
  without a subscription; **production use without a subscription is forbidden.**
- The self-hosted app communicates with **one external Chatwoot service**,
  `https://hub.2.chatwoot.com` (`app/lib/chatwoot_hub.rb`), via a **daily,
  production-only** job (`Internal::CheckNewVersionsJob`, cron `0 0 * * *`):
  - `POST /ping` (`sync_with_hub`) sends installation identity (UUID, version,
    host, env, edition) **plus aggregate counts** (accounts/users/inboxes/
    conversations/message counts) unless `DISABLE_TELEMETRY` is set.
  - The Enterprise override of that job **writes `INSTALLATION_PRICING_PLAN`
    from the Hub response** (locked) and runs premium config/feature reconcile.
  - `DISABLE_TELEMETRY` only strips the aggregate metrics block and `emit_event`;
    it does **not** stop the `/ping` itself, the identity payload, or the plan
    sync.
  - **No per-account feature flags and no `channel_voice` state are sent
    outbound** (not proven to be transmitted anywhere in the code).

Bloomwire is a **commercial SaaS product** built on Chatwoot **Community
Edition**. We need an explicit, durable boundary so the SaaS layer never acquires
an accidental dependency on Enterprise code, and so production outbound
communication is minimized for privacy and tenant isolation.

## Decision

### 1. Chatwoot CE / OSS remains the source of truth

Chatwoot Community Edition stays the operational source of truth for the core
support workflow. Bloomwire reads it live and references it by identifier; it
never forks or duplicates it. Chatwoot owns:

- `accounts`, `inboxes`, `contacts`, `conversations`, `messages`, `labels`,
  `teams`, and the **normal support workflow**.

### 2. No Chatwoot Enterprise calling code in production without a license

Bloomwire **must not use Chatwoot Enterprise calling code in production unless
Bloomwire (or the operator) holds a valid Chatwoot Enterprise subscription** for
the correct number of seats. This is a hard licensing constraint from
`app/enterprise/LICENSE`, not a Bloomwire preference.

### 3. No dependency on the Enterprise calling surface

Bloomwire code **must not depend on, import, call, or extend** any of:

- `app/enterprise/` **voice controllers** (e.g. `Twilio::VoiceController`),
- `app/enterprise/` **WhatsApp calling services** (e.g. `Whatsapp::CallService`,
  `Voice::*` services),
- the **Enterprise `Call` model** (`app/enterprise/app/models/call.rb`),
- the **`calls` table treated as Enterprise-owned runtime state**,
- the **`channel_voice`** feature flag,
- any **Chatwoot Enterprise routes / services / controllers**.

### 4. Any future calling feature must be Bloomwire-owned (clean-room)

If voice / WhatsApp calling becomes required, it is built **independently** using
public provider documentation only:

- **public Twilio Voice APIs / SDKs**,
- **public Meta WhatsApp Cloud Calling APIs**,
- **Bloomwire-owned services / controllers / tables** (`bloomwire_` prefix,
  Bloomwire-owned credentials),
- **no copied Enterprise implementation logic** (do not use Enterprise files as a
  template),
- **optional OSS-safe Chatwoot timeline note/activity only** — e.g. add an
  `activity` / note message through the **public OSS messages API**; never write
  to the Enterprise `calls` table or emit the Enterprise `voice_call.*` events.

### 5. ChatwootHub telemetry decision (privacy / security / SaaS isolation)

We **may disable or remove ChatwootHub outbound communication** for **privacy,
security, SaaS isolation, and customer-data protection** reasons.

- This is **not** a licensing bypass.
- This does **not** permit use of Enterprise features.
- **Enterprise features still require a valid Chatwoot Enterprise
  subscription / license** regardless of telemetry configuration.

### 6. Security requirement — minimize production outbound calls

As a hard Bloomwire security requirement, **Bloomwire production should run with
ChatwootHub outbound communication disabled/removed unless explicitly approved.**
This is now **implemented** (see *Implementation status* below) via a centralized
`ChatwootHub.outbound_disabled?` guard that is **secure-by-default in production**.
The target state is:

- no `/ping` to `hub.2.chatwoot.com`,
- no installation metadata sync,
- no pricing-plan sync from ChatwootHub,
- no telemetry events to ChatwootHub,
- no aggregate counts sent to ChatwootHub,
- no Chatwoot push relay dependency unless separately approved.

Rationale framing for this decision: **privacy · security · SaaS isolation ·
customer-data protection · clean licensing boundary · reducing accidental
Enterprise-code usage · keeping Bloomwire-owned product behavior explicit.**

## Non-goals (explicitly out of scope of this decision)

This ADR is **not** about, and must never be framed as, hiding Enterprise feature
usage, avoiding detection, or bypassing the Chatwoot license. The absence of
`channel_voice` telemetry and the lack of a community auto-disable do **not**
constitute permission to run Enterprise code in production. Enterprise calling in
production requires a subscription — full stop.

## Implementation status & remaining tasks

**Slice delivered 2026-06-21 — ChatwootHub outbound isolation** (branch
`feature/bloomwire-chatwoothub-outbound-isolation`):

- **A. Done** — exact ChatwootHub call sites audited: `sync_with_hub`,
  `register_instance`, `send_push`, `emit_event`, and the daily
  `Internal::CheckNewVersionsJob` (with its Enterprise plan-sync override).
- **B. Done** — production-safe config added: `BLOOMWIRE_DISABLE_CHATWOOT_HUB`
  (secure-by-default: isolated in `production` when unset) plus an explicit
  `BLOOMWIRE_ALLOW_CHATWOOT_HUB_PUSH` override for the push relay. A single
  centralized predicate `ChatwootHub.outbound_disabled?` gates every outbound
  method.
- **C. Done** — the daily `Internal::CheckNewVersionsJob` returns early under
  isolation, so the production ping / plan sync never runs.
- **D. Done (simulated)** — verified via a production-simulated runner with a
  `RestClient.post` spy: **zero** posts to `hub.2.chatwoot.com` under isolation;
  `/ping` is attempted only when isolation is explicitly disabled. Real
  production network verification remains an ops checklist item.
- **E. Done** — specs create and read OSS account/inbox/contact/conversation/
  message under isolation; Super Admin Accounts + Bloomwire Businesses pages
  verified loading in-browser with only known dev console noise.
- **F. Parked** — removing/disabling the Enterprise overlay from the production
  build (this slice does **not** touch the overlay).
- **G. Parked** — designing a Bloomwire-owned calling architecture if calling
  becomes required.

The Enterprise overlay was intentionally **not** removed or modified, and
`channel_voice` / Enterprise calling code remain untouched and unused.

## Consequences

- **Positive:** clean licensing boundary; no accidental Enterprise-code coupling;
  reduced production outbound surface (privacy / tenant isolation); explicit,
  Bloomwire-owned product behavior; a clear path to a future calling feature
  without legal risk.
- **Trade-offs:** if calling is needed sooner, Bloomwire must either build its own
  layer or purchase a Chatwoot Enterprise subscription — there is no free
  shortcut through the Enterprise overlay.
- **Carried-forward constraints:** Chatwoot CE source of truth; no Enterprise
  dependency; `bloomwire_` table prefix; backend-enforced permissions; safe DTOs.

## Status of code

- **The ChatwootHub outbound isolation guard is implemented** (see *Implementation
  status* above): `app/lib/chatwoot_hub.rb` (predicate + per-method guards) and
  `app/app/jobs/internal/check_new_versions_job.rb` (job guard), with acceptance
  and edge/security specs under `app/spec/lib/bloomwire/`.
- **No migration, schema, or Enterprise-overlay change** was made. `channel_voice`
  and Enterprise calling code are untouched and remain unused. This is **not** a
  licensing bypass and does **not** permit Enterprise feature use — **Enterprise
  features still require a valid Chatwoot Enterprise subscription/license.**

## References

- Audit source files: `app/package.json`, `app/lib/chatwoot_app.rb`,
  `app/lib/chatwoot_hub.rb`, `app/config/features.yml`,
  `app/enterprise/LICENSE`, `app/enterprise/config/premium_features.yml`,
  `app/enterprise/app/services/internal/reconcile_plan_config_service.rb`,
  `app/enterprise/app/jobs/enterprise/internal/check_new_versions_job.rb`,
  `app/enterprise/app/controllers/twilio/voice_controller.rb`,
  `app/enterprise/app/services/whatsapp/call_service.rb`,
  `app/enterprise/app/models/call.rb`, `app/config/routes.rb`,
  `app/db/schema.rb`, `app/app/models/message.rb`.
- Related docs: `0001-technical-baseline.md`,
  `0003-bloomwire-permission-and-channel-control-boundary.md` (permission &
  channel-control boundary — who may create tenants/channels), `../../CONTEXT.md`,
  `../product/05-development-phases.md`, `../system-overview/index.html`.
