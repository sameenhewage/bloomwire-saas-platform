# Phase 10A.1: read-only readiness calculator for a Bloomwire WhatsApp real-hop inbound test. Given a
# Bloomwire::WhatsappSetup it reports, as a structured + secret-free result, whether every prerequisite for
# a real Meta inbound webhook test is satisfied (feature toggles, configured secrets, a consistent mapping,
# channel alignment that the global router would actually hand off, and a documented public callback host).
#
# It NEVER calls Meta and NEVER returns secret values: secrets are reported only as configured/missing, and
# phone identifiers are masked. It is consumed by the SuperAdmin-only readiness console. Stores nothing.
class Bloomwire::WhatsappRealHopReadiness
  CALLBACK_PATH = '/bloomwire/webhooks/whatsapp'.freeze
  APP_SECRET_KEY = 'WHATSAPP_APP_SECRET'.freeze
  VERIFY_TOKEN_KEY = 'BLOOMWIRE_WHATSAPP_GLOBAL_VERIFY_TOKEN'.freeze
  PUBLIC_HOST_KEY = 'BLOOMWIRE_WHATSAPP_PUBLIC_CALLBACK_HOST'.freeze

  # Checks that gate the inbound POST path (Meta -> router -> existing job).
  INBOUND_KEYS = %w[
    bloomwire_mode_enabled privacy_hardening_enabled global_webhook_router_enabled app_secret_configured
    setup_present setup_ready_for_webhook setup_phone_number_id_present setup_account_present
    setup_inbox_present setup_channel_present inbox_belongs_to_account channel_belongs_to_account
    inbox_matches_channel channel_provider_whatsapp_cloud channel_phone_number_present
    channel_provider_config_phone_number_id_matches router_handoff_safe
  ].freeze

  # Checks that gate configuring + verifying the Meta webhook callback (GET verification).
  GET_CONFIG_KEYS = %w[
    bloomwire_mode_enabled privacy_hardening_enabled global_webhook_router_enabled
    global_verify_token_configured public_callback_host_configured
  ].freeze

  def self.for(setup: nil, setup_id: nil, channel_id: nil)
    setup ||= Bloomwire::WhatsappSetup.find_by(id: setup_id) if setup_id.present?
    setup ||= Bloomwire::WhatsappSetup.find_by(channel_whatsapp_id: channel_id) if channel_id.present?
    new(setup)
  end

  def initialize(setup)
    @setup = setup
  end

  def result
    checks = feature_toggle_checks + secret_checks + setup_presence_checks + setup_consistency_checks +
             channel_alignment_checks + [callback_host_check]
    {
      status: checks.any? { |c| c[:status] == 'blocked' } ? 'blocked' : 'ready',
      ready_for_inbound_mapping: subset_pass?(checks, INBOUND_KEYS),
      ready_for_get_verification_config: subset_pass?(checks, GET_CONFIG_KEYS),
      checks: checks,
      callback_path: CALLBACK_PATH,
      callback_url: callback_url,
      public_callback_host_configured: public_host.present?,
      masked: masked_identifiers
    }
  end

  private

  attr_reader :setup

  def channel
    setup&.channel_whatsapp
  end

  def check(key, group, passed, message)
    { key: key.to_s, group: group.to_s, status: passed ? 'pass' : 'blocked', message: passed ? nil : message }
  end

  def feature_toggle_checks
    [
      check(:bloomwire_mode_enabled, :feature_toggles, Bloomwire::Features.master_enabled?, 'BLOOMWIRE_MODE_ENABLED is OFF'),
      check(:privacy_hardening_enabled, :feature_toggles, Bloomwire::Features.raw_enabled?(:privacy_hardening), 'BLOOMWIRE_PRIVACY_HARDENING is OFF'),
      check(:global_webhook_router_enabled, :feature_toggles,
            Bloomwire::Features.raw_enabled?(:global_webhook_router), 'BLOOMWIRE_GLOBAL_WEBHOOK_ROUTER is OFF')
    ]
  end

  def secret_checks
    [
      check(:app_secret_configured, :secrets_config, config_present?(APP_SECRET_KEY), 'WHATSAPP_APP_SECRET is missing'),
      check(:global_verify_token_configured, :secrets_config, config_present?(VERIFY_TOKEN_KEY), 'BLOOMWIRE_WHATSAPP_GLOBAL_VERIFY_TOKEN is missing')
    ]
  end

  def setup_presence_checks
    [
      check(:setup_present, :setup_mapping, setup.present?, 'No Bloomwire::WhatsappSetup selected/found'),
      check(:setup_ready_for_webhook, :setup_mapping, setup&.setup_status == 'ready_for_webhook', "Setup status is not 'ready_for_webhook'"),
      check(:setup_phone_number_id_present, :setup_mapping, setup&.phone_number_id.present?, 'Setup phone_number_id is missing'),
      check(:setup_account_present, :setup_mapping, setup&.account_id.present?, 'Setup has no account'),
      check(:setup_inbox_present, :setup_mapping, setup&.inbox_id.present?, 'Setup has no inbox'),
      check(:setup_channel_present, :setup_mapping, setup&.channel_whatsapp_id.present?, 'Setup has no WhatsApp channel')
    ]
  end

  def setup_consistency_checks
    [
      check(:inbox_belongs_to_account, :setup_mapping, inbox_belongs_to_account?, 'Setup inbox does not belong to the setup account'),
      check(:channel_belongs_to_account, :setup_mapping, channel_belongs_to_account?, 'Setup channel does not belong to the setup account'),
      check(:inbox_matches_channel, :setup_mapping, inbox_matches_channel?, "Setup inbox is not the WhatsApp channel's own inbox")
    ]
  end

  def channel_alignment_checks
    [
      check(:channel_provider_whatsapp_cloud, :channel_alignment, channel&.provider == 'whatsapp_cloud', "Channel provider is not 'whatsapp_cloud'"),
      check(:channel_phone_number_present, :channel_alignment, channel&.phone_number.present?, 'Channel phone_number is missing'),
      check(:channel_provider_config_phone_number_id_matches, :channel_alignment, provider_config_pnid_matches?,
            'Channel provider_config phone_number_id does not match the setup phone_number_id'),
      check(:router_handoff_safe, :channel_alignment, router_handoff_safe?,
            'The global router would not hand off this payload (fix mapping/alignment above first)')
    ]
  end

  def callback_host_check
    check(:public_callback_host_configured, :callback_url, public_host.present?,
          "No public HTTPS callback host documented (set #{PUBLIC_HOST_KEY})")
  end

  # Consistency predicates: when the referenced record is absent the dedicated presence check carries the
  # signal, so these pass (vacuously) to avoid a confusing duplicate "does not belong" message.
  def inbox_belongs_to_account?
    return true if setup&.inbox_id.blank? || setup&.account_id.blank?

    setup.inbox&.account_id == setup.account_id
  end

  def channel_belongs_to_account?
    return true if setup&.channel_whatsapp_id.blank? || setup&.account_id.blank?

    channel&.account_id == setup.account_id
  end

  def inbox_matches_channel?
    return true if setup.blank? || setup.inbox_id.blank? || setup.channel_whatsapp_id.blank?

    inbox = setup.inbox
    inbox.present? && inbox.channel_type == 'Channel::Whatsapp' && inbox.channel_id == setup.channel_whatsapp_id
  end

  def provider_config_pnid_matches?
    return false if channel.blank? || setup&.phone_number_id.blank?

    channel.provider_config.to_h['phone_number_id'] == setup.phone_number_id
  end

  # Holistic check: would the existing global router actually hand off a real aligned payload for this mapping?
  # Built from the channel's own phone number + the setup's phone_number_id (what Meta would send).
  def router_handoff_safe?
    return false if setup.blank? || channel&.phone_number.blank? || setup.phone_number_id.blank?

    Bloomwire::Webhooks::WhatsappRouter.resolve_handoff_safe_setup(sample_payload)&.id == setup.id
  end

  def sample_payload
    {
      'entry' => [{
        'changes' => [{
          'value' => { 'metadata' => {
            'display_phone_number' => channel.phone_number.to_s.delete_prefix('+'),
            'phone_number_id' => setup.phone_number_id
          } }
        }]
      }]
    }
  end

  def subset_pass?(checks, keys)
    keys.all? { |k| checks.find { |c| c[:key] == k }&.fetch(:status) == 'pass' }
  end

  def config_present?(key)
    GlobalConfigService.load(key, nil).present?
  end

  def public_host
    GlobalConfigService.load(PUBLIC_HOST_KEY, nil).presence
  end

  def callback_url
    public_host.present? ? "https://#{public_host}#{CALLBACK_PATH}" : nil
  end

  def masked_identifiers
    {
      phone_number_id: mask_tail(setup&.phone_number_id),
      channel_phone_number: mask_phone(channel&.phone_number),
      display_phone_number: mask_tail(setup&.display_phone_number)
    }
  end

  def mask_tail(value)
    value.blank? ? '—' : "****#{value.to_s.last(4)}"
  end

  def mask_phone(value)
    value.blank? ? '—' : "+****#{value.to_s.delete_prefix('+').last(4)}"
  end
end
