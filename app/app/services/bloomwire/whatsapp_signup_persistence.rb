# DB persistence + WhatsWay-parity reconnect for the managed WhatsApp embedded-signup flow, extracted from
# Bloomwire::WhatsappEmbeddedSignupService (which #include-s this) so that orchestrator stays focused on the Meta
# steps. Every method is private and relies on the including service's @account and its create/DTO helpers — so the
# Coexistence subclass's create_channel_shell override still resolves normally through the ancestor chain.
#
# Boundary (do not weaken): the token is written ONLY to Channel::Whatsapp#provider_config via
# Bloomwire::WhatsappCredentialWriter; Bloomwire::WhatsappSetup stays non-secret; NO Meta calls happen here (all
# Meta work is done before persistence); cross-account phone/phone_number_id reuse fails closed.
module Bloomwire::WhatsappSignupPersistence
  private

  # DB-only, atomic. Returns the created/reconnected Bloomwire::WhatsappSetup, or a safe Symbol error. The
  # capability result decides the persisted setup_status: routeable-ready when the actor can send, else Action-Required.
  def persist(token, waba_id, phone_info, verification_pin, capability)
    reconnected = reconnect_same_account_number(token, waba_id, phone_info, verification_pin, capability)
    return reconnected if reconnected
    return :phone_number_taken if Channel::Whatsapp.exists?(phone_number: phone_info[:phone_number])

    commit_mapping do
      channel = create_channel_shell(waba_id, phone_info)
      inbox = create_inbox(channel, phone_info)
      Bloomwire::WhatsappCredentialWriter.new(channel: channel, attributes: { 'api_key' => token }).perform
      store_verification_pin(channel, verification_pin)
      create_mapping(channel, inbox, waba_id, phone_info, capability)
    end
  rescue ActiveRecord::RecordNotUnique
    :phone_number_taken
  end

  # Run a mapping write inside a DB transaction and translate the WhatsappSetupCreator::Result the block returns
  # into the persisted return value: the created/updated Bloomwire::WhatsappSetup on success, or a safe Symbol
  # error (with the whole write rolled back) on failure. Shared by the fresh-create and reconnect paths.
  def commit_mapping
    setup = nil
    error = nil
    ActiveRecord::Base.transaction(requires_new: true) do
      creator = yield
      if creator.success?
        setup = creator.setup
      else
        error = creator.error
        raise ActiveRecord::Rollback
      end
    end
    error || setup
  end

  # WhatsWay-parity reconnect + idempotency, scoped to THIS account (a phone_number_id owned by ANOTHER account is
  # never matched here and is failed closed by the caller / SetupCreator). Runs AFTER flow-specific Meta readiness,
  # so a previously-DISCONNECTED number is confirmed usable before we resume it. Returns:
  #   - the refreshed Bloomwire::WhatsappSetup when this account re-onboards the SAME number (same phone_number_id
  #     AND same phone): the long-lived token is refreshed and the mapping re-aligned on the EXISTING channel/inbox,
  #     so a browser retry or a reconnect never duplicates the Channel/Inbox/Setup;
  #   - :phone_number_id_conflict when this account re-uses the phone_number_id for a DIFFERENT phone (ADR-0009);
  #   - nil when this account has no (channel-backed) setup for this phone_number_id (caller does a fresh create).
  def reconnect_same_account_number(token, waba_id, phone_info, verification_pin, capability)
    setup = Bloomwire::WhatsappSetup.find_by(account_id: @account.id, phone_number_id: phone_info[:phone_number_id])
    return unless setup

    channel = setup.channel_whatsapp
    return unless channel
    return :phone_number_id_conflict unless same_number?(setup, phone_info[:phone_number])

    commit_mapping do
      Bloomwire::WhatsappCredentialWriter.new(channel: channel, attributes: { 'api_key' => token }).perform
      configure_reconnected_channel(channel)
      store_verification_pin(channel, verification_pin)
      create_mapping(channel, setup.inbox, waba_id, phone_info, capability)
    end
  end

  def configure_reconnected_channel(_channel); end

  # Same physical number => compare digits only (robust to +/formatting differences between the stored display
  # number and the freshly fetched phone_info).
  def same_number?(setup, phone_number)
    setup.display_phone_number.to_s.gsub(/\D/, '') == phone_number.to_s.gsub(/\D/, '')
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

  # A routeable (ready_for_webhook) mapping ONLY when outbound capability is confirmed; otherwise an explicit
  # Action-Required mapping (with a sanitized reason) the global router will not treat as ready — so we never
  # persist a silently receive-only inbox.
  def create_mapping(channel, inbox, waba_id, phone_info, capability)
    Bloomwire::WhatsappSetupCreator.call(
      account: @account,
      inbox: inbox,
      channel_whatsapp: channel,
      phone_number_id: phone_info[:phone_number_id],
      waba_id: waba_id,
      display_phone_number: phone_info[:phone_number],
      setup_status: capability.ready? ? Bloomwire::WhatsappSetup::ROUTEABLE_STATUS : Bloomwire::WhatsappSetup::ACTION_REQUIRED_STATUS,
      status_reason: capability.ready? ? nil : capability.reason
    )
  end
end
