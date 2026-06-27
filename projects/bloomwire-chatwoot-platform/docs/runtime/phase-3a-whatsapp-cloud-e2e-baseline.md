# Phase 3A — WhatsApp Cloud API Real E2E Baseline (Evidence Note)

> **STATUS: PARTIAL.**
> - Automated baseline (graphify + flow analysis + Phase 1/2 + native WhatsApp specs + RuboCop): **PASS**.
> - **Live real-phone E2E (steps 5–10 below): PENDING / BLOCKED** — requires real Meta/WhatsApp Cloud
>   credentials, a Meta Business account + WABA + registered number, a physical test phone, and a public
>   HTTPS tunnel. These cannot be performed by the agent autonomously and must be run by a human operator.
> - **No PR will be opened until the live E2E rows below are filled with real (masked) evidence.**

## 1. Environment
- App: Chatwoot (this repo, nested Rails root `app/`), local dev (`overmind`/`pnpm dev`), Postgres + Redis + Sidekiq.
- Ruby via rbenv (`.ruby-version`). Dev server: `http://localhost:3000`.
- Public ingress for Meta webhooks: **TODO** (approved local tunnel; document masked URL only).

## 2. Branch / HEAD
- Branch: `feature/bloomwire-phase-3a-whatsapp-cloud-e2e-baseline`
- HEAD SHA: `86c64d3a9fbedde4379e7bc7799333628a4c4e83` (base: `version_1`, which has Phase 1 + 2A + 2B + 2C merged).

## 3. Graphify freshness
- `graphify update .` run on this branch; **rebuilt** 327,548 nodes / 349,123 edges / 17,112 communities (6,844 files).
- `GRAPH_REPORT.md` `Built from commit: 86c64d3a` == HEAD `86c64d3a` → **fresh**.
- Confirmed nodes present: `whatsappcontroller_process_payload`, `whatsappeventsjob_perform`,
  `webhooksetupservice_setup_webhook`, `whatsappcloudservice_send_message`, plus Phase 2B/2C nodes
  (`provider_config_scrubber`, `sensitive_data_redactor`).
- graphify-out is git-ignored and is **not** committed.

## 4. Native WhatsApp Cloud flow (as built — no Bloomwire code change)
1. **Bind / connect** — `Channel::Whatsapp` (`provider: 'whatsapp_cloud'`) with `provider_config`
   `{ api_key, phone_number_id, business_account_id }`. `before_validation :ensure_webhook_verify_token`
   auto-generates `webhook_verify_token` (`SecureRandom.hex(16)`). `validate_provider_config` verifies creds
   against Meta (`GET <waba>/message_templates`). Manual flow: `after_commit :setup_webhooks` registers the
   webhook with Meta (`should_auto_setup_webhooks?` = whatsapp_cloud && source != embedded_signup).
   `app/models/channel/whatsapp.rb`.
2. **Callback URL** — `FRONTEND_URL/webhooks/whatsapp/<phone_number>`
   (`Whatsapp::WebhookSetupService#build_callback_url`). Routes: `GET/POST /webhooks/whatsapp/:phone_number`.
3. **Meta webhook verification** — `Webhooks::WhatsappController#verify` (via `MetaTokenVerifyConcern`),
   `valid_token?` compares `hub.verify_token` to `channel.provider_config['webhook_verify_token']`
   (direct model read). `app/controllers/webhooks/whatsapp_controller.rb:19-23`.
4. **Inbound** — `POST #process_payload` → `verify_meta_signature!` → enqueue `Webhooks::WhatsappEventsJob`
   → `Whatsapp::IncomingMessageWhatsappCloudService` → contact + conversation + message in the inbox.
5. **Outbound** — outgoing message → `SendReplyJob` → `Whatsapp::SendOnWhatsappService#send_session_message`
   → `Channel::Whatsapp#send_message` → `Whatsapp::Providers::WhatsappCloudService` →
   `POST graph.facebook.com/v13.0/<phone_number_id>/messages` with `Authorization: Bearer <api_key>`;
   `message.source_id` set to the returned `wamid`.
6. **Status** — status webhooks flow through the same controller/job → status update path.

