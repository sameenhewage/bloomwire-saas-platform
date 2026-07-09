# Phase 17C.2: dedicated customer WhatsApp Embedded Signup for Bloomwire managed mode. This is the ONLY seam
# that turns a Meta embedded-signup `code` into a working managed WhatsApp inbox — WITHOUT touching the native
# Whatsapp::EmbeddedSignupService (which registers a per-channel webhook) and WITHOUT weakening native flows.
#
# Boundary (do not weaken):
# - Bloomwire GLOBAL webhook router owns inbound: we only `subscribe_app_to_waba` (app-level subscription so Meta
#   forwards this WABA to the global callback). We NEVER call channel.setup_webhooks / override_waba_callback /
#   subscribe_waba_webhook (no per-customer callback override).
# - The channel is created as a `source: 'bloomwire_managed'` shell (skips the model's after_commit webhook setup
#   and the template sync — api_key is written AFTER create via the credential writer), then the encrypted
#   api_key is stored ONLY in Channel::Whatsapp#provider_config (ADR-0006).
# - Bloomwire::WhatsappSetup stores only non-secret routing identifiers (via Bloomwire::WhatsappSetupCreator).
# - Fails closed BEFORE storing a token when platform config is incomplete or (outside dev/test) encryption is
#   not configured. Meta errors are sanitized (class-only logs; a generic :meta_error) — no raw payload/token.
# - The result DTO carries only safe, non-secret fields (ids, status, masked phone) — never api_key/provider_config.
class Bloomwire::WhatsappEmbeddedSignupService
  # DB persistence + WhatsWay-parity reconnect live in a focused mixin (keeps this orchestrator readable). The
  # Coexistence subclass's create_channel_shell/dto_for overrides still resolve first through the ancestor chain.
  include Bloomwire::WhatsappSignupPersistence

  # Fail-closed readiness: a managed inbox is persisted ONLY when the number is live on the Cloud API. When the
  # selected registration is DISCONNECTED, the same number may be CONNECTED as a duplicate under another WABA the
  # token can message — Bloomwire::WhatsappConnectedNumberResolver routes to that single same-business registration,
  # or fails closed (no channel/inbox/setup). The whole gate runs before any DB write.
  CONNECTED_STATUS = 'CONNECTED'.freeze
  # Meta Graph API error code for a Cloud API /register two-step-verification PIN mismatch. Hitting it means the
  # number already carries a 2SV PIN we do not hold — fail closed (never silently retry with another random PIN).
  PIN_MISMATCH_META_ERROR_CODE = 133_005
  # Non-secret guidance shown to the account owner. Until this step is completed the managed inbox is NOT active
  # in EITHER direction — it is deliberately not subscribed for inbound and cannot send outbound — so we say so
  # plainly. The concrete Meta asset-task grant is a customer/owner action; "Recheck permission" then activates it.
  OUTBOUND_ACTION_REQUIRED_RESOLUTION =
    'This WhatsApp inbox is not active yet — it can neither receive nor send messages until one more Meta step ' \
    'is completed: in Meta Business Settings, grant this WhatsApp Business Account the Manage task to the ' \
    'connected system user, then use "Recheck permission" to activate the inbox.'.freeze

  Result = Struct.new(:dto, :error, keyword_init: true) do
    def success?
      error.nil?
    end
  end

  # Internal result of the Cloud API /register step. `pin` is the (secret) PIN used on success — persisted encrypted,
  # never logged/returned. `error` is a safe Symbol surfaced to the caller ONLY when register failed in a way the
  # owner must act on (:registration_pin_required for a 2SV PIN mismatch); nil keeps the failure non-fatal.
  RegistrationResult = Struct.new(:pin, :error, keyword_init: true)

  def initialize(account:, params:)
    @account = account
    @code = params[:code].presence
    @business_id = params[:business_id].presence
    @waba_id = params[:waba_id].presence
    @phone_number_id = params[:phone_number_id].presence
  end

  def perform
    preflight_error = preflight
    return Result.new(error: preflight_error) if preflight_error

    meta = perform_meta_steps
    return Result.new(error: :meta_error) if meta.nil?
    return Result.new(error: meta[:registration_error]) if meta[:registration_error]

    target = resolve_target(meta)
    return Result.new(error: target) if target.is_a?(Symbol)

    finalize(meta, target)
  end

  private

  # Outbound capability is verified BEFORE any subscription, and we subscribe ONLY on the ready path — a not-ready
  # inbox must never be subscribed (Meta would forward inbound the global router then discards). So an
  # Action-Required inbox is persisted UNSUBSCRIBED, inactive in both directions until "Recheck" completes it.
  def finalize(meta, target)
    capability = outbound_capability(meta, target[:waba_id])

    activation_error = subscribe_final_waba(meta[:client], target[:waba_id]) if capability.ready?
    return Result.new(error: activation_error) if activation_error

    persisted = persist(meta[:token], target[:waba_id], target[:phone_info], meta[:verification_pin], capability)
    return Result.new(error: persisted) if persisted.is_a?(Symbol)

    Result.new(dto: dto_for(persisted))
  end

  # Fail closed before any Meta call / token storage.
  def preflight
    return :missing_code if @code.blank?
    return :missing_waba_id if @waba_id.blank?
    return :not_ready unless Bloomwire::GlobalWhatsappConfig.new.result[:platform_ready]
    return :encryption_not_configured unless encryption_ok?

    nil
  end

  # Customer access tokens must never be persisted in plaintext outside local dev/test (ADR-0006). Storing them
  # requires Active Record encryption to be configured; dev/test may proceed (explicit local-env guard) so the
  # flow is testable without keys.
  def encryption_ok?
    Chatwoot.encryption_configured? || local_env?
  end

  def local_env?
    Rails.env.development? || Rails.env.test?
  end

  # Extend the short-lived embedded-signup USER token to a long-lived (~60 day) one — the WhatsWay-proven step
  # that keeps the stored operational credential usable beyond ~1h. Fails open to the short token.
  def long_lived_token(short_token)
    Whatsapp::FacebookApiClient.new.exchange_for_long_lived_token(short_token)
  end

  # All Meta calls up front (before any DB write) so a Meta failure leaves NO partial records. Returns nil on any
  # failure with a sanitized (class-only) log — never the message/body (which can carry the token or PII).
  def perform_meta_steps
    short_token = Whatsapp::TokenExchangeService.new(@code).perform
    log_signup_token(stage: 'code_exchange', token: short_token, phone_number_id: @phone_number_id)
    token = long_lived_token(short_token)
    client = Whatsapp::FacebookApiClient.new(token)
    log_signup_token(stage: 'long_lived_exchange', token: token, phone_number_id: @phone_number_id, client: client)
    phone_info = Whatsapp::PhoneInfoService.new(@waba_id, @phone_number_id, token).perform
    phone_number_id = phone_info[:phone_number_id]
    log_signup_token(stage: 'pre_register', token: token, phone_number_id: phone_number_id, client: client)
    registration = ensure_registered(client, phone_number_id)
    { token: token, client: client, phone_info: phone_info, **registration }
  rescue StandardError => e
    Rails.logger.error("[BLOOMWIRE EMBEDDED SIGNUP] Meta step failed: #{e.class}")
    nil
  end

  # Ensures the number is registered on the Cloud API. Registers ONLY when it is not already CONNECTED
  # (re-registering a live, pin-enabled number can disrupt the owner-set registration). A /register failure stays
  # non-fatal (the readiness gate then fails closed) unless it is a 2SV PIN mismatch we must surface to the owner.
  # Returns connection_status + the verification_pin used (persisted encrypted) + any owner-facing registration_error.
  def ensure_registered(client, phone_number_id)
    status = client.phone_number_status(phone_number_id)
    return { connection_status: status, verification_pin: nil, registration_error: nil } if status == CONNECTED_STATUS

    registration = register_number(client, phone_number_id)
    { connection_status: client.phone_number_status(phone_number_id),
      verification_pin: registration.pin, registration_error: registration.error }
  end

  def log_signup_token(stage:, token:, phone_number_id:, client: Whatsapp::FacebookApiClient.new(token))
    Bloomwire::WhatsappSignupTokenDebug.log(
      stage: stage, client: client, token: token, waba_id: @waba_id, phone_number_id: phone_number_id
    )
  end

  # Chooses the (waba_id, phone_info) actually persisted. The customer's selection is used as-is when Meta reports
  # it live. When it is DISCONNECTED, a duplicate of the same number may be CONNECTED under another WABA the token
  # can message (Meta allows multi-WABA registration) — we route to that single same-business registration so
  # inbound webhooks and outbound sends use the LIVE phone_number_id. Otherwise we fail closed (safe Symbol).
  def resolve_target(meta)
    phone_info = meta[:phone_info]
    return { waba_id: @waba_id, phone_info: phone_info } if meta[:connection_status] == CONNECTED_STATUS

    resolution = Bloomwire::WhatsappConnectedNumberResolver.new(
      client: meta[:client], input_token: meta[:token],
      selected_waba_id: @waba_id, selected_phone_number: phone_info[:phone_number]
    ).resolve
    return resolution.error unless resolution.ok?

    { waba_id: resolution.waba_id, phone_info: phone_info.merge(phone_number_id: resolution.phone_number_id) }
  end

  # Subscribe the FINAL resolved WABA (which, after #resolve_target, can differ from the selection) to the app,
  # then VERIFY it took effect (subscribed_apps) so a silent failure never yields a ready-but-deaf inbox. Fails
  # closed (Symbol). This is the single point the inbox becomes live for inbound (global router) AND outbound;
  # NEVER override_waba_callback / subscribe_waba_webhook.
  #
  # Idempotent/resumable: if a prior (e.g. timed-out) attempt already subscribed the app to this WABA, we SKIP the
  # subscribe POST and treat the step as already done — so a retry after a subscribe-then-timeout resumes cleanly.
  def subscribe_final_waba(client, waba_id)
    return nil if client.subscribed_to_waba?(waba_id)

    client.subscribe_app_to_waba(waba_id)
    client.subscribed_to_waba?(waba_id) ? nil : :subscription_failed
  rescue StandardError => e
    Rails.logger.error("[BLOOMWIRE EMBEDDED SIGNUP] App-to-WABA subscription failed: #{e.class}")
    :subscription_failed
  end

  # Outbound readiness (send-side counterpart to the CONNECTED gate): VERIFY the EXACT stored-token actor holds
  # the WABA send task (Meta #10). Verify-only (allow_grant: false) — the partner SYSTEM_USER token never self-grants.
  def outbound_capability(meta, waba_id)
    Bloomwire::WhatsappMessagingCapability.new(
      client: meta[:client], token: meta[:token], waba_id: waba_id, allow_grant: false
    ).ensure
  end

  # Registers the number on Cloud API using the PIN RESOLVED for it (stored-encrypted > securely-configured >
  # fresh random), so an EXISTING number is re-registered with its KNOWN 2SV pin instead of a random one Meta
  # rejects (#133005). Returns a RegistrationResult with the PIN on success (persisted encrypted, never logged).
  # A 2SV PIN mismatch fails closed with :registration_pin_required (we hold no correct pin, so never a silent
  # random retry); any other Meta error stays non-fatal (nil error) so the readiness gate fails closed generically.
  def register_number(client, phone_number_id)
    pin = Bloomwire::WhatsappRegistrationPin.new(account: @account, phone_number_id: phone_number_id).resolve.pin
    client.register_phone_number(phone_number_id, pin)
    RegistrationResult.new(pin: pin)
  rescue Whatsapp::GraphApiError => e
    log_phone_registration_failure(phone_number_id, e)
    RegistrationResult.new(error: pin_mismatch?(e) ? :registration_pin_required : nil)
  rescue StandardError => e
    log_phone_registration_failure(phone_number_id, e)
    RegistrationResult.new
  end

  # A Cloud API /register 2SV PIN mismatch (#133005): the number already has a two-step-verification PIN we could
  # not match. Detected on the sanitized, allow-listed Meta error code only (never the raw body).
  def pin_mismatch?(error)
    error.error_code.to_i == PIN_MISMATCH_META_ERROR_CODE
  end

  # Sanitized, structured observability for a failed Cloud API /register. The failure stays non-fatal (the number
  # remains DISCONNECTED and the readiness gate then refuses to persist), but we now record the SPECIFIC Meta error
  # (status/code/subcode/type/is_transient/fbtrace_id/sanitized message) so a dual-WABA/permission/PIN cause is
  # diagnosable. NEVER logs the token, PIN, OAuth code, Authorization header, cookies, or the raw request/response
  # body — only the exception class name plus the allow-listed safe fields from Whatsapp::GraphApiError#to_safe_h.
  def log_phone_registration_failure(phone_number_id, error)
    event = {
      event: 'bloomwire.whatsapp.phone_registration_failed',
      operation: 'phone_registration',
      phone_number_id: phone_number_id,
      exception_class: error.class.name
    }
    event.merge!(error.to_safe_h) if error.is_a?(Whatsapp::GraphApiError)
    Rails.logger.warn("[BLOOMWIRE EMBEDDED SIGNUP] #{event.to_json}")
  end

  # Safe DTO — ids/status + masked phone only; NEVER api_key / token / provider_config. When outbound is not
  # yet enabled the DTO carries an explicit, secret-free action_required block (reason + the exact Meta step).
  def dto_for(setup)
    readiness = Bloomwire::WhatsappRealHopReadiness.new(setup).result
    dto = {
      inbox: { id: setup.inbox_id, name: setup.inbox&.name },
      channel: { id: setup.channel_whatsapp_id, type: 'Channel::Whatsapp', source: 'bloomwire_managed' },
      setup: { id: setup.id, status: setup.setup_status, readiness: readiness[:status] },
      phone: readiness[:masked]
    }
    if setup.setup_status == Bloomwire::WhatsappSetup::ACTION_REQUIRED_STATUS
      dto[:action_required] = { reason: setup.status_reason, resolution: OUTBOUND_ACTION_REQUIRED_RESOLUTION }
    end
    dto
  end
end
