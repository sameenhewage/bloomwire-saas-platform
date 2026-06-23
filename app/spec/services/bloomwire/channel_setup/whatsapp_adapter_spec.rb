require 'rails_helper'

# WhatsApp Cloud adapter for the generic channel-setup orchestrator. It isolates
# all WhatsApp-specific credential/routing extraction (Meta phone_number_id,
# business_account_id, api_key) so the orchestrator and the integration model
# stay channel-agnostic. This is the first adapter; SMS/Email/etc. add their own.
RSpec.describe Bloomwire::ChannelSetup::WhatsappAdapter do
  subject(:adapter) { described_class.new }

  let(:account) { create(:account) }
  let(:params) do
    {
      phone_number: '+15557770001',
      phone_number_id: 'pnid-ad-001',
      business_account_id: 'waba-ad-001',
      api_key: 'secret-key',
      business_name: 'Adapter Co'
    }
  end

  before do
    teardown = instance_double(Whatsapp::WebhookTeardownService, perform: nil)
    allow(Whatsapp::WebhookTeardownService).to receive(:new).and_return(teardown)
    setup = instance_double(Whatsapp::WebhookSetupService, perform: nil)
    allow(Whatsapp::WebhookSetupService).to receive(:new).and_return(setup)
    allow(Channel::Whatsapp).to receive(:new).and_wrap_original do |method, *args|
      channel = method.call(*args)
      allow(channel).to receive(:validate_provider_config)
      allow(channel).to receive(:sync_templates)
      channel
    end
  end

  it 'identifies as the whatsapp app_kind' do
    expect(adapter.app_kind).to eq('whatsapp')
  end

  it 'derives the routing key from the WhatsApp phone_number_id' do
    expect(adapter.routing_key(params)).to eq('pnid-ad-001')
  end

  describe '#create_channel' do
    it 'creates a whatsapp_cloud channel with an inbox via Whatsapp::ChannelCreationService' do
      channel = adapter.create_channel(account: account, params: params)
      expect(channel).to be_a(Channel::Whatsapp)
      expect(channel.provider).to eq('whatsapp_cloud')
      expect(channel.inbox).to be_present
    end

    it 'raises a coded SetupError when a required credential is missing' do
      expect { adapter.create_channel(account: account, params: params.except(:api_key)) }
        .to raise_error(Bloomwire::ChannelSetup::SetupError) { |e| expect(e.code).to eq(:invalid_channel_params) }
    end

    it 'raises a coded SetupError when the phone number already exists' do
      create(:channel_whatsapp, account: create(:account), phone_number: '+15557770001',
                                provider: 'whatsapp_cloud', validate_provider_config: false, sync_templates: false)
      expect { adapter.create_channel(account: account, params: params) }
        .to raise_error(Bloomwire::ChannelSetup::SetupError) { |e| expect(e.code).to eq(:duplicate_phone_number) }
    end
  end

  describe '#integration_attributes' do
    it 'extracts only non-secret routing metadata from the channel' do
      channel = adapter.create_channel(account: account, params: params)

      expect(adapter.integration_attributes(channel)).to eq(
        provider: 'whatsapp_cloud',
        phone_number: '+15557770001',
        phone_number_id: 'pnid-ad-001',
        business_account_id: 'waba-ad-001',
        routing_key: 'pnid-ad-001'
      )
    end

    it 'never returns provider secrets' do
      channel = adapter.create_channel(account: account, params: params)
      expect(adapter.integration_attributes(channel).keys).not_to include(:api_key, :provider_config)
    end
  end
end
