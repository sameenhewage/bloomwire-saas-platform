require 'rails_helper'

# DEV-only, sanitized signup-token diagnostic. Proves it is INERT unless explicitly flagged, that when flagged it
# logs the token identity/scopes + WABA management/messaging membership + owner business, and that it NEVER logs
# the token and NEVER raises into the caller. Meta client stubbed (no real Meta). Fake values only.
RSpec.describe Bloomwire::WhatsappSignupTokenDebug do
  let(:token) { 'FAKE-SIGNUP-TOKEN' }
  let(:waba_id) { 'WABA-1' }
  let(:client) { instance_double(Whatsapp::FacebookApiClient) }

  def debug_payload(type:, mgmt_targets:, msg_targets:)
    { 'data' => { 'type' => type, 'app_id' => 'APP-1', 'user_id' => 'ACTOR-1', 'is_valid' => true,
                  'scopes' => %w[whatsapp_business_management whatsapp_business_messaging],
                  'granular_scopes' => [
                    { 'scope' => 'whatsapp_business_management', 'target_ids' => mgmt_targets },
                    { 'scope' => 'whatsapp_business_messaging', 'target_ids' => msg_targets }
                  ] } }
  end

  def flag(value)
    allow(GlobalConfigService).to receive(:load).and_call_original
    allow(GlobalConfigService).to receive(:load).with('BLOOMWIRE_WHATSAPP_TOKEN_DEBUG', 'false').and_return(value)
  end

  def capture_logs
    logs = []
    allow(Rails.logger).to receive(:warn) { |message| logs << message }
    yield
    logs
  end

  def call
    described_class.log(client: client, token: token, waba_id: waba_id, phone_number_id: 'PNID-1')
  end

  it 'is INERT when the flag is off (no Meta call, no log)' do
    flag('false')
    allow(client).to receive(:debug_token)
    logs = capture_logs { call }
    aggregate_failures do
      expect(client).not_to have_received(:debug_token)
      expect(logs).to be_empty
    end
  end

  it 'is HARD-BLOCKED on real production even when the flag is on (BLOOMWIRE_ENV=production)' do
    flag('true')
    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:fetch).with('BLOOMWIRE_ENV', '').and_return('production')
    allow(client).to receive(:debug_token)
    logs = capture_logs { call }
    aggregate_failures do
      expect(client).not_to have_received(:debug_token)
      expect(logs).to be_empty
    end
  end

  context 'when the flag is on (dev/test)' do
    before { flag('true') }

    it 'logs the sanitized identity + WABA scope flags + the actor WABA tasks + owner, and NEVER the token' do
      allow(client).to receive(:debug_token).with(token)
                                            .and_return(debug_payload(type: 'SYSTEM_USER', mgmt_targets: [], msg_targets: [waba_id]))
      allow(client).to receive(:waba_owner_business_id).with(waba_id).and_return('BIZ-OWNER-1')
      allow(client).to receive(:waba_user_tasks).with(waba_id, 'ACTOR-1').and_return(%w[MESSAGING])
      logs = capture_logs { call }
      line = logs.find { |message| message.include?('bloomwire.whatsapp.signup_token_debug') }
      event = JSON.parse(line[line.index('{')..])
      aggregate_failures do
        expect(event['token_type']).to eq('SYSTEM_USER')
        expect(event['waba_in_management']).to be(false)
        expect(event['waba_in_messaging']).to be(true)
        expect(event['actor_waba_tasks']).to eq(%w[MESSAGING])
        expect(event['waba_owner_business_id']).to eq('BIZ-OWNER-1')
        expect(line).not_to include(token)
      end
    end

    it 'captures actor_waba_tasks null when the actor is not visible in the WABA assigned_users list' do
      allow(client).to receive(:debug_token).and_return(debug_payload(type: 'USER', mgmt_targets: [], msg_targets: []))
      allow(client).to receive(:waba_owner_business_id).and_return('BIZ-OWNER-1')
      allow(client).to receive(:waba_user_tasks).and_return(nil)
      logs = capture_logs { call }
      line = logs.find { |message| message.include?('signup_token_debug') }
      expect(JSON.parse(line[line.index('{')..])['actor_waba_tasks']).to be_nil
    end

    it 'reports waba_in_management true when the token holds management on the selected WABA' do
      allow(client).to receive(:debug_token).and_return(debug_payload(type: 'USER', mgmt_targets: [waba_id], msg_targets: [waba_id]))
      allow(client).to receive(:waba_owner_business_id).and_return('BIZ-OWNER-1')
      allow(client).to receive(:waba_user_tasks).and_return(%w[MANAGE])
      logs = capture_logs { call }
      line = logs.find { |message| message.include?('signup_token_debug') }
      expect(JSON.parse(line[line.index('{')..])['waba_in_management']).to be(true)
    end

    it 'never raises into the caller (and never logs the token) when debug_token fails' do
      allow(client).to receive(:debug_token).and_raise(StandardError, "boom #{token}")
      logs = capture_logs { expect { call }.not_to raise_error }
      expect(logs.join).not_to include(token)
    end
  end
end
