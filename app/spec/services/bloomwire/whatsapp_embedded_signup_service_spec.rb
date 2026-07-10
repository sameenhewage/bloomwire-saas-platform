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
    stub_fb_client
    stub_messaging_capability
  end

  # Meta client stub for the managed flow (extracted so stub_meta stays within RuboCop's AbcSize budget).
  def stub_fb_client
    allow(fb_client).to receive_messages(subscribe_app_to_waba: true,
                                         override_waba_callback: nil, subscribe_waba_webhook: nil,
                                         register_phone_number: { 'success' => true }, messaging_waba_ids: [],
                                         waba_registrations: [], waba_owner_business_id: nil)
    # Idempotent subscribe: a fresh number is NOT yet subscribed (this flow subscribes it) and is verified subscribed
    # afterwards; a retry that finds it ALREADY subscribed skips the subscribe POST (see subscribe_final_waba).
    allow(fb_client).to receive(:subscribed_to_waba?).and_return(false, true)
    # Default (fresh number): DISCONNECTED before Bloomwire registers it, then CONNECTED afterwards. Blocks that
    # need a different lifecycle (already-CONNECTED, or never-CONNECTED) override :phone_number_status themselves.
    allow(fb_client).to receive(:phone_number_status).and_return('DISCONNECTED', 'CONNECTED')
    # The managed flow extends the short-lived signup token to a long-lived one before storing it (WhatsWay
    # parity); the identity stub keeps the stored api_key equal to the exchanged token unless a case overrides it.
    allow(fb_client).to receive(:exchange_for_long_lived_token) { |short| short }
    allow(Whatsapp::FacebookApiClient).to receive(:new).and_return(fb_client)
  end

  # The outbound capability gate is unit-tested in bloomwire/whatsapp_messaging_capability_spec.rb; here it
  # defaults to READY so the flow reaches ready_for_webhook. The Action-Required wiring overrides this.
  def stub_messaging_capability(status: :ready, reason: nil)
    allow(Bloomwire::WhatsappMessagingCapability).to receive(:new).and_return(
      instance_double(Bloomwire::WhatsappMessagingCapability,
                      ensure: Bloomwire::WhatsappMessagingCapability::Result.new(status: status, reason: reason))
    )
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

    it 'uses the GLOBAL router (app-to-WABA subscribe) exactly once and never a per-channel webhook/override' do
      result
      aggregate_failures do
        # Same-WABA path (the selected number is CONNECTED): the final WABA equals the selection, so exactly one
        # subscription call is made — no duplicate.
        expect(fb_client).to have_received(:subscribe_app_to_waba).with('WABA-1').once
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

  # Phase 4 (recovery) — when the customer's SELECTED number is ALREADY CONNECTED on the Cloud API (e.g. an
  # owner-admin connected it out-of-band), Bloomwire must NOT re-register it: re-sending /register with a fresh
  # 2FA PIN against a live, pin-enabled number is unnecessary and can disrupt the owner-set PIN. The number is
  # persisted on the SELECTED WABA + phone_number_id (no substitution), with no Bloomwire-generated PIN.
  describe 'skips /register when the selected number is already CONNECTED' do
    before do
      stub_ready
      stub_meta
      allow(fb_client).to receive(:phone_number_status).and_return('CONNECTED')
    end

    it 'does NOT call /register but still persists channel/inbox/setup on the SELECTED WABA + phone_number_id' do
      aggregate_failures do
        expect(result).to be_success
        expect(fb_client).not_to have_received(:register_phone_number)
        channel = Channel::Whatsapp.last
        expect(channel.provider_config['phone_number_id']).to eq('PNID-1')
        expect(channel.provider_config['business_account_id']).to eq('WABA-1')
        expect(Bloomwire::WhatsappSetup.last.phone_number_id).to eq('PNID-1')
      end
    end

    it 'stores no Bloomwire-generated verification PIN (the owner-set PIN is left untouched)' do
      result
      expect(Channel::Whatsapp.last.provider_config['verification_pin']).to be_nil
    end

    it 'subscribes the Bloomwire app to the SELECTED WABA exactly once (no resolver, no substitution)' do
      result
      aggregate_failures do
        expect(fb_client).to have_received(:subscribe_app_to_waba).with('WABA-1').once
        expect(fb_client).not_to have_received(:messaging_waba_ids)
      end
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
                                                      .and_return([{ 'id' => 'PNID-1', 'display_phone_number' => '+15551230001',
                                                                     'status' => 'DISCONNECTED' }])
      # Same number, different formatting, CONNECTED under a sibling WABA owned by the same business.
      allow(fb_client).to receive(:waba_registrations).with('WABA-CONNECTED')
                                                      .and_return([{ 'id' => 'PNID-CONN', 'display_phone_number' => '+1 555 123 0001',
                                                                     'status' => 'CONNECTED' }])
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

    it 'subscribes the Bloomwire app to the RESOLVED WABA (WABA-CONNECTED), not the disconnected selection' do
      result
      aggregate_failures do
        expect(fb_client).to have_received(:subscribe_app_to_waba).with('WABA-CONNECTED')
        expect(fb_client).not_to have_received(:subscribe_app_to_waba).with('WABA-1')
      end
    end
  end

  # The resolved WABA must be subscribed to the Bloomwire app BEFORE any DB write; if Meta rejects that
  # subscription the whole onboarding fails closed (a resolved inbox that never receives inbound is worse than none).
  describe 'fails closed when subscribing the RESOLVED WABA is rejected (creates nothing)' do
    before do
      stub_ready
      stub_meta
      allow(fb_client).to receive(:phone_number_status).and_return('DISCONNECTED')
      allow(fb_client).to receive(:messaging_waba_ids).and_return(%w[WABA-1 WABA-CONNECTED])
      allow(fb_client).to receive(:waba_registrations).with('WABA-1')
                                                      .and_return([{ 'id' => 'PNID-1', 'display_phone_number' => '+15551230001',
                                                                     'status' => 'DISCONNECTED' }])
      allow(fb_client).to receive(:waba_registrations).with('WABA-CONNECTED')
                                                      .and_return([{ 'id' => 'PNID-CONN', 'display_phone_number' => '+15551230001',
                                                                     'status' => 'CONNECTED' }])
      allow(fb_client).to receive(:waba_owner_business_id).and_return('BIZ-OWNER')
      allow(fb_client).to receive(:subscribe_app_to_waba).with('WABA-CONNECTED').and_raise(StandardError, 'RAW subscribe error')
    end

    it 'returns :subscription_failed and creates no channel, inbox, credentials, or setup' do
      aggregate_failures do
        expect(result.error).to eq(:subscription_failed)
        expect(Channel::Whatsapp.count).to eq(0)
        expect(account.inboxes.count).to eq(0)
        expect(Bloomwire::WhatsappSetup.count).to eq(0)
      end
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
                                                      .and_return([{ 'id' => 'PNID-1', 'display_phone_number' => '+15551230001',
                                                                     'status' => 'DISCONNECTED' }])
      aggregate_failures do
        expect(result.error).to eq(:no_connected_registration)
        expect(Channel::Whatsapp.count).to eq(0)
        expect(account.inboxes.count).to eq(0)
      end
    end

    it 'returns :ambiguous_connected_registration when the number is CONNECTED on two WABAs' do
      allow(fb_client).to receive(:messaging_waba_ids).and_return(%w[WABA-A WABA-B])
      allow(fb_client).to receive(:waba_registrations).with('WABA-A')
                                                      .and_return([{ 'id' => 'PNID-A', 'display_phone_number' => '+15551230001',
                                                                     'status' => 'CONNECTED' }])
      allow(fb_client).to receive(:waba_registrations).with('WABA-B')
                                                      .and_return([{ 'id' => 'PNID-B', 'display_phone_number' => '+15551230001',
                                                                     'status' => 'CONNECTED' }])
      aggregate_failures do
        expect(result.error).to eq(:ambiguous_connected_registration)
        expect(Channel::Whatsapp.count).to eq(0)
      end
    end

    it 'returns :cross_business_registration when the only connected match is a different business' do
      allow(fb_client).to receive(:messaging_waba_ids).and_return(%w[WABA-1 WABA-OTHER])
      allow(fb_client).to receive(:waba_registrations).with('WABA-1')
                                                      .and_return([{ 'id' => 'PNID-1', 'display_phone_number' => '+15551230001',
                                                                     'status' => 'DISCONNECTED' }])
      allow(fb_client).to receive(:waba_registrations).with('WABA-OTHER')
                                                      .and_return([{ 'id' => 'PNID-X', 'display_phone_number' => '+15551230001',
                                                                     'status' => 'CONNECTED' }])
      allow(fb_client).to receive(:waba_owner_business_id).with('WABA-1').and_return('BIZ-1')
      allow(fb_client).to receive(:waba_owner_business_id).with('WABA-OTHER').and_return('BIZ-2')
      aggregate_failures do
        expect(result.error).to eq(:cross_business_registration)
        expect(Channel::Whatsapp.count).to eq(0)
      end
    end
  end

  # Phase 17F — sanitized observability for a rejected Cloud API /register. The failure stays non-fatal (number
  # remains DISCONNECTED, gate refuses to persist) but the SPECIFIC Meta error is now recorded via the structured
  # `bloomwire.whatsapp.phone_registration_failed` event — with NO token / PIN / OAuth code / auth header / raw body.
  describe 'sanitized phone registration failure observability' do
    subject(:run) { described_class.new(account: account, params: params).perform }

    let(:raw_body_sentinel) { 'RAW_BODY_SENTINEL_MUST_NOT_BE_LOGGED' }
    let(:meta_error_body) do
      { error: { message: '(#100) The number is registered on another WABA', type: 'OAuthException', code: 100,
                 error_subcode: 2_388_004, is_transient: false, fbtrace_id: 'SAFE_TRACE_ID',
                 error_data: { detail: raw_body_sentinel } } }.to_json
    end
    let(:graph_error) do
      Whatsapp::GraphApiError.from_response('Phone registration failed',
                                            instance_double(HTTParty::Response, body: meta_error_body, code: 400))
    end
    let(:warn_logs) { [] }

    before do
      stub_ready
      stub_meta
      allow(SecureRandom).to receive(:random_number).with(1_000_000).and_return(42) # deterministic PIN => '000042'
      allow(fb_client).to receive(:register_phone_number).and_raise(graph_error)
      allow(fb_client).to receive(:phone_number_status).and_return('DISCONNECTED')
      allow(fb_client).to receive(:messaging_waba_ids).and_return(%w[WABA-1])
      allow(fb_client).to receive(:waba_registrations).with('WABA-1')
                                                      .and_return([{ 'id' => 'PNID-1', 'display_phone_number' => '+15551230001',
                                                                     'status' => 'DISCONNECTED' }])
      allow(Rails.logger).to receive(:warn) { |msg| warn_logs << msg }
    end

    def registration_event
      warn_logs.find { |m| m.include?('bloomwire.whatsapp.phone_registration_failed') }
    end

    it 'logs the sanitized structured Meta error fields (status/code/subcode/type/is_transient/fbtrace_id/message)' do
      run
      payload = JSON.parse(registration_event.sub('[BLOOMWIRE EMBEDDED SIGNUP] ', ''))
      aggregate_failures do
        expect(payload['event']).to eq('bloomwire.whatsapp.phone_registration_failed')
        expect(payload['operation']).to eq('phone_registration')
        expect(payload['phone_number_id']).to eq('PNID-1')
        expect(payload['exception_class']).to eq('Whatsapp::GraphApiError')
        expect(payload['http_status']).to eq(400)
        expect(payload['meta_error_code']).to eq(100)
        expect(payload['meta_error_subcode']).to eq(2_388_004)
        expect(payload['meta_error_type']).to eq('OAuthException')
        expect(payload['is_transient']).to be(false)
        expect(payload['fbtrace_id']).to eq('SAFE_TRACE_ID')
        expect(payload['meta_error_message']).to include('registered on another WABA')
      end
    end

    it 'never logs the token, PIN, OAuth code, Authorization header, request body, or raw response body' do
      run
      log = registration_event
      aggregate_failures do
        expect(log).not_to include('FAKE-CUSTOMER-TOKEN') # access token
        expect(log).not_to include('000042')              # generated 2FA PIN
        expect(log).not_to include('META-CODE')           # OAuth code
        expect(log).not_to match(/Bearer|Authorization/)  # auth header
        expect(log).not_to include('messaging_product')   # raw request body
        expect(log).not_to include(raw_body_sentinel)     # raw response body detail
        expect(log).not_to include(meta_error_body)       # whole raw response body
      end
    end

    it 'keeps the failure non-fatal: fails closed with :no_connected_registration and persists nothing' do
      aggregate_failures do
        expect(run.error).to eq(:no_connected_registration)
        expect(Channel::Whatsapp.count).to eq(0)
        expect(account.inboxes.count).to eq(0)
        expect(Bloomwire::WhatsappSetup.count).to eq(0)
      end
    end
  end

  # Existing-number 2SV PIN: a number that was registered before already carries a Meta two-step-verification PIN,
  # so Bloomwire must re-register it with that KNOWN pin (stored-encrypted, else securely-configured) instead of a
  # fresh random one — which Meta rejects with #133005. When no correct pin is available, fail CLOSED (never a
  # silent random retry, never a partial record). The pin is a secret: never in a log or the DTO. Fake values only.
  describe 'existing-number registration PIN (avoids Meta #133005)' do
    let(:existing_pins_env) { 'BLOOMWIRE_WHATSAPP_EXISTING_REGISTRATION_PINS' }

    def pin_mismatch_error
      body = { error: { message: '(#133005) Two step verification PIN Mismatch', type: 'OAuthException',
                        code: 133_005, fbtrace_id: 'SAFE_TRACE_ID' } }.to_json
      Whatsapp::GraphApiError.from_response('Phone registration failed',
                                            instance_double(HTTParty::Response, body: body, code: 400))
    end

    before do
      stub_ready
      stub_meta
    end

    it 'registers with the securely-configured existing PIN (never a random one) and stores it encrypted' do
      with_modified_env(existing_pins_env => { 'PNID-1' => '654321' }.to_json) do
        aggregate_failures do
          expect(result).to be_success
          expect(fb_client).to have_received(:register_phone_number).with('PNID-1', '654321')
          expect(Channel::Whatsapp.last.provider_config['verification_pin']).to eq('654321')
          expect(result.dto.to_json).not_to include('654321')
        end
      end
    end

    it 'reuses the stored encrypted PIN on reconnect (no new random PIN, same single records)' do
      with_modified_env(existing_pins_env => { 'PNID-1' => '654321' }.to_json) do
        expect(result).to be_success # first onboard: DISCONNECTED -> register('654321') -> CONNECTED, stores it
      end
      expect(Channel::Whatsapp.last.provider_config['verification_pin']).to eq('654321')

      # Reconnect WITHOUT the env configured — proves the PIN now comes from encrypted storage, not the env.
      allow(fb_client).to receive(:phone_number_status).and_return('DISCONNECTED', 'CONNECTED')
      again = described_class.new(account: account, params: params).perform
      aggregate_failures do
        expect(again).to be_success
        expect(fb_client).to have_received(:register_phone_number).with('PNID-1', '654321').twice
        expect(Channel::Whatsapp.where(account: account).count).to eq(1)
        expect(Bloomwire::WhatsappSetup.where(account: account).count).to eq(1)
      end
    end

    it 'fails closed with :registration_pin_required (persists nothing) when Meta rejects a known PIN with #133005' do
      with_modified_env(existing_pins_env => { 'PNID-1' => '654321' }.to_json) do
        allow(fb_client).to receive(:register_phone_number).and_raise(pin_mismatch_error)
        allow(fb_client).to receive(:phone_number_status).and_return('DISCONNECTED')
        aggregate_failures do
          expect(result.error).to eq(:registration_pin_required)
          expect(Channel::Whatsapp.count).to eq(0)
          expect(account.inboxes.count).to eq(0)
          expect(Bloomwire::WhatsappSetup.count).to eq(0)
        end
      end
    end

    it 'fails closed with :registration_pin_required for a new number on #133005 (no silent random retry)' do
      allow(fb_client).to receive(:register_phone_number).and_raise(pin_mismatch_error)
      allow(fb_client).to receive(:phone_number_status).and_return('DISCONNECTED')
      aggregate_failures do
        expect(result.error).to eq(:registration_pin_required)
        expect(Channel::Whatsapp.count).to eq(0)
        expect(Bloomwire::WhatsappSetup.count).to eq(0)
      end
    end

    it 'never logs the PIN when registration fails with #133005' do
      warn_logs = []
      allow(Rails.logger).to receive(:warn) { |m| warn_logs << m }
      with_modified_env(existing_pins_env => { 'PNID-1' => '654321' }.to_json) do
        allow(fb_client).to receive(:register_phone_number).and_raise(pin_mismatch_error)
        allow(fb_client).to receive(:phone_number_status).and_return('DISCONNECTED')
        result
        expect(warn_logs.join("\n")).not_to include('654321')
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
    before do
      stub_ready
      stub_messaging_capability
    end

    # Run the managed signup for ONE specific number, with Meta fully stubbed for this call.
    def signup(phone_number_id:, phone_number:, waba_id: 'WABA-1', token: 'FAKE-CUSTOMER-TOKEN')
      allow(Whatsapp::TokenExchangeService).to receive(:new)
        .and_return(instance_double(Whatsapp::TokenExchangeService, perform: token))
      allow(Whatsapp::PhoneInfoService).to receive(:new)
        .and_return(instance_double(Whatsapp::PhoneInfoService,
                                    perform: { phone_number_id: phone_number_id, phone_number: phone_number,
                                               verified: true, business_name: 'Acme' }))
      allow(Whatsapp::FacebookApiClient).to receive(:new)
        .and_return(instance_double(Whatsapp::FacebookApiClient, subscribe_app_to_waba: true, subscribed_to_waba?: true,
                                                                 register_phone_number: { 'success' => true },
                                                                 override_waba_callback: nil, subscribe_waba_webhook: nil,
                                                                 phone_number_status: 'CONNECTED', exchange_for_long_lived_token: token))
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

    it 'idempotently RESUMES the same setup when the same account re-onboards the same phone_number_id (no duplicate)' do
      first = signup(phone_number_id: 'PNID-1', phone_number: '+15551230001')
      again = signup(phone_number_id: 'PNID-1', phone_number: '+15551230001')
      aggregate_failures do
        expect(first).to be_success
        expect(again).to be_success
        expect(Channel::Whatsapp.where(account: account).count).to eq(1)
        expect(account.inboxes.count).to eq(1)
        expect(Bloomwire::WhatsappSetup.where(account: account).count).to eq(1)
      end
    end
  end

  # WhatsWay-proven token lifecycle: the short-lived embedded-signup USER token is extended to a long-lived
  # (~60 day) one BEFORE it is stored, and that long-lived token is the operational channel credential. Plus
  # cross-account isolation and a 10-customer volume simulation (the expected daily onboarding load).
  describe 'WhatsWay long-lived token lifecycle + multi-customer isolation' do
    before { stub_ready }

    it 'stores the LONG-LIVED exchanged token (not the short-lived signup token) as the operational credential' do
      stub_meta(token: 'SHORT-LIVED')
      allow(fb_client).to receive(:exchange_for_long_lived_token).with('SHORT-LIVED').and_return('LONG-LIVED-60D')
      aggregate_failures do
        expect(result).to be_success
        expect(Channel::Whatsapp.last.provider_config['api_key']).to eq('LONG-LIVED-60D')
        expect(result.dto.to_json).not_to include('SHORT-LIVED')
        expect(result.dto.to_json).not_to include('LONG-LIVED-60D')
      end
    end

    it 'captures both code-exchange and long-lived token authority before phone-info lookup and register' do
      events = []
      stub_meta(token: 'SHORT-LIVED')
      allow(fb_client).to receive(:exchange_for_long_lived_token).with('SHORT-LIVED').and_return('LONG-LIVED-60D')
      allow(Bloomwire::WhatsappSignupTokenDebug).to receive(:log) do |args|
        events << [:token_debug, args[:stage], args[:token], args[:phone_number_id]]
      end
      allow(Whatsapp::PhoneInfoService).to receive(:new) do |waba_id, phone_number_id, token|
        events << [:phone_info, waba_id, phone_number_id, token]
        instance_double(Whatsapp::PhoneInfoService, perform: phone_info)
      end

      result

      expected_debug_events = [
        [:token_debug, 'code_exchange', 'SHORT-LIVED', 'PNID-1'],
        [:token_debug, 'long_lived_exchange', 'LONG-LIVED-60D', 'PNID-1']
      ]
      aggregate_failures do
        expect(events.first(2)).to eq(expected_debug_events)
        expect(events.third).to eq([:phone_info, 'WABA-1', 'PNID-1', 'LONG-LIVED-60D'])
      end
    end

    it 'fails closed (:phone_number_taken) when the SAME phone_number_id belongs to ANOTHER account (isolation)' do
      stub_meta
      expect(result).to be_success # account A onboards PNID-1
      other = create(:account)
      cross = described_class.new(account: other,
                                  params: { code: 'META-CODE', business_id: 'BIZ-1', waba_id: 'WABA-1',
                                            phone_number_id: 'PNID-1' }).perform
      aggregate_failures do
        expect(cross.error).to eq(:phone_number_taken)
        expect(Channel::Whatsapp.where(account: other).count).to eq(0)
        expect(Bloomwire::WhatsappSetup.where(account: other).count).to eq(0)
      end
    end

    it 'onboards 10 independent customers into 10 isolated Channel/Inbox/Setup with no token leakage' do
      stub_messaging_capability
      accounts = create_list(:account, 10)
      results = accounts.each_with_index.map do |acct, i|
        pnid = "PNID-SIM-#{i}"
        phone = { phone_number_id: pnid, phone_number: "+1555000#{format('%04d', i)}", verified: true, business_name: "Biz#{i}" }
        client_stubs = { subscribe_app_to_waba: true, subscribed_to_waba?: true, register_phone_number: { 'success' => true },
                         override_waba_callback: nil, subscribe_waba_webhook: nil, phone_number_status: 'CONNECTED',
                         exchange_for_long_lived_token: "LONG-#{i}" }
        allow(Whatsapp::TokenExchangeService).to receive(:new).and_return(instance_double(Whatsapp::TokenExchangeService, perform: "SHORT-#{i}"))
        allow(Whatsapp::PhoneInfoService).to receive(:new).and_return(instance_double(Whatsapp::PhoneInfoService, perform: phone))
        allow(Whatsapp::FacebookApiClient).to receive(:new).and_return(instance_double(Whatsapp::FacebookApiClient, client_stubs))
        described_class.new(account: acct,
                            params: { code: "CODE-#{i}", business_id: 'BIZ', waba_id: "WABA-#{i}", phone_number_id: pnid }).perform
      end
      aggregate_failures do
        expect(results).to all(be_success)
        expect(Bloomwire::WhatsappSetup.where(account: accounts).count).to eq(10)
        expect(Channel::Whatsapp.where(account: accounts).count).to eq(10)
        accounts.each_with_index do |acct, i|
          expect(Bloomwire::WhatsappSetup.find_by(account_id: acct.id, phone_number_id: "PNID-SIM-#{i}")).to be_present
        end
        expect(results.map { |r| r.dto.to_json }.join).not_to match(/LONG-\d|SHORT-\d/)
      end
    end
  end

  # WhatsWay-parity reconnect: a previously-CONNECTED managed number that later drops to DISCONNECTED must be
  # RE-REGISTERED (Cloud API /register) on re-onboard and reconnected onto the SAME Channel/Inbox/Setup — never a
  # silent resume (which would leave the number offline) and never a duplicate inbox. This is the Stage 1 truth.
  describe 'reconnect of a previously-disconnected number' do
    before { stub_ready }

    it 're-registers a DISCONNECTED number and reconnects the SAME channel/inbox/setup (no duplicate)' do
      stub_meta
      allow(fb_client).to receive(:phone_number_status).and_return('CONNECTED') # first onboard: no register needed
      expect(result).to be_success
      first_channel_id = Channel::Whatsapp.last.id

      # The number later drops offline; the SAME account re-onboards the SAME number.
      allow(fb_client).to receive(:phone_number_status).and_return('DISCONNECTED', 'CONNECTED')
      again = described_class.new(account: account, params: params).perform

      aggregate_failures do
        expect(again).to be_success
        # /register was invoked exactly once — only on the reconnect (the first onboard was already CONNECTED).
        expect(fb_client).to have_received(:register_phone_number).with('PNID-1', anything).once
        expect(Channel::Whatsapp.where(account: account).count).to eq(1)
        expect(account.inboxes.count).to eq(1)
        expect(Bloomwire::WhatsappSetup.where(account: account).count).to eq(1)
        expect(Channel::Whatsapp.last.id).to eq(first_channel_id)
        expect(Bloomwire::WhatsappSetup.last.setup_status).to eq('ready_for_webhook')
      end
    end

    it 'refreshes the stored long-lived token on reconnect (same channel keeps only the newest token)' do
      stub_meta(token: 'OLD-LONG-LIVED')
      allow(fb_client).to receive(:phone_number_status).and_return('CONNECTED')
      expect(result).to be_success
      expect(Channel::Whatsapp.last.provider_config['api_key']).to eq('OLD-LONG-LIVED')

      stub_meta(token: 'NEW-LONG-LIVED')
      allow(fb_client).to receive(:phone_number_status).and_return('CONNECTED')
      again = described_class.new(account: account, params: params).perform
      aggregate_failures do
        expect(again).to be_success
        expect(Channel::Whatsapp.where(account: account).count).to eq(1)
        expect(Channel::Whatsapp.last.provider_config['api_key']).to eq('NEW-LONG-LIVED')
        expect(again.dto.to_json).not_to include('NEW-LONG-LIVED')
      end
    end
  end

  # Phase 5 — outbound messaging capability gate wiring. The capability service (unit-tested in
  # bloomwire/whatsapp_messaging_capability_spec.rb) decides whether the stored-token actor can SEND; this
  # asserts the embedded-signup service TRANSLATES that into the persisted setup_status + a safe DTO, and never
  # persists a silently receive-only "ready" inbox.
  describe 'outbound messaging capability gate (wiring)' do
    before do
      stub_ready
      stub_meta
    end

    it 'persists a ready_for_webhook inbox with no status_reason when the actor can send (:ready)' do
      stub_messaging_capability(status: :ready)
      result
      aggregate_failures do
        expect(Bloomwire::WhatsappSetup.last.setup_status).to eq('ready_for_webhook')
        expect(Bloomwire::WhatsappSetup.last.status_reason).to be_nil
        # BLOCKER 2: the WABA is subscribed to the global router ONLY on the ready path, and the subscription is
        # verified before the inbox is treated as live.
        expect(fb_client).to have_received(:subscribe_app_to_waba).with('WABA-1')
        # subscribed_to_waba? is now called twice: an idempotent pre-check (skip if already subscribed) + the verify.
        expect(fb_client).to have_received(:subscribed_to_waba?).with('WABA-1').at_least(:once)
      end
    end

    # BLOCKER 2: a capability failure fails onboarding closed (no falsely-ready inbox that never receives inbound).
    it 'fails closed (persists nothing) when the actor CAN send but the subscription cannot be confirmed' do
      stub_messaging_capability(status: :ready)
      allow(fb_client).to receive(:subscribed_to_waba?).and_return(false)
      aggregate_failures do
        expect(result.error).to eq(:subscription_failed)
        expect(Channel::Whatsapp.count).to eq(0)
        expect(Bloomwire::WhatsappSetup.count).to eq(0)
      end
    end

    it 'persists an explicit Action-Required inbox (never silently receive-only) when the actor cannot send' do
      stub_messaging_capability(status: :action_required, reason: 'outbound_messaging_permission_required')
      aggregate_failures do
        expect(result).to be_success
        setup = Bloomwire::WhatsappSetup.last
        expect(setup.setup_status).to eq('action_required')
        expect(setup.status_reason).to eq('outbound_messaging_permission_required')
        # Records preserved for resumption, but NOT routeable-ready: the global router hands off nothing.
        expect(Channel::Whatsapp.count).to eq(1)
        expect(account.inboxes.count).to eq(1)
        # BLOCKER 2: a not-ready inbox is NEVER subscribed — else Meta forwards inbound the router would discard
        # (lost inbound). It is inactive in BOTH directions until Recheck completes it.
        expect(fb_client).not_to have_received(:subscribe_app_to_waba)
        payload = bw_inbound_text_payload(phone_number_id: 'PNID-1', display_phone_number: '15551230001')
        expect(Bloomwire::Webhooks::WhatsappRouter.resolve_handoff_safe_setup(payload)).to be_nil
      end
    end

    it 'surfaces a secret-free action_required block (reason + resolution) in the DTO' do
      stub_messaging_capability(status: :action_required, reason: 'outbound_messaging_permission_required')
      dto = result.dto
      aggregate_failures do
        expect(dto.dig(:setup, :status)).to eq('action_required')
        expect(dto.dig(:action_required, :reason)).to eq('outbound_messaging_permission_required')
        expect(dto.dig(:action_required, :resolution)).to be_present
        expect(dto.to_json).not_to include('FAKE-CUSTOMER-TOKEN')
      end
    end
  end
end
