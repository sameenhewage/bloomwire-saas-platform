require 'rails_helper'

RSpec.describe Whatsapp::HealthService do
  subject(:health_status) { described_class.new(channel).fetch_health_status }

  let(:source) { nil }
  let(:provider_config) do
    {
      'api_key' => 'fake-access-token',
      'phone_number_id' => 'fake-phone-number-id',
      'source' => source
    }
  end
  let(:channel) do
    instance_double(
      Channel::Whatsapp,
      provider_config: provider_config,
      phone_number: '+15550000000'
    )
  end
  let(:graph_response) do
    instance_double(
      HTTParty::Response,
      success?: true,
      parsed_response: {
        'id' => 'fake-phone-number-id',
        'webhook_configuration' => webhook_configuration
      }
    )
  end
  let(:webhook_configuration) { {} }

  before do
    allow(GlobalConfigService).to receive(:load)
      .with('WHATSAPP_API_VERSION', Whatsapp::GraphApi::DEFAULT_VERSION)
      .and_return('v25.0')
    allow(HTTParty).to receive(:get).and_return(graph_response)
  end

  context 'with a Bloomwire-managed channel' do
    let(:source) { 'bloomwire_managed' }
    let(:managed_callback_url) { 'https://chat.example.com/bloomwire/webhooks/whatsapp' }
    let(:webhook_configuration) { { 'application' => managed_callback_url } }
    let(:global_config) do
      instance_double(
        Bloomwire::GlobalWhatsappConfig,
        result: { callback_url: managed_callback_url }
      )
    end

    before do
      allow(Bloomwire::GlobalWhatsappConfig).to receive(:new).and_return(global_config)
    end

    it 'uses the global router callback as the expected webhook URL' do
      with_modified_env FRONTEND_URL: 'https://chat.example.com' do
        expect(health_status[:expected_webhook_url]).to eq(managed_callback_url)
        expect(health_status[:webhook_configuration]['application']).to eq(health_status[:expected_webhook_url])
      end
    end
  end

  context 'with a stock manually configured channel' do
    it 'keeps the native per-phone callback as the expected webhook URL' do
      expect(Bloomwire::GlobalWhatsappConfig).not_to receive(:new)

      with_modified_env FRONTEND_URL: 'https://chat.example.com' do
        expect(health_status[:expected_webhook_url]).to eq(
          'https://chat.example.com/webhooks/whatsapp/+15550000000'
        )
      end
    end
  end

  context 'with a native Chatwoot Embedded Signup channel' do
    let(:source) { 'embedded_signup' }

    it 'keeps the native per-phone callback as the expected webhook URL' do
      expect(Bloomwire::GlobalWhatsappConfig).not_to receive(:new)

      with_modified_env FRONTEND_URL: 'https://chat.example.com' do
        expect(health_status[:expected_webhook_url]).to eq(
          'https://chat.example.com/webhooks/whatsapp/+15550000000'
        )
      end
    end
  end
end
