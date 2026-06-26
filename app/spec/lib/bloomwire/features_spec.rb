require 'rails_helper'

RSpec.describe Bloomwire::Features do
  before { GlobalConfig.clear_cache }

  # Set an InstallationConfig-backed toggle and clear the cache so the next read is fresh.
  def set_toggle(key, value)
    config = InstallationConfig.where(name: key).first_or_initialize
    config.value = value
    config.locked = false
    config.save!
    GlobalConfig.clear_cache
  end

  describe 'defaults' do
    it 'defaults the master toggle OFF when nothing is configured' do
      expect(described_class.enabled?(:mode)).to be(false)
      expect(described_class.master_enabled?).to be(false)
    end

    it 'defaults every sub-feature OFF when nothing is configured' do
      described_class::SUB_FEATURES.each_key do |feature|
        expect(described_class.enabled?(feature)).to be(false)
      end
    end
  end

  describe 'master AND-gate' do
    before do
      set_toggle(described_class::MASTER, false)
      # store every sub-feature ON (incl. privacy hardening) so only the gate can hold them OFF
      described_class::SUB_FEATURES.each_value { |key| set_toggle(key, true) }
    end

    it 'forces every sub-feature OFF while master is OFF, even when stored ON' do
      described_class::SUB_FEATURES.each_key do |feature|
        expect(described_class.enabled?(feature)).to be(false)
      end
    end

    it 'still exposes the raw stored value via raw_enabled? (for the bootstrap UI)' do
      expect(described_class.raw_enabled?(:privacy_hardening)).to be(true)
    end
  end

  describe 'master ON' do
    before { set_toggle(described_class::MASTER, true) }

    it 'reports :mode enabled' do
      expect(described_class.enabled?(:mode)).to be(true)
    end

    it 'allows a non-managed sub-feature to follow its stored value' do
      set_toggle('BLOOMWIRE_RESTRICT_NATIVE_WHATSAPP_SETUP', true)
      expect(described_class.enabled?(:restrict_native_whatsapp_setup)).to be(true)

      set_toggle('BLOOMWIRE_RESTRICT_NATIVE_WHATSAPP_SETUP', false)
      expect(described_class.enabled?(:restrict_native_whatsapp_setup)).to be(false)
    end
  end

  describe 'privacy-hardening prerequisite for managed-data toggles' do
    before do
      set_toggle(described_class::MASTER, true)
      set_toggle('BLOOMWIRE_MANAGED_WHATSAPP_ONBOARDING', true)
      set_toggle('BLOOMWIRE_GLOBAL_WEBHOOK_ROUTER', true)
    end

    it 'keeps managed-data toggles OFF while privacy hardening is OFF (fail-closed)' do
      set_toggle('BLOOMWIRE_PRIVACY_HARDENING', false)
      expect(described_class.enabled?(:managed_whatsapp_onboarding)).to be(false)
      expect(described_class.enabled?(:global_webhook_router)).to be(false)
    end

    it 'allows managed-data toggles once privacy hardening is ON' do
      set_toggle('BLOOMWIRE_PRIVACY_HARDENING', true)
      expect(described_class.enabled?(:managed_whatsapp_onboarding)).to be(true)
      expect(described_class.enabled?(:global_webhook_router)).to be(true)
    end
  end

  describe 'unknown feature' do
    it 'raises ArgumentError' do
      expect { described_class.enabled?(:not_a_real_feature) }.to raise_error(ArgumentError)
    end
  end

  # The global WhatsApp webhook verify token is a sensitive secret and must follow the Phase 2A masking
  # contract on SuperAdmin surfaces (masked + no-wipe) once privacy hardening is effectively ON.
  describe 'global WhatsApp webhook verify token is a masked secret' do
    it 'is registered as a masked secret key' do
      expect(described_class::MASKED_SECRET_KEYS).to include('BLOOMWIRE_WHATSAPP_GLOBAL_VERIFY_TOKEN')
    end

    it 'is masked when master + privacy hardening are ON' do
      set_toggle(described_class::MASTER, true)
      set_toggle('BLOOMWIRE_PRIVACY_HARDENING', true)
      expect(described_class.masked_secret_key?('BLOOMWIRE_WHATSAPP_GLOBAL_VERIFY_TOKEN')).to be(true)
    end

    it 'is not masked while privacy hardening is OFF (stock SuperAdmin behavior)' do
      set_toggle(described_class::MASTER, true)
      set_toggle('BLOOMWIRE_PRIVACY_HARDENING', false)
      expect(described_class.masked_secret_key?('BLOOMWIRE_WHATSAPP_GLOBAL_VERIFY_TOKEN')).to be(false)
    end
  end

  # Feature-OFF regression contract: OFF == stock Chatwoot (nothing activates).
  describe 'feature-OFF regression (OFF = stock Chatwoot)' do
    it 'reports nothing enabled when the whole layer is OFF (fresh install)' do
      expect(described_class.enabled?(:mode)).to be(false)
      described_class::SUB_FEATURES.each_key do |feature|
        expect(described_class.enabled?(feature)).to be(false)
      end
    end

    it 'cannot activate any sub-feature without the master, so OFF is the rollback switch' do
      described_class::SUB_FEATURES.each_value { |key| set_toggle(key, true) }
      set_toggle(described_class::MASTER, false)
      described_class::SUB_FEATURES.each_key do |feature|
        expect(described_class.enabled?(feature)).to be(false)
      end
    end
  end
end
