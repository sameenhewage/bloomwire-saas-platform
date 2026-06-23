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

  it 'is a channel-setup adapter (inherits the base default-no-op hook contract)' do
    expect(adapter).to be_a(Bloomwire::ChannelSetup::BaseAdapter)
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

    it 'translates a duplicate-phone race that slips past the pre-check into :duplicate_phone_number' do
      # Pre-check sees no existing channel, but a concurrent setup wins the race, so the
      # reused Chatwoot service raises; the rescue re-checks and finds the phone taken.
      # exists? is called: phone (pre) -> phone_number_id (pre) -> phone (rescue).
      creation = instance_double(Whatsapp::ChannelCreationService)
      allow(Whatsapp::ChannelCreationService).to receive(:new).and_return(creation)
      allow(creation).to receive(:perform).and_raise(RuntimeError, 'WhatsApp number already exists')
      allow(Channel::Whatsapp).to receive(:exists?).and_return(false, false, true)

      expect { adapter.create_channel(account: account, params: params) }
        .to raise_error(Bloomwire::ChannelSetup::SetupError) { |e| expect(e.code).to eq(:duplicate_phone_number) }
    end

    it 'rejects an existing WhatsApp phone_number_id (source of truth) with different phone formatting and no integration' do
      # A Channel::Whatsapp created via the still-enabled tenant path (no Bloomwire
      # integration) already uses this phone_number_id, under a differently formatted number.
      existing = create(:channel_whatsapp, account: create(:account), phone_number: '+1 (999) 000-1111',
                                           provider: 'whatsapp_cloud', validate_provider_config: false, sync_templates: false)
      dup_params = params.merge(phone_number: '+19990001111', phone_number_id: existing.provider_config['phone_number_id'])

      expect { adapter.create_channel(account: account, params: dup_params) }
        .to raise_error(Bloomwire::ChannelSetup::SetupError) { |e| expect(e.code).to eq(:duplicate_phone_number_id) }
    end
  end

  describe '#post_create!' do
    let(:channel) do
      instance_double(Channel::Whatsapp,
                      provider_config: { 'business_account_id' => 'waba-ad-001', 'api_key' => 'secret-key' })
    end

    it 'registers the webhook via WebhookSetupService (a failure-surfacing path, not the swallowing setup_webhooks)' do
      webhook = instance_double(Whatsapp::WebhookSetupService, perform: nil)
      allow(Whatsapp::WebhookSetupService).to receive(:new).and_return(webhook)

      adapter.post_create!(channel)

      expect(Whatsapp::WebhookSetupService).to have_received(:new).with(channel, 'waba-ad-001', 'secret-key')
      expect(webhook).to have_received(:perform)
    end

    it 'raises :webhook_setup_failed when provider registration fails (so setup never reports success)' do
      webhook = instance_double(Whatsapp::WebhookSetupService)
      allow(Whatsapp::WebhookSetupService).to receive(:new).and_return(webhook)
      allow(webhook).to receive(:perform).and_raise(RuntimeError, 'Webhook setup failed: Meta down')

      expect { adapter.post_create!(channel) }
        .to raise_error(Bloomwire::ChannelSetup::SetupError) { |e| expect(e.code).to eq(:webhook_setup_failed) }
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

  describe '#refresh_channel!' do
    let(:channel) { adapter.create_channel(account: account, params: params) }

    it 'merges corrected credentials into provider_config while preserving existing keys' do
      channel.update!(provider_config: channel.provider_config.merge('webhook_verify_token' => 'keep-me'))

      adapter.refresh_channel!(channel, params.merge(api_key: 'new-key', business_account_id: 'new-waba'))

      expect(channel.reload.provider_config).to include(
        'api_key' => 'new-key', 'business_account_id' => 'new-waba',
        'phone_number_id' => 'pnid-ad-001', 'webhook_verify_token' => 'keep-me'
      )
    end

    it 'never wipes existing config when the retry values are blank or missing' do
      original = channel.provider_config.dup

      adapter.refresh_channel!(channel, { api_key: '', business_account_id: nil })

      expect(channel.reload.provider_config).to eq(original)
    end
  end
end