## 5. Phase 1/2 runtime-safety confirmation (investigation item 7)
- **Phase 2B (`ProviderConfigScrubber.for_response`)** is invoked **only** in `app/views/api/v1/models/_inbox.json.jbuilder`
  (outbound DTO). Every runtime consumer reads `channel.provider_config[...]` **directly** from the model
  (send: `whatsapp_cloud_service.rb:61-63,94`; verify: `whatsapp_controller.rb:21`; setup:
  `webhook_setup_service.rb:4-5,60`). → DTO scrub **cannot** break send/receive/verify/setup.
- **Phase 2C (`SensitiveDataRedactor`)** is invoked **only** at two log boundaries
  (`callbacks_controller#log_additional_info`, `base_service#handle_error`). It never mutates data the flow uses.
- Conclusion: privacy hardening ON is **output/log-only** and does not remove any value the runtime needs.

## 6. Automated validation results
- `rspec` (Phase 1/2 + native WhatsApp flow): **139 examples, 0 failures**
  - `bloomwire/features_spec`, `bloomwire/sensitive_data_redactor_spec`,
    `super_admin/app_config_bloomwire_app_secret_masking_spec`,
    `super_admin/installation_configs_app_secret_masking_spec`,
    `api/v1/accounts/inboxes_provider_config_scrub_spec`,
    `webhooks/whatsapp_controller_spec`, `webhooks/whatsapp_events_job_spec`,
    `whatsapp/webhook_setup_service_spec`, `whatsapp/send_on_whatsapp_service_spec`,
    `whatsapp/incoming_message_whatsapp_cloud_service_spec`,
    `whatsapp/providers/whatsapp_cloud_service_spec`.
- `rubocop` (native flow files): **no offenses**.
- **Code change required for the baseline: NONE** (the native path is fully implemented; Phase 1/2 are output/log-only).

## 7. Live E2E prerequisites (human operator)
- Local `.env` (NEVER committed): `FRONTEND_URL=<public-https-tunnel>`, optionally `WHATSAPP_CLOUD_BASE_URL`.
- Global: `WHATSAPP_APP_SECRET` (InstallationConfig) for inbound signature verification.
- Per inbox `provider_config`: real `api_key` (Meta access token), `phone_number_id`, `business_account_id` (WABA).
- A public HTTPS tunnel pointing at `localhost:3000` (document the **masked** URL only).
- A real consumer WhatsApp phone to message the business number, and access to send a reply from the Chatwoot inbox.

## 8. Live E2E runbook (execute manually; fill §9)
1. Start tunnel; set `FRONTEND_URL` to the tunnel URL; boot app; confirm SuperAdmin login + Bloomwire Features page.
2. Tenant account login; create a WhatsApp (Cloud) inbox with real `api_key` / `phone_number_id` / `business_account_id`.
3. Confirm Chatwoot registered the webhook (or configure it in Meta) and Meta verification (GET) returns 200.
4. From the test phone, send an inbound WhatsApp message to the business number; record timestamp.
5. Confirm the message appears in the correct Chatwoot inbox/conversation.
6. Reply from the Chatwoot inbox; record timestamp; confirm receipt on the test phone.
7. Confirm message/status history is consistent.
8. With **master ON + privacy hardening ON**, repeat 4–6 and confirm: send/receive still works; inbox API
   `provider_config` is scrubbed; server logs show `[FILTERED]` (no real tokens). Then with **master OFF**,
   confirm stock behavior.
9. Confirm no new console/server errors and no unrelated tenant UI regression.

## 9. Live E2E evidence (PENDING — fill with masked values)
| Field | Value |
|---|---|
| Tunnel/callback URL (masked) | `TODO https://****.<tunnel>/webhooks/whatsapp/+****1234` |
| WhatsApp inbox id / name | `TODO` |
| phone_number_id (masked) | `TODO ****` |
| business WABA number (masked) | `TODO +****1234` |
| Webhook verification result | `TODO (GET 200 / token match)` |
| Inbound test timestamp + result | `TODO` |
| Outbound test timestamp + result | `TODO` |
| Privacy ON: send/receive OK | `TODO` |
| Privacy ON: provider_config scrubbed in API | `TODO` |
| Privacy ON: logs show [FILTERED], no real tokens | `TODO` |
| New errors / regressions | `TODO` |

## 10. Known blockers
- Live real-phone E2E requires real Meta credentials + a physical phone + a public tunnel + a Meta Business
  account/WABA. The agent cannot perform these autonomously; a human operator must run §8 and record §9.
- Until §9 is complete, the Phase 3A PR gate is **not** met and **no PR will be opened**.
