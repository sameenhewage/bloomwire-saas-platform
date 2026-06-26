require 'rails_helper'

# Phase 10A.1: a SuperAdmin/Ops readiness calculator that reports whether a Bloomwire WhatsApp real-hop
# inbound test is ready or blocked, WITHOUT calling Meta and WITHOUT ever returning secret values. It only
# reports configured/missing for secrets and masks phone identifiers. Fake values only.
RSpec.describe Bloomwire::WhatsappRealHopReadiness do
  let(:account) { create(:account) }
  let(:app_secret) { 'FAKE-APP-SECRET-DO-NOT-LEAK' }
  let(:verify_token) { 'FAKE-VERIFY-TOKEN-DO-NOT-LEAK' }
  let(:api_key) { 'FAKE-PROVIDER-API-KEY-DO-NOT-LEAK' }
  let(:pnid) { 'FAKE-PNID-7777' }
  let(:display) { '15551230077' }

  def set_cfg(key, value)
    config = InstallationConfig.where(name: key).first_or_initialize
    config.value = value
    config.locked = false
    config.save!
    GlobalConfig.clear_cache
  end

  def enable_all_config
    set_cfg('BLOOMWIRE_MODE_ENABLED', true)
    set_cfg('BLOOMWIRE_PRIVACY_HARDENING', true)
    set_cfg('BLOOMWIRE_GLOBAL_WEBHOOK_ROUTER', true)
    set_cfg('WHATSAPP_APP_SECRET', app_secret)
    set_cfg('BLOOMWIRE_WHATSAPP_GLOBAL_VERIFY_TOKEN', verify_token)
    set_cfg('BLOOMWIRE_WHATSAPP_PUBLIC_CALLBACK_HOST', 'smoke.example.com')
  end

  def aligned_channel
    channel = create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud',
                                        phone_number: "+#{display}", sync_templates: false,
                                        validate_provider_config: false)
    channel.update!(provider_config: channel.provider_config.merge('phone_number_id' => pnid,
                                                                   'source' => 'embedded_signup', 'api_key' => api_key))
    channel
  end

  def ready_setup
    channel = aligned_channel
    create(:bloomwire_whatsapp_setup, account: account, inbox: channel.inbox, channel_whatsapp: channel,
                                      phone_number_id: pnid, display_phone_number: display, setup_status: 'ready_for_webhook')
  end

  def check(result, key)
    result[:checks].find { |c| c[:key] == key.to_s }
  end

  before { GlobalConfig.clear_cache }

  describe 'fully aligned + configured' do
    it 'returns ready with every check passing' do
      enable_all_config
      result = described_class.new(ready_setup).result
      expect(result[:status]).to eq('ready')
      expect(result[:checks].map { |c| c[:status] }.uniq).to eq(['pass'])
      expect(result[:callback_path]).to eq('/bloomwire/webhooks/whatsapp')
    end

    it 'reports both readiness sub-summaries true' do
      enable_all_config
      result = described_class.new(ready_setup).result
      expect(result[:ready_for_inbound_mapping]).to be(true)
      expect(result[:ready_for_get_verification_config]).to be(true)
    end
  end

  describe 'feature toggles' do
    it 'is blocked when Bloomwire mode is OFF' do
      enable_all_config
      setup = ready_setup
      set_cfg('BLOOMWIRE_MODE_ENABLED', false)
      result = described_class.new(setup).result
      expect(result[:status]).to eq('blocked')
      expect(check(result, :bloomwire_mode_enabled)[:status]).to eq('blocked')
    end

    it 'is blocked when privacy hardening is OFF' do
      enable_all_config
      setup = ready_setup
      set_cfg('BLOOMWIRE_PRIVACY_HARDENING', false)
      result = described_class.new(setup).result
      expect(result[:status]).to eq('blocked')
      expect(check(result, :privacy_hardening_enabled)[:status]).to eq('blocked')
    end

    it 'is blocked when the global webhook router is OFF' do
      enable_all_config
      setup = ready_setup
      set_cfg('BLOOMWIRE_GLOBAL_WEBHOOK_ROUTER', false)
      result = described_class.new(setup).result
      expect(result[:status]).to eq('blocked')
      expect(check(result, :global_webhook_router_enabled)[:status]).to eq('blocked')
    end
  end

  describe 'secrets / config' do
    it 'is blocked when WHATSAPP_APP_SECRET is missing' do
      enable_all_config
      setup = ready_setup
      set_cfg('WHATSAPP_APP_SECRET', nil)
      result = described_class.new(setup).result
      expect(result[:status]).to eq('blocked')
      expect(check(result, :app_secret_configured)[:status]).to eq('blocked')
    end

    it 'is blocked when BLOOMWIRE_WHATSAPP_GLOBAL_VERIFY_TOKEN is missing' do
      enable_all_config
      setup = ready_setup
      set_cfg('BLOOMWIRE_WHATSAPP_GLOBAL_VERIFY_TOKEN', nil)
      result = described_class.new(setup).result
      expect(result[:status]).to eq('blocked')
      expect(check(result, :global_verify_token_configured)[:status]).to eq('blocked')
    end

    it 'is blocked when the public callback host is not documented' do
      enable_all_config
      setup = ready_setup
      set_cfg('BLOOMWIRE_WHATSAPP_PUBLIC_CALLBACK_HOST', nil)
      result = described_class.new(setup).result
      expect(check(result, :public_callback_host_configured)[:status]).to eq('blocked')
      expect(result[:ready_for_inbound_mapping]).to be(true)
    end

    it 'is blocked when the public callback host includes a scheme or path' do
      enable_all_config
      setup = ready_setup
      set_cfg('BLOOMWIRE_WHATSAPP_PUBLIC_CALLBACK_HOST', 'https://smoke.example.com/path')
      result = described_class.new(setup).result
      expect(check(result, :public_callback_host_configured)[:status]).to eq('blocked')
      expect(result[:ready_for_get_verification_config]).to be(false)
      expect(result[:callback_url]).to be_nil
    end
  end

  describe 'setup mapping' do
    it 'is blocked when no setup is given' do
      enable_all_config
      result = described_class.new(nil).result
      expect(result[:status]).to eq('blocked')
      expect(check(result, :setup_present)[:status]).to eq('blocked')
    end

    it 'is blocked when the setup is not ready_for_webhook' do
      enable_all_config
      setup = ready_setup
      setup.update_column(:setup_status, 'configured') # rubocop:disable Rails/SkipsModelValidations
      result = described_class.new(setup).result
      expect(result[:status]).to eq('blocked')
      expect(check(result, :setup_ready_for_webhook)[:status]).to eq('blocked')
    end

    it 'is blocked when phone_number_id is missing' do
      enable_all_config
      setup = ready_setup
      setup.update_columns(phone_number_id: nil, setup_status: 'configured') # rubocop:disable Rails/SkipsModelValidations
      result = described_class.new(setup).result
      expect(result[:status]).to eq('blocked')
      expect(check(result, :setup_phone_number_id_present)[:status]).to eq('blocked')
    end

    it 'is blocked when inbox/channel are missing' do
      enable_all_config
      setup = create(:bloomwire_whatsapp_setup, account: account, setup_status: 'configured', phone_number_id: pnid)
      result = described_class.new(setup).result
      expect(result[:status]).to eq('blocked')
      expect(check(result, :setup_inbox_present)[:status]).to eq('blocked')
      expect(check(result, :setup_channel_present)[:status]).to eq('blocked')
    end

    it 'is blocked when account/inbox/channel are inconsistent' do
      enable_all_config
      setup = ready_setup
      other_account = create(:account)
      other_channel = create(:channel_whatsapp, account: other_account, provider: 'whatsapp_cloud',
                                                sync_templates: false, validate_provider_config: false)
      # force an inconsistent state past validations
      setup.update_columns(channel_whatsapp_id: other_channel.id) # rubocop:disable Rails/SkipsModelValidations
      result = described_class.new(setup.reload).result
      expect(result[:status]).to eq('blocked')
      expect(check(result, :channel_belongs_to_account)[:status]).to eq('blocked')
    end
  end

  describe 'channel alignment' do
    it 'is blocked when channel provider_config phone_number_id mismatches the setup' do
      enable_all_config
      setup = ready_setup
      setup.channel_whatsapp.update!(provider_config: setup.channel_whatsapp.provider_config.merge('phone_number_id' => 'OTHER-PNID'))
      result = described_class.new(setup.reload).result
      expect(result[:status]).to eq('blocked')
      expect(check(result, :channel_provider_config_phone_number_id_matches)[:status]).to eq('blocked')
      expect(check(result, :router_handoff_safe)[:status]).to eq('blocked')
    end

    it 'is blocked when the channel phone_number is missing' do
      enable_all_config
      setup = ready_setup
      # phone_number is NOT NULL at the DB; a blank value is the "missing" representation the check guards.
      setup.channel_whatsapp.update_columns(phone_number: '') # rubocop:disable Rails/SkipsModelValidations
      result = described_class.new(setup.reload).result
      expect(result[:status]).to eq('blocked')
      expect(check(result, :channel_phone_number_present)[:status]).to eq('blocked')
    end
  end

  describe 'secret hygiene + masking' do
    it 'never includes secret values anywhere in the result payload' do
      enable_all_config
      result = described_class.new(ready_setup).result
      dump = result.inspect
      expect(dump).not_to include(app_secret)
      expect(dump).not_to include(verify_token)
      expect(dump).not_to include(api_key)
    end

    it 'masks the phone_number_id and channel phone number' do
      enable_all_config
      result = described_class.new(ready_setup).result
      dump = result.inspect
      expect(dump).not_to include(pnid)
      expect(dump).not_to include("+#{display}")
      expect(result[:masked][:phone_number_id]).to include('****')
    end
  end
end
