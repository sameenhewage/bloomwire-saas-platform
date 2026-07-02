require 'rails_helper'

# Phase 17D.1: Coexistence service contract. ALL Meta calls are stubbed (no HTTP / no real Meta). Proves the
# service keeps the 17C.2 safe managed-signup boundary while making the connection mode explicit.
RSpec.describe Bloomwire::WhatsappCoexistenceEmbeddedSignupService do
  subject(:result) { described_class.new(account: account, params: params).perform }

  let(:account) { create(:account) }
  let(:params) { { code: 'META-CODE', business_id: 'BIZ-1', waba_id: 'WABA-1', phone_number_id: 'PNID-1' } }
  let(:phone_info) do
    { phone_number_id: 'PNID-1', phone_number: '+15551230001', verified: true, business_name: 'Acme' }
  end
  let(:fb_client) { instance_double(Whatsapp::FacebookApiClient) }

  def stub_ready(ready: true)
    allow(Bloomwire::GlobalWhatsappConfig).to receive(:new)
      .and_return(instance_double(Bloomwire::GlobalWhatsappConfig, result: { platform_ready: ready }))
  end

  def stub_meta(token: 'FAKE-CUSTOMER-TOKEN')
    allow(Whatsapp::TokenExchangeService).to receive(:new)
      .and_return(instance_double(Whatsapp::TokenExchangeService, perform: token))
    allow(Whatsapp::PhoneInfoService).to receive(:new)
      .and_return(instance_double(Whatsapp::PhoneInfoService, perform: phone_info))
    allow(fb_client).to receive_messages(subscribe_app_to_waba: true, override_waba_callback: nil,
                                         subscribe_waba_webhook: nil)
    allow(Whatsapp::FacebookApiClient).to receive(:new).and_return(fb_client)
  end

  describe 'happy path (Meta stubbed)' do
    before do
      stub_ready
      stub_meta
    end

    it 'creates a bloomwire_managed Cloud channel explicitly marked as coexistence' do
      expect { result }.to change(Channel::Whatsapp, :count).by(1)
      channel = Channel::Whatsapp.last

      aggregate_failures do
        expect(channel.provider).to eq('whatsapp_cloud')
        expect(channel.provider_config['source']).to eq('bloomwire_managed')
        expect(channel.provider_config['connection_mode']).to eq('coexistence')
        expect(channel.provider_config['api_key']).to eq('FAKE-CUSTOMER-TOKEN')
        expect(channel.provider_config['phone_number_id']).to eq('PNID-1')
      end
    end

    it 'returns a safe DTO with explicit coexistence mode and no secrets' do
      aggregate_failures do
        expect(result).to be_success
        expect(result.dto.dig(:channel, :source)).to eq('bloomwire_managed')
        expect(result.dto.dig(:channel, :connection_mode)).to eq('coexistence')
        expect(result.dto.dig(:setup, :connection_mode)).to eq('coexistence')
        expect(result.dto.to_json).not_to include('FAKE-CUSTOMER-TOKEN')
        expect(result.dto.to_json).not_to include('api_key')
        expect(result.dto.to_json).not_to include('provider_config')
      end
    end

    it 'creates a ready_for_webhook mapping the global router resolves' do
      result
      setup = Bloomwire::WhatsappSetup.last
      payload = bw_inbound_text_payload(phone_number_id: 'PNID-1', display_phone_number: '15551230001')

      aggregate_failures do
        expect(setup.setup_status).to eq('ready_for_webhook')
        expect(Bloomwire::Webhooks::WhatsappRouter.resolve_handoff_safe_setup(payload)&.id).to eq(setup.id)
      end
    end

    it 'uses the GLOBAL router app-to-WABA subscription and never per-channel webhook override' do
      result

      aggregate_failures do
        expect(fb_client).to have_received(:subscribe_app_to_waba).with('WABA-1')
        expect(fb_client).not_to have_received(:override_waba_callback)
        expect(fb_client).not_to have_received(:subscribe_waba_webhook)
      end
    end
  end

  describe 'fail-closed behavior inherited from the safe managed-signup seam' do
    it 'returns :not_ready and persists nothing when the platform is not ready' do
      stub_ready(ready: false)
      stub_meta

      aggregate_failures do
        expect(result.error).to eq(:not_ready)
        expect(Channel::Whatsapp.count).to eq(0)
        expect(Bloomwire::WhatsappSetup.count).to eq(0)
      end
    end

    it 'returns :encryption_not_configured outside dev/test and persists nothing' do
      stub_ready
      stub_meta
      allow(Chatwoot).to receive(:encryption_configured?).and_return(false)
      allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new('production'))

      aggregate_failures do
        expect(result.error).to eq(:encryption_not_configured)
        expect(Channel::Whatsapp.count).to eq(0)
        expect(Bloomwire::WhatsappSetup.count).to eq(0)
      end
    end
  end
end
