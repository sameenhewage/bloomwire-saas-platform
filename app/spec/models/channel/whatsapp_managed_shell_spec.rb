require 'rails_helper'

# Phase 14 S3 — Channel::Whatsapp "managed shell" guards: a credential-less whatsapp_cloud channel (created by
# Ops provisioning before the api_key is entered via the S2 page) must never make a Meta call on create or on
# template sync, and must not auto-register the native per-channel webhook. Channels with an api_key are
# unchanged. Fake values only. (Channels WITH an api_key are only built, not saved, to avoid the real
# after_create sync that those legitimately trigger.)
RSpec.describe Channel::Whatsapp do
  let(:account) { create(:account) }

  def build_channel(api_key: nil, source: 'bloomwire_managed')
    config = { 'phone_number_id' => 'PNID-X', 'business_account_id' => 'WABA-X', 'source' => source }
    config['api_key'] = api_key if api_key
    described_class.new(account: account, phone_number: "+#{SecureRandom.random_number(10**12)}",
                        provider: 'whatsapp_cloud', provider_config: config)
  end

  describe '#sync_templates guard' do
    it 'does not touch the provider service (no Meta) when api_key is blank' do
      channel = build_channel(api_key: nil)
      expect(channel).not_to receive(:provider_service)
      channel.sync_templates
    end

    it 'delegates to the provider service when api_key is present' do
      channel = build_channel(api_key: 'tok')
      fake = instance_double(Whatsapp::Providers::WhatsappCloudService, sync_templates: true)
      allow(channel).to receive(:provider_service).and_return(fake)
      channel.sync_templates
      expect(fake).to have_received(:sync_templates)
    end
  end

  describe '#should_auto_setup_webhooks?' do
    it 'is false for a bloomwire_managed shell' do
      expect(build_channel(source: 'bloomwire_managed').send(:should_auto_setup_webhooks?)).to be(false)
    end

    it 'is false for embedded_signup (unchanged)' do
      expect(build_channel(source: 'embedded_signup', api_key: 'tok').send(:should_auto_setup_webhooks?)).to be(false)
    end

    it 'is true for a manual cloud channel with another source (unchanged)' do
      expect(build_channel(source: 'manual', api_key: 'tok').send(:should_auto_setup_webhooks?)).to be(true)
    end
  end

  describe 'creating a credential-less shell' do
    it 'persists with no graph.facebook.com call on create (after_create sync + webhook setup skipped)' do
      channel = build_channel(api_key: nil)
      expect { channel.save!(validate: false) }.not_to raise_error
      expect(channel).to be_persisted
      expect(a_request(:any, /graph\.facebook\.com/)).not_to have_been_made
    end
  end
end
