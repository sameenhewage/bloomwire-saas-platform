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
  # Fail-closed readiness: a managed inbox is persisted ONLY when the number is live on the Cloud API. When the
  # selected registration is DISCONNECTED, the same number may be CONNECTED as a duplicate under another WABA the
  # token can message — Bloomwire::WhatsappConnectedNumberResolver routes to that single same-business registration,
  # or fails closed (no channel/inbox/setup). The whole gate runs before any DB write.
  CONNECTED_STATUS = 'CONNECTED'.freeze

  Result = Struct.new(:dto, :error, keyword_init: true) do
    def success?
      error.nil?
    end
  end

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

    target = resolve_target(meta)
    return Result.new(error: target) if target.is_a?(Symbol)

    persisted = persist(meta[:token], target[:waba_id], target[:phone_info], meta[:verification_pin])
    return Result.new(error: persisted) if persisted.is_a?(Symbol)

    Result.new(dto: dto_for(persisted))
  end

  private

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

  # All Meta calls up front (before any DB write) so a Meta failure leaves NO partial records. Returns nil on any
  # failure with a sanitized (class-only) log — never the message/body (which can carry the token or PII).
  def perform_meta_steps
    token = Whatsapp::TokenExchangeService.new(@code).perform
    phone_info = Whatsapp::PhoneInfoService.new(@waba_id, @phone_number_id, token).perform
    client = Whatsapp::FacebookApiClient.new(token)
    # App-to-WABA subscription only (global router). NOT override_waba_callback / subscribe_waba_webhook.
    client.subscribe_app_to_waba(@waba_id)
    # Register the number on Cloud API so Meta moves it from DISCONNECTED to CONNECTED (mirrors native
    # Whatsapp::WebhookSetupService). Best-effort: a registration failure (e.g. Meta (#100) when the app is not
    # the WABA owner) is not raised here — the readiness gate (CONNECTED check in #perform) then fails closed on a
    # non-CONNECTED number so NO partial inbox is created.
    verification_pin = register_number(client, phone_info[:phone_number_id])
    # Fail-closed readiness signal: the actual Meta connection state, checked by the caller before any DB write.
    connection_status = client.phone_number_status(phone_info[:phone_number_id])
    { token: token, client: client, phone_info: phone_info, verification_pin: verification_pin,
      connection_status: connection_status }
  rescue StandardError => e
    Rails.logger.error("[BLOOMWIRE EMBEDDED SIGNUP] Meta step failed: #{e.class}")
    nil
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

  # Registers the number on Cloud API with a fresh 6-digit 2FA PIN. Returns the PIN (persisted so a later
  # re-register does not lock the number out), or nil when the call fails (non-fatal by design).
  def register_number(client, phone_number_id)
    pin = format('%06d', SecureRandom.random_number(1_000_000))
    client.register_phone_number(phone_number_id, pin)
    pin
  rescue StandardError => e
    Rails.logger.warn("[BLOOMWIRE EMBEDDED SIGNUP] Phone registration failed (continuing, stays DISCONNECTED): #{e.class}")
    nil
  end

  # DB-only, atomic. Returns the created Bloomwire::WhatsappSetup, or a safe Symbol error.
  def persist(token, waba_id, phone_info, verification_pin)
    return :phone_number_taken if Channel::Whatsapp.exists?(phone_number: phone_info[:phone_number])

    setup = nil
    error = nil
    ActiveRecord::Base.transaction do
      channel = create_channel_shell(waba_id, phone_info)
      inbox = create_inbox(channel, phone_info)
      Bloomwire::WhatsappCredentialWriter.new(channel: channel, attributes: { 'api_key' => token }).perform
      store_verification_pin(channel, verification_pin)
      creator = create_mapping(channel, inbox, waba_id, phone_info)
      if creator.success?
        setup = creator.setup
      else
        error = creator.error
        raise ActiveRecord::Rollback
      end
    end
    error || setup
  rescue ActiveRecord::RecordNotUnique
    :phone_number_taken
  end

  # The register step's 2FA PIN is persisted (provider_config is encrypted at rest, ADR-0006) so a later
  # re-register does not lock out the number. Kept off the Ops credential-writer surface deliberately.
  def store_verification_pin(channel, verification_pin)
    return if verification_pin.blank?

    channel.provider_config['verification_pin'] = verification_pin
    channel.save!(validate: false)
  end

  # Credential-less shell: source 'bloomwire_managed' skips the after_commit per-channel webhook setup; a blank
  # api_key at create-time no-ops the after_create template sync; save(validate: false) skips the remote
  # validate_provider_config credential re-check (no live Meta call). The api_key is written next, encrypted.
  def create_channel_shell(waba_id, phone_info)
    channel = Channel::Whatsapp.new(
      account: @account,
      phone_number: phone_info[:phone_number],
      provider: 'whatsapp_cloud',
      provider_config: {
        'phone_number_id' => phone_info[:phone_number_id],
        'business_account_id' => waba_id,
        'source' => 'bloomwire_managed',
        'connection_mode' => 'standard'
      }
    )
    channel.save!(validate: false)
    channel
  end

  def create_inbox(channel, phone_info)
    Inbox.create!(account: @account, name: inbox_name(phone_info), channel: channel)
  end

  def inbox_name(phone_info)
    "#{phone_info[:business_name].presence || 'WhatsApp'} WhatsApp"
  end

  def create_mapping(channel, inbox, waba_id, phone_info)
    Bloomwire::WhatsappSetupCreator.call(
      account: @account,
      inbox: inbox,
      channel_whatsapp: channel,
      phone_number_id: phone_info[:phone_number_id],
      waba_id: waba_id,
      display_phone_number: phone_info[:phone_number]
    )
  end

  # Safe DTO — ids/status + masked phone only; NEVER api_key / token / provider_config.
  def dto_for(setup)
    readiness = Bloomwire::WhatsappRealHopReadiness.new(setup).result
    {
      inbox: { id: setup.inbox_id, name: setup.inbox&.name },
      channel: { id: setup.channel_whatsapp_id, type: 'Channel::Whatsapp', source: 'bloomwire_managed' },
      setup: { id: setup.id, status: setup.setup_status, readiness: readiness[:status] },
      phone: readiness[:masked]
    }
  end
end
