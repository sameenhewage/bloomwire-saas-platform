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
    allow(fb_client).to receive_messages(subscribe_app_to_waba: true, register_phone_number: { 'success' => true }, override_waba_callback: nil,
                                         subscribe_waba_webhook: nil, phone_number_status: 'CONNECTED')
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

    it 'never calls the Standard Cloud API /register (coexistence numbers are already registered)' do
      result

      expect(fb_client).not_to have_received(:register_phone_number)
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

    it 'returns :number_not_connected and persists nothing when the coexistence number is DISCONNECTED' do
      stub_ready
      stub_meta
      allow(fb_client).to receive(:phone_number_status).and_return('DISCONNECTED')

      aggregate_failures do
        expect(result.error).to eq(:number_not_connected)
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

  # Phase 17E.1 — multiple Coexistence WhatsApp inboxes per account (ADR-0009). Coexistence inherits the safe
  # standard persistence, so two different numbers become two distinct channels/inboxes/setups (both marked
  # connection_mode=coexistence); duplicate phone_number / phone_number_id stays blocked. All Meta stubbed.
  describe 'multiple Coexistence inboxes per account (Phase 17E.1 contract)' do
    before { stub_ready }

    def coexistence_signup(phone_number_id:, phone_number:, waba_id: 'WABA-1', token: 'FAKE-CUSTOMER-TOKEN')
      allow(Whatsapp::TokenExchangeService).to receive(:new)
        .and_return(instance_double(Whatsapp::TokenExchangeService, perform: token))
      allow(Whatsapp::PhoneInfoService).to receive(:new)
        .and_return(instance_double(Whatsapp::PhoneInfoService,
                                    perform: { phone_number_id: phone_number_id, phone_number: phone_number,
                                               verified: true, business_name: 'Acme' }))
      allow(Whatsapp::FacebookApiClient).to receive(:new)
        .and_return(instance_double(Whatsapp::FacebookApiClient, subscribe_app_to_waba: true, register_phone_number: { 'success' => true },
                                                                 override_waba_callback: nil, subscribe_waba_webhook: nil,
                                                                 phone_number_status: 'CONNECTED'))
      described_class.new(account: account,
                          params: { code: 'META-CODE', business_id: 'BIZ-1', waba_id: waba_id,
                                    phone_number_id: phone_number_id }).perform
    end

    it 'creates two distinct coexistence channels + inboxes + setups for the same account (connection_mode stays coexistence)' do
      r1 = coexistence_signup(phone_number_id: 'PNID-1', phone_number: '+15551230001', waba_id: 'WABA-1')
      r2 = coexistence_signup(phone_number_id: 'PNID-2', phone_number: '+15551230002', waba_id: 'WABA-2')

      channels = Channel::Whatsapp.where(account: account)
      aggregate_failures do
        expect(r1).to be_success
        expect(r2).to be_success
        expect(account.inboxes.count).to eq(2)
        expect(channels.count).to eq(2)
        expect(Bloomwire::WhatsappSetup.where(account: account).count).to eq(2)
        expect(channels.map { |c| c.provider_config['connection_mode'] }).to all(eq('coexistence'))
        expect(r1.dto.dig(:channel, :connection_mode)).to eq('coexistence')
        expect(r2.dto.dig(:channel, :connection_mode)).to eq('coexistence')
      end
    end

    it 'routes each coexistence number to its own inbox' do
      coexistence_signup(phone_number_id: 'PNID-1', phone_number: '+15551230001')
      coexistence_signup(phone_number_id: 'PNID-2', phone_number: '+15551230002')
      setup1 = Bloomwire::WhatsappSetup.find_by(phone_number_id: 'PNID-1')
      setup2 = Bloomwire::WhatsappSetup.find_by(phone_number_id: 'PNID-2')
      payload1 = bw_inbound_text_payload(phone_number_id: 'PNID-1', display_phone_number: '15551230001')
      payload2 = bw_inbound_text_payload(phone_number_id: 'PNID-2', display_phone_number: '15551230002')
      aggregate_failures do
        expect(Bloomwire::Webhooks::WhatsappRouter.resolve_handoff_safe_setup(payload1)&.inbox_id).to eq(setup1.inbox_id)
        expect(Bloomwire::Webhooks::WhatsappRouter.resolve_handoff_safe_setup(payload2)&.inbox_id).to eq(setup2.inbox_id)
      end
    end

    it 'still blocks a duplicate phone_number' do
      coexistence_signup(phone_number_id: 'PNID-1', phone_number: '+15551230001')
      dup = coexistence_signup(phone_number_id: 'PNID-2', phone_number: '+15551230001')
      aggregate_failures do
        expect(dup.error).to eq(:phone_number_taken)
        expect(Bloomwire::WhatsappSetup.where(account: account).count).to eq(1)
      end
    end

    it 'still blocks a duplicate phone_number_id' do
      coexistence_signup(phone_number_id: 'PNID-1', phone_number: '+15551230001')
      dup = coexistence_signup(phone_number_id: 'PNID-1', phone_number: '+15551230002')
      aggregate_failures do
        expect(dup.error).to eq(:phone_number_id_conflict)
        expect(Channel::Whatsapp.where(account: account).count).to eq(1)
      end
    end
  end
end
