# Slice 2 (ADR-0010 v3): resumable, idempotent processor that drives ONE Bloomwire::WhatsappOnboardingAttempt to a
# terminal state. All Meta HTTP happens with NO DB transaction/row lock open; every credential/state write is
# guarded by (owner + submission_generation). Corrected step machine (v3 + four correctness gaps):
#
# 0. claim_lease! (short with_lock) — not claimable (stale/owned/terminal) => no-op.
# 1. RESUME-FROM-PERSISTED (gap 4): matching finalized Setup (ready/action-required) + channel credential =>
#    bind ids and FINALIZE with NO exchange/register/subscribe. Disconnected reconnects continue through OAuth.
# 2. TWO-STAGE TOKEN (gap 1): exchange code -> SHORT token (store + clear code atomically); then SHORT -> LONG
#    (upgrade). On a transient long-exchange failure the SHORT token is RETAINED (retry only step 2); the consumed
#    OAuth code is never re-exchanged.
# 3. reconcile-before-mutate REGISTER: GET status; CONNECTED => skip /register; else renew lease, register, re-GET.
# 4. resolve final WABA (duplicate-number resolver).
# 5. CAPABILITY-BEFORE-SUBSCRIPTION (gap 2): capability on the FINAL WABA. ready => GET subscribed_apps, subscribe
#    only if absent, verify; not ready => do NOT subscribe (persist action_required, Recheck path preserved).
# 6. persist exactly one Channel/Inbox/Setup (idempotent); mark_credential_persisted! (clear token); finalize.
#
# LEASE SAFETY (gap 3): the lease TTL (Attempt.mutation_lease_seconds, derived from the single Graph-timeout
# config) outlasts the max bounded Graph call; the lease is renewed under a short lock BEFORE each mutation and
# RELEASED before the HTTP call; ownership+generation are re-checked before every write; a lost lease => NO local
# write; release is guarded (matching owner+generation).
# TRANSIENT errors (timeout/5xx/network) => retain the encrypted token + stage, record a sanitized code, stay
# resumable (never terminal). Only confirmed-terminal cases clear secrets. Sanitized errors only; no secret leakage.
#
# OAUTH ERROR CLASSIFICATION (no invented Meta codes — only GraphApiError safe fields is_transient/http_status/
# error_type): TERMINAL (status=expired, safe_error_code=oauth_code_expired, secrets cleared, not redrivable, no
# endless retry) ONLY when Meta confirms an OAuthException that is not is_transient (an invalid/expired auth code).
# RETRYABLE (safe_error_code=oauth_exchange_retryable; oauth_code/token/stage retained) for a network/read timeout,
# Meta's is_transient flag, an HTTP 5xx, an HTTP 429 rate limit, or any unclassifiable error.
class Bloomwire::WhatsappOnboardingProcessor
  Attempt = Bloomwire::WhatsappOnboardingAttempt
  CONNECTED_STATUS = 'CONNECTED'.freeze
  PIN_MISMATCH_META_ERROR_CODE = 133_005

  def initialize(attempt:, owner: nil, generation: nil, persister: nil)
    @attempt = attempt
    @account = attempt.account
    @owner = owner.presence || "onboarding-#{SecureRandom.hex(6)}"
    # The generation this worker was enqueued for (a stale job carries an older one); defaults to the current value.
    @generation = generation || attempt.submission_generation
    @persister = persister || Bloomwire::WhatsappOnboardingPersister.new(@account)
  end

  def process
    return unless @attempt.claim_lease!(owner: @owner, ttl_seconds: Attempt.mutation_lease_seconds, expected_generation: @generation)

    begin
      process_owned
    ensure
      @attempt.release_lease!(owner: @owner, expected_generation: @generation)
    end
  rescue Attempt::StaleWorkerError
    nil # a newer worker/generation owns this attempt; make no local write
  end

  private

  def process_owned
    return if resume_from_persisted_setup

    mark_processing
    token = ensure_long_lived_token
    return if token.blank? # transient failure recorded; credential retained (resumable)

    client = Whatsapp::FacebookApiClient.new(token)
    phone_info = fetch_phone_info(token)
    return if phone_info.nil?

    registration = reconcile_register(client, phone_info)
    return if registration.nil? # aborted (transient) or lost lease -> no write

    target = resolve_target(client, token, phone_info, registration[:connection_status])
    return if target.nil?

    capability = outbound_capability(client, token, target[:waba_id])
    return unless subscribe_if_ready(client, target[:waba_id], capability)

    persist_and_finalize(token, target, registration[:verification_pin], capability)
  end

  def mark_processing
    @attempt.transition!(Attempt::PROCESSING) unless @attempt.status == Attempt::PROCESSING
  end

  # ---- Gap 4: resume from persisted-but-not-finalized records --------------------------------------------
  def resume_from_persisted_setup
    setup = Bloomwire::WhatsappSetup.find_by(account_id: @account.id, phone_number_id: @attempt.phone_number_id)
    finalized_statuses = [Bloomwire::WhatsappSetup::ROUTEABLE_STATUS, Bloomwire::WhatsappSetup::ACTION_REQUIRED_STATUS]
    return false unless setup&.setup_status.in?(finalized_statuses) && channel_credential_present?(setup)

    bind_attempt_to_setup(setup)
    @attempt.mark_credential_persisted!(owner: @owner, expected_generation: @generation) if @attempt.access_token.present?
    finalize_from_setup(setup)
    true
  end

  def channel_credential_present?(setup)
    channel = setup.channel_whatsapp
    channel.present? && channel.provider_config['api_key'].present?
  end

  def bind_attempt_to_setup(setup)
    @attempt.bind_target!(waba_id: setup.waba_id, phone_number_id: setup.phone_number_id,
                          phone_number: setup.display_phone_number)
    @attempt.update!(channel_whatsapp_id: setup.channel_whatsapp_id, inbox_id: setup.inbox_id)
  end

  def finalize_from_setup(setup)
    status = setup.setup_status == Bloomwire::WhatsappSetup::ROUTEABLE_STATUS ? Attempt::COMPLETED : Attempt::ACTION_REQUIRED
    @attempt.transition!(status)
  end

  # ---- Gap 1: two-stage OAuth token exchange (resumable) ------------------------------------------------
  def ensure_long_lived_token
    return @attempt.access_token if @attempt.token_stage == Attempt::LONG_LIVED

    short = ensure_short_lived_token
    return if short.blank?

    long = safe_meta { Whatsapp::FacebookApiClient.new.exchange_for_long_lived_token(short) }
    return if long.blank? # transient: SHORT token retained, safe error recorded

    @attempt.upgrade_to_long_lived_token!(long, owner: @owner, expected_generation: @generation)
    @attempt.access_token
  end

  def ensure_short_lived_token
    return @attempt.access_token if @attempt.token_stage == Attempt::SHORT_LIVED
    return terminal_missing_code if @attempt.oauth_code.blank?

    short = exchange_authorization_code
    return if short.blank?

    @attempt.store_short_lived_token!(short, owner: @owner, expected_generation: @generation)
    @attempt.access_token
  end

  # OAuth-code exchange with terminal-vs-transient classification (see the mapping in the class header). Only the
  # TokenExchangeService call is wrapped, so guarded-write / encryption errors propagate. Never logs the code or
  # the raw Meta response.
  def exchange_authorization_code
    Whatsapp::TokenExchangeService.new(@attempt.oauth_code).perform
  rescue Whatsapp::GraphApiTimeoutError, Whatsapp::GraphApiError, StandardError => e
    Bloomwire::WhatsappGraphErrorClassifier.terminal_oauth?(e) ? terminal_oauth_expired! : record_safe_error(:oauth_exchange_retryable)
    nil
  end

  def fetch_phone_info(token)
    safe_meta { Whatsapp::PhoneInfoService.new(@attempt.waba_id, @attempt.phone_number_id, token).perform }
  end

  # ---- Gap 3 + reconcile-before-register ---------------------------------------------------------------
  def reconcile_register(client, phone_info)
    phone_number_id = phone_info[:phone_number_id]
    status = safe_meta { client.phone_number_status(phone_number_id) }
    return if status.nil?
    return { connection_status: status, verification_pin: nil } if status == CONNECTED_STATUS

    return unless @attempt.renew_lease!(owner: @owner, expected_generation: @generation) # re-check before POST

    pin = register_number(client, phone_number_id)
    return if pin == :aborted

    new_status = safe_meta { client.phone_number_status(phone_number_id) }
    return if new_status.nil?

    { connection_status: new_status, verification_pin: pin }
  end

  # Registers using the RESOLVED PIN (stored > configured > fresh). Returns the pin on success, nil on a non-fatal
  # register failure (number stays DISCONNECTED; resolver then decides), or :aborted on a transient timeout.
  def register_number(client, phone_number_id)
    pin = Bloomwire::WhatsappRegistrationPin.new(account: @account, phone_number_id: phone_number_id).resolve.pin
    client.register_phone_number(phone_number_id, pin)
    pin
  rescue Whatsapp::GraphApiTimeoutError
    record_safe_error(:meta_timeout)
    :aborted
  rescue Whatsapp::GraphApiError => e
    record_safe_error(pin_mismatch?(e) ? :registration_pin_required : :registration_failed)
    nil
  end

  def pin_mismatch?(error)
    error.respond_to?(:error_code) && error.error_code.to_i == PIN_MISMATCH_META_ERROR_CODE
  end

  def resolve_target(client, token, phone_info, connection_status)
    return { waba_id: @attempt.waba_id, phone_info: phone_info } if connection_status == CONNECTED_STATUS

    resolution = safe_meta do
      Bloomwire::WhatsappConnectedNumberResolver.new(
        client: client, input_token: token, selected_waba_id: @attempt.waba_id,
        selected_phone_number: phone_info[:phone_number]
      ).resolve
    end
    return if resolution.nil?
    return record_safe_error(resolution.error) unless resolution.ok?

    { waba_id: resolution.waba_id, phone_info: phone_info.merge(phone_number_id: resolution.phone_number_id) }
  end

  # ---- Gap 2: capability BEFORE subscription ----------------------------------------------------------
  def outbound_capability(client, token, waba_id)
    Bloomwire::WhatsappMessagingCapability.new(client: client, token: token, waba_id: waba_id, allow_grant: false).ensure
  end

  # ready => reconcile (GET subscribed_apps) then subscribe only if absent, and verify. not ready => skip (the
  # setup persists as action_required). Returns true to proceed to persistence, false to abort (lost lease/failure).
  def subscribe_if_ready(client, waba_id, capability)
    return true unless capability.ready?
    return true if safe_meta { client.subscribed_to_waba?(waba_id) }
    return false unless @attempt.renew_lease!(owner: @owner, expected_generation: @generation) # re-check before POST

    safe_meta { client.subscribe_app_to_waba(waba_id) }
    return true if safe_meta { client.subscribed_to_waba?(waba_id) }

    record_safe_error(:subscription_failed)
    false
  end

  # ---- Persist (idempotent) + finalize ----------------------------------------------------------------
  def persist_and_finalize(token, target, verification_pin, capability)
    return unless @attempt.renew_lease!(owner: @owner, expected_generation: @generation) # re-check before local write

    setup = safe_meta do
      @persister.call(token: token, waba_id: target[:waba_id], phone_info: target[:phone_info],
                      verification_pin: verification_pin, capability: capability)
    end
    return if setup.nil? # transient persist failure -> retain, retry
    return record_safe_error(setup) if setup.is_a?(Symbol)

    bind_attempt_to_setup(setup)
    @attempt.mark_credential_persisted!(owner: @owner, expected_generation: @generation)
    finalize_from_setup(setup)
  end

  # ---- Sanitized error handling (never a secret; transient => retain, resumable) -----------------------
  # Wraps a Meta call: on any error records a stable, non-secret code and returns nil (transient/resumable). Never
  # logs the exception message/body (either can echo a token). Terminal handling is explicit at the call sites.
  def safe_meta
    yield
  rescue Whatsapp::GraphApiTimeoutError
    record_safe_error(:meta_timeout)
    nil
  rescue StandardError
    record_safe_error(:meta_error)
    nil
  end

  # Records a stable, non-secret error/retry code WITHOUT clearing credentials or marking a terminal failure.
  def record_safe_error(code)
    @attempt.update!(safe_error_code: code.to_s)
    nil
  end

  # No code AND no stored token => nothing resumable => terminal (clear per lifecycle).
  def terminal_missing_code
    @attempt.transition!(Attempt::FAILED, error_code: 'missing_code')
    @attempt.clear_secrets!
    nil
  end

  # Meta confirmed the authorization code is unusable: terminal EXPIRED, both secrets cleared, not redrivable.
  def terminal_oauth_expired!
    @attempt.transition!(Attempt::EXPIRED, error_code: 'oauth_code_expired')
    @attempt.clear_secrets!
    nil
  end
end
