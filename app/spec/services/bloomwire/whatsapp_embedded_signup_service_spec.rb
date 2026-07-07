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
                                         subscribe_waba_webhook: nil, register_phone_number: { 'success' => true },
                                         phone_number_status: 'CONNECTED',
                                         messaging_waba_ids: [], waba_registrations: [], waba_owner_business_id: nil)
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
        expect(channel.provider_config['connection_mode']).to eq('standard')
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

    it 'registers the number on Cloud API with a 6-digit PIN (so Meta connects it for inbound)' do
      result
      expect(fb_client).to have_received(:register_phone_number).with('PNID-1', /\A\d{6}\z/)
    end

    it 'persists the generated 2FA PIN in provider_config (so a later re-register cannot lock the number out)' do
      result
      expect(Channel::Whatsapp.last.provider_config['verification_pin']).to match(/\A\d{6}\z/)
    end
  end

  # Phase 17E.2 — a DISCONNECTED selection is not an immediate dead end: the same number may be CONNECTED as a
  # duplicate under another WABA the token can message. The safe root fix routes to that single same-business
  # registration (so inbound/outbound use the LIVE phone_number_id), or fails closed. All lookups stubbed.
  describe 'auto-resolves a DISCONNECTED selection to the single CONNECTED same-business registration' do
    before do
      stub_ready
      stub_meta
      allow(fb_client).to receive(:phone_number_status).and_return('DISCONNECTED')
      allow(fb_client).to receive(:messaging_waba_ids).and_return(%w[WABA-1 WABA-CONNECTED])
      allow(fb_client).to receive(:waba_registrations).with('WABA-1')
        .and_return([{ 'id' => 'PNID-1', 'display_phone_number' => '+15551230001', 'status' => 'DISCONNECTED' }])
      # Same number, different formatting, CONNECTED under a sibling WABA owned by the same business.
      allow(fb_client).to receive(:waba_registrations).with('WABA-CONNECTED')
        .and_return([{ 'id' => 'PNID-CONN', 'display_phone_number' => '+1 555 123 0001', 'status' => 'CONNECTED' }])
      allow(fb_client).to receive(:waba_owner_business_id).and_return('BIZ-OWNER')
    end

    it 'persists the channel + setup on the CONNECTED phone_number_id / WABA (not the disconnected selection)' do
      expect(result).to be_success
      channel = Channel::Whatsapp.last
      setup = Bloomwire::WhatsappSetup.last
      aggregate_failures do
        expect(channel.provider_config['phone_number_id']).to eq('PNID-CONN')
        expect(channel.provider_config['business_account_id']).to eq('WABA-CONNECTED')
        expect(setup.phone_number_id).to eq('PNID-CONN')
      end
    end

    it 'routes an inbound webhook carrying the CONNECTED phone_number_id to the created inbox' do
      result
      setup = Bloomwire::WhatsappSetup.last
      payload = bw_inbound_text_payload(phone_number_id: 'PNID-CONN', display_phone_number: '15551230001')
      expect(Bloomwire::Webhooks::WhatsappRouter.resolve_handoff_safe_setup(payload)&.id).to eq(setup.id)
    end
  end

  describe 'fails closed when a DISCONNECTED number cannot be safely resolved (creates nothing)' do
    before do
      stub_ready
      stub_meta
      allow(fb_client).to receive(:phone_number_status).and_return('DISCONNECTED')
    end

    it 'returns :no_connected_registration when no connected duplicate exists (even if /register was rejected)' do
      allow(fb_client).to receive(:register_phone_number).and_raise(StandardError, 'RAW (#100) owner-permission error')
      allow(fb_client).to receive(:messaging_waba_ids).and_return(%w[WABA-1])
      allow(fb_client).to receive(:waba_registrations).with('WABA-1')
        .and_return([{ 'id' => 'PNID-1', 'display_phone_number' => '+15551230001', 'status' => 'DISCONNECTED' }])
      aggregate_failures do
        expect(result.error).to eq(:no_connected_registration)
        expect(Channel::Whatsapp.count).to eq(0)
        expect(account.inboxes.count).to eq(0)
      end
    end

    it 'returns :ambiguous_connected_registration when the number is CONNECTED on two WABAs' do
      allow(fb_client).to receive(:messaging_waba_ids).and_return(%w[WABA-A WABA-B])
      allow(fb_client).to receive(:waba_registrations).with('WABA-A')
        .and_return([{ 'id' => 'PNID-A', 'display_phone_number' => '+15551230001', 'status' => 'CONNECTED' }])
      allow(fb_client).to receive(:waba_registrations).with('WABA-B')
        .and_return([{ 'id' => 'PNID-B', 'display_phone_number' => '+15551230001', 'status' => 'CONNECTED' }])
      aggregate_failures do
        expect(result.error).to eq(:ambiguous_connected_registration)
        expect(Channel::Whatsapp.count).to eq(0)
      end
    end

    it 'returns :cross_business_registration when the only connected match is a different business' do
      allow(fb_client).to receive(:messaging_waba_ids).and_return(%w[WABA-1 WABA-OTHER])
      allow(fb_client).to receive(:waba_registrations).with('WABA-1')
        .and_return([{ 'id' => 'PNID-1', 'display_phone_number' => '+15551230001', 'status' => 'DISCONNECTED' }])
      allow(fb_client).to receive(:waba_registrations).with('WABA-OTHER')
        .and_return([{ 'id' => 'PNID-X', 'display_phone_number' => '+15551230001', 'status' => 'CONNECTED' }])
      allow(fb_client).to receive(:waba_owner_business_id).with('WABA-1').and_return('BIZ-1')
      allow(fb_client).to receive(:waba_owner_business_id).with('WABA-OTHER').and_return('BIZ-2')
      aggregate_failures do
        expect(result.error).to eq(:cross_business_registration)
        expect(Channel::Whatsapp.count).to eq(0)
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
        .and_return(instance_double(Whatsapp::FacebookApiClient, subscribe_app_to_waba: true, register_phone_number: { 'success' => true },
                                                                 override_waba_callback: nil, subscribe_waba_webhook: nil,
                                                                 phone_number_status: 'CONNECTED'))
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
