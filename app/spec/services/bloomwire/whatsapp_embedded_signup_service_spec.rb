require 'rails_helper'

# Phase 17C.2: dedicated Bloomwire customer WhatsApp Embedded Signup. ALL Meta calls are stubbed (no HTTP / no
# real Meta). Proves: bloomwire_managed Cloud channel + inbox + ready_for_webhook mapping created; token stored
# ONLY in encrypted provider_config; global-router app-to-WABA subscription used (never per-channel webhook /
# override); safe DTO with no secrets; fail-closed preflight (not-ready / encryption) before any token storage;
# sanitized Meta errors persist nothing. Fake values only.
RSpec.describe Bloomwire::WhatsappEmbeddedSignupService do
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

    it 'succeeds with a safe DTO that never contains the token/api_key' do
      aggregate_failures do
        expect(result).to be_success
        expect(result.dto.to_json).not_to include('FAKE-CUSTOMER-TOKEN')
        expect(result.dto.to_json).not_to include('api_key')
        expect(result.dto.dig(:channel, :source)).to eq('bloomwire_managed')
        expect(result.dto.dig(:setup, :status)).to eq('ready_for_webhook')
      end
    end

    it 'creates a bloomwire_managed Cloud channel with the token only in provider_config' do
      expect { result }.to change(Channel::Whatsapp, :count).by(1)
      channel = Channel::Whatsapp.last
      aggregate_failures do
        expect(channel.provider).to eq('whatsapp_cloud')
        expect(channel.provider_config['source']).to eq('bloomwire_managed')
        expect(channel.provider_config['api_key']).to eq('FAKE-CUSTOMER-TOKEN')
        expect(channel.provider_config['phone_number_id']).to eq('PNID-1')
      end
    end

    it 'creates an inbox for the account' do
      expect { result }.to change(account.inboxes, :count).by(1)
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

    it 'uses the GLOBAL router (app-to-WABA subscribe) and never a per-channel webhook/override' do
      result
      aggregate_failures do
        expect(fb_client).to have_received(:subscribe_app_to_waba).with('WABA-1')
        expect(fb_client).not_to have_received(:override_waba_callback)
        expect(fb_client).not_to have_received(:subscribe_waba_webhook)
      end
    end
  end

  describe 'fail-closed preflight (before any Meta call / token storage)' do
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
      end
    end

    it 'returns :missing_code when the code is absent' do
      stub_ready
      described = described_class.new(account: account, params: params.merge(code: '')).perform
      expect(described.error).to eq(:missing_code)
    end
  end

  describe 'sanitized Meta failure' do
    it 'returns a generic :meta_error and persists nothing (no raw payload leaked)' do
      stub_ready
      failing = instance_double(Whatsapp::TokenExchangeService)
      allow(failing).to receive(:perform).and_raise(StandardError, 'RAW-META-BODY-WITH-TOKEN')
      allow(Whatsapp::TokenExchangeService).to receive(:new).and_return(failing)
      aggregate_failures do
        expect(result.error).to eq(:meta_error)
        expect(result.dto).to be_nil
        expect(Channel::Whatsapp.count).to eq(0)
        expect(Bloomwire::WhatsappSetup.count).to eq(0)
      end
    end
  end

  # Phase 17E.1 — multiple WhatsApp inboxes per account (ADR-0009). One account can register several numbers;
  # each distinct phone_number / phone_number_id becomes its own channel + inbox + mapping. Duplicate
  # phone_number / phone_number_id stays globally blocked. All Meta calls stubbed per-number (no real Meta).
  describe 'multiple WhatsApp inboxes per account (Phase 17E.1 contract)' do
    before { stub_ready }

    # Run the managed signup for ONE specific number, with Meta fully stubbed for this call.
    def signup(phone_number_id:, phone_number:, waba_id: 'WABA-1', token: 'FAKE-CUSTOMER-TOKEN')
      allow(Whatsapp::TokenExchangeService).to receive(:new)
        .and_return(instance_double(Whatsapp::TokenExchangeService, perform: token))
      allow(Whatsapp::PhoneInfoService).to receive(:new)
        .and_return(instance_double(Whatsapp::PhoneInfoService,
                                    perform: { phone_number_id: phone_number_id, phone_number: phone_number,
                                               verified: true, business_name: 'Acme' }))
      allow(Whatsapp::FacebookApiClient).to receive(:new)
        .and_return(instance_double(Whatsapp::FacebookApiClient, subscribe_app_to_waba: true,
                                                                 override_waba_callback: nil, subscribe_waba_webhook: nil))
      described_class.new(account: account,
                          params: { code: 'META-CODE', business_id: 'BIZ-1', waba_id: waba_id,
                                    phone_number_id: phone_number_id }).perform
    end

    it 'creates two distinct channels + inboxes + setups for two different numbers, all under the same account' do
      r1 = signup(phone_number_id: 'PNID-1', phone_number: '+15551230001', waba_id: 'WABA-1')
      r2 = signup(phone_number_id: 'PNID-2', phone_number: '+15551230002', waba_id: 'WABA-2')

      setup1 = Bloomwire::WhatsappSetup.find_by(phone_number_id: 'PNID-1')
      setup2 = Bloomwire::WhatsappSetup.find_by(phone_number_id: 'PNID-2')
      aggregate_failures do
        expect(r1).to be_success
        expect(r2).to be_success
        expect(account.inboxes.count).to eq(2)
        expect(Channel::Whatsapp.where(account: account).count).to eq(2)
        expect(Bloomwire::WhatsappSetup.where(account: account).count).to eq(2)
        expect(setup1.account_id).to eq(account.id)
        expect(setup2.account_id).to eq(account.id)
        expect(setup1.channel_whatsapp_id).not_to eq(setup2.channel_whatsapp_id)
        expect(setup1.inbox_id).not_to eq(setup2.inbox_id)
      end
    end

    it 'routes each number to its own inbox (no overwrite of the first)' do
      signup(phone_number_id: 'PNID-1', phone_number: '+15551230001')
      signup(phone_number_id: 'PNID-2', phone_number: '+15551230002')
      setup1 = Bloomwire::WhatsappSetup.find_by(phone_number_id: 'PNID-1')
      setup2 = Bloomwire::WhatsappSetup.find_by(phone_number_id: 'PNID-2')
      payload1 = bw_inbound_text_payload(phone_number_id: 'PNID-1', display_phone_number: '15551230001')
      payload2 = bw_inbound_text_payload(phone_number_id: 'PNID-2', display_phone_number: '15551230002')
      aggregate_failures do
        expect(Bloomwire::Webhooks::WhatsappRouter.resolve_handoff_safe_setup(payload1)&.inbox_id).to eq(setup1.inbox_id)
        expect(Bloomwire::Webhooks::WhatsappRouter.resolve_handoff_safe_setup(payload2)&.inbox_id).to eq(setup2.inbox_id)
      end
    end

    it 'blocks a duplicate phone_number (second signup reuses the first number) and creates no second inbox' do
      signup(phone_number_id: 'PNID-1', phone_number: '+15551230001')
      dup = signup(phone_number_id: 'PNID-2', phone_number: '+15551230001')
      aggregate_failures do
        expect(dup).not_to be_success
        expect(dup.error).to eq(:phone_number_taken)
        expect(account.inboxes.count).to eq(1)
        expect(Bloomwire::WhatsappSetup.where(account: account).count).to eq(1)
      end
    end

    it 'blocks a duplicate phone_number_id claimed by another channel (rolls back the second channel)' do
      signup(phone_number_id: 'PNID-1', phone_number: '+15551230001')
      dup = signup(phone_number_id: 'PNID-1', phone_number: '+15551230002')
      aggregate_failures do
        expect(dup).not_to be_success
        expect(dup.error).to eq(:phone_number_id_conflict)
        expect(Channel::Whatsapp.where(account: account).count).to eq(1)
        expect(Bloomwire::WhatsappSetup.where(account: account).count).to eq(1)
      end
    end
  end
end
