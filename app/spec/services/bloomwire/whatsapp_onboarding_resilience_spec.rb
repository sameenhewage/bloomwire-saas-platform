require 'rails_helper'

# Onboarding resilience contract (the Rack::Timeout split-state fix). Proves the Standard Embedded Signup is
# idempotent/resumable so a Meta side effect that completes AFTER a request timed out never yields a split state
# (Meta CONNECTED / subscribed but 0 Bloomwire records) that a retry cannot safely finish — and never a duplicate
# Channel/Inbox/Setup. ALL Meta calls are stubbed (no HTTP). Fake values only. Deliberately a focused resilience
# spec kept separate from the large whatsapp_embedded_signup_service_spec.rb.
RSpec.describe Bloomwire::WhatsappEmbeddedSignupService do # rubocop:disable RSpec/SpecFilePathFormat
  subject(:result) { described_class.new(account: account, params: params).perform }

  let(:account) { create(:account) }
  let(:params) { { code: 'META-CODE', business_id: 'BIZ-1', waba_id: 'WABA-1', phone_number_id: 'PNID-1' } }
  let(:phone_info) do
    { phone_number_id: 'PNID-1', phone_number: '+15551230001', verified: true, business_name: 'Acme' }
  end
  let(:fb_client) { instance_double(Whatsapp::FacebookApiClient) }

  before do
    allow(Bloomwire::GlobalWhatsappConfig).to receive(:new)
      .and_return(instance_double(Bloomwire::GlobalWhatsappConfig, result: { platform_ready: true }))
    allow(Whatsapp::TokenExchangeService).to receive(:new)
      .and_return(instance_double(Whatsapp::TokenExchangeService, perform: 'SHORT-TOKEN'))
    allow(Whatsapp::PhoneInfoService).to receive(:new)
      .and_return(instance_double(Whatsapp::PhoneInfoService, perform: phone_info))
    allow(fb_client).to receive_messages(
      exchange_for_long_lived_token: 'LONG-LIVED-TOKEN', subscribe_app_to_waba: { 'success' => true },
      register_phone_number: { 'success' => true },
      messaging_waba_ids: [], waba_registrations: [], waba_owner_business_id: nil
    )
    allow(Whatsapp::FacebookApiClient).to receive(:new).and_return(fb_client)
    allow(Bloomwire::WhatsappMessagingCapability).to receive(:new).and_return(
      instance_double(Bloomwire::WhatsappMessagingCapability,
                      ensure: Bloomwire::WhatsappMessagingCapability::Result.new(status: :ready, reason: nil))
    )
    # Default world: a fresh number is not yet subscribed until this flow subscribes it.
    allow(fb_client).to receive(:subscribed_to_waba?).and_return(false, true)
  end

  def counts
    { channels: Channel::Whatsapp.where(account: account).count,
      inboxes: account.inboxes.count,
      setups: Bloomwire::WhatsappSetup.where(account: account).count }
  end

  describe 'in-request recovery when Meta /register connected the number but our READ timed out' do
    before do
      allow(fb_client).to receive(:phone_number_status).and_return('DISCONNECTED', 'CONNECTED')
      allow(fb_client).to receive(:register_phone_number)
        .and_raise(Whatsapp::GraphApiTimeoutError, 'Graph API POST timed out (Net::ReadTimeout)')
    end

    it 'recovers within the SAME request (re-checks status -> CONNECTED) and persists exactly one set of records' do
      aggregate_failures do
        expect(result).to be_success
        expect(fb_client).to have_received(:register_phone_number).with('PNID-1', anything).once
        expect(counts).to eq(channels: 1, inboxes: 1, setups: 1)
      end
    end
  end

  describe 'retry after a prior attempt /register-ed the number but persisted nothing (split-state)' do
    before { allow(fb_client).to receive(:phone_number_status).and_return('CONNECTED') }

    it 'sees CONNECTED, skips /register, and completes with exactly one Channel/Inbox/Setup' do
      aggregate_failures do
        expect(result).to be_success
        expect(fb_client).not_to have_received(:register_phone_number)
        expect(counts).to eq(channels: 1, inboxes: 1, setups: 1)
      end
    end
  end

  describe 'retry after a prior attempt subscribed the app but persisted nothing' do
    before do
      allow(fb_client).to receive(:phone_number_status).and_return('CONNECTED')
      allow(fb_client).to receive(:subscribed_to_waba?).and_return(true) # already subscribed on Meta
    end

    it 'skips the subscribe POST (already subscribed) and still persists the inbox' do
      aggregate_failures do
        expect(result).to be_success
        expect(fb_client).not_to have_received(:subscribe_app_to_waba)
        expect(counts).to eq(channels: 1, inboxes: 1, setups: 1)
      end
    end
  end

  describe 'repeated retries are convergent' do
    before do
      allow(fb_client).to receive(:phone_number_status).and_return('CONNECTED')
      allow(fb_client).to receive(:subscribed_to_waba?).and_return(true)
    end

    it 'creates EXACTLY one Channel, one Inbox and one Setup across three retries' do
      3.times { described_class.new(account: account, params: params).perform }
      expect(counts).to eq(channels: 1, inboxes: 1, setups: 1)
    end
  end

  describe 'a Meta call that times out fails safely (no partial records)' do
    before do
      allow(fb_client).to receive(:phone_number_status)
        .and_raise(Whatsapp::GraphApiTimeoutError, 'Graph API GET timed out (Net::OpenTimeout)')
    end

    it 'returns :meta_error and persists nothing' do
      aggregate_failures do
        expect(result.error).to eq(:meta_error)
        expect(counts).to eq(channels: 0, inboxes: 0, setups: 0)
      end
    end
  end

  describe 'fast path (already CONNECTED, fresh subscribe) still succeeds without leaking secrets' do
    before { allow(fb_client).to receive(:phone_number_status).and_return('CONNECTED') }

    it 'succeeds and never exposes the stored token in the DTO' do
      aggregate_failures do
        expect(result).to be_success
        expect(result.dto.to_json).not_to include('LONG-LIVED-TOKEN')
        expect(counts).to eq(channels: 1, inboxes: 1, setups: 1)
      end
    end
  end
end
