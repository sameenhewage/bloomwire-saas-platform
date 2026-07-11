require 'rails_helper'

# WhatsWay-parity "Disconnect" endpoint: admin-only + managed-mode-only; Meta /deregister stubbed; safe DTO. Marks
# the setup `disconnected` while KEEPING the Channel/Inbox/Setup records (a later Embedded Signup reconnect reuses
# them). Never a delete, never a webhook unsubscribe, never a secret in the response. Fake values only.
RSpec.describe 'Bloomwire WhatsApp disconnect endpoint', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:token) { 'FAKE-STORED-TOKEN' }
  let(:channel) do
    Channel::Whatsapp.new(
      account: account, phone_number: '+15551230001', provider: 'whatsapp_cloud',
      provider_config: { 'phone_number_id' => 'PNID-1', 'business_account_id' => 'WABA-1',
                         'source' => 'bloomwire_managed', 'connection_mode' => 'standard' }
    ).tap do |channel_record|
      channel_record.save!(validate: false)
      channel_record.provider_config['api_key'] = token
      channel_record.save!(validate: false)
    end
  end
  let(:inbox) { Inbox.create!(account: account, name: 'Acme WhatsApp', channel: channel) }
  let(:setup) do
    Bloomwire::WhatsappSetup.create!(
      account: account, inbox: inbox, channel_whatsapp: channel, phone_number_id: 'PNID-1', waba_id: 'WABA-1',
      display_phone_number: '+15551230001', setup_status: Bloomwire::WhatsappSetup::ROUTEABLE_STATUS
    )
  end
  let(:url) { "/api/v1/accounts/#{account.id}/bloomwire/whatsapp/disconnections" }

  before { GlobalConfig.clear_cache }

  def enable_managed_mode
    bw_set_config('BLOOMWIRE_MODE_ENABLED', true)
    bw_set_config('BLOOMWIRE_PRIVACY_HARDENING', true)
    bw_set_config('BLOOMWIRE_RESTRICT_NATIVE_WHATSAPP_SETUP', true)
    bw_set_config('BLOOMWIRE_MANAGED_WHATSAPP_ONBOARDING', true)
  end

  def stub_meta(statuses: %w[CONNECTED DISCONNECTED])
    client = instance_double(Whatsapp::FacebookApiClient)
    allow(client).to receive(:phone_number_status).and_return(*statuses)
    allow(client).to receive(:deregister_phone_number).and_return('success' => true)
    allow(Whatsapp::FacebookApiClient).to receive(:new).and_return(client)
    client
  end

  context 'when managed mode is active and admin (Meta stubbed)' do
    before { enable_managed_mode }

    it 'disconnects: marks the setup disconnected, KEEPS records, returns a safe DTO (no secrets)' do
      setup
      stub_meta
      post url, headers: admin.create_new_auth_token, params: { inbox_id: inbox.id }, as: :json
      aggregate_failures do
        expect(response).to have_http_status(:ok)
        expect(response.parsed_body['disconnected']).to be(true)
        expect(response.parsed_body.dig('setup', 'status')).to eq('disconnected')
        expect(response.body).not_to include('FAKE-STORED-TOKEN')
        expect(response.body).not_to include('api_key')
        expect(response.body).not_to include('PNID-1')
        expect(setup.reload.setup_status).to eq('disconnected')
        expect(Inbox.exists?(inbox.id)).to be(true)
        expect(Channel::Whatsapp.exists?(channel.id)).to be(true)
      end
    end

    it 'returns a safe failure and leaves Standard state unchanged when Meta deregistration is unverified' do
      setup
      client = stub_meta(statuses: ['CONNECTED'])
      allow(client).to receive(:deregister_phone_number).and_raise(StandardError, 'RAW Meta failure')
      post url, headers: admin.create_new_auth_token, params: { inbox_id: inbox.id }, as: :json
      aggregate_failures do
        expect(response).to have_http_status(:bad_gateway)
        expect(response.parsed_body['code']).to eq('disconnect_unverified')
        expect(response.body).not_to include('RAW Meta failure')
        expect(setup.reload.setup_status).to eq(Bloomwire::WhatsappSetup::ROUTEABLE_STATUS)
      end
    end

    it 'enforces Coexistence mobile offboarding on a direct API call without Meta deregister or local state change' do
      setup
      channel.provider_config['connection_mode'] = 'coexistence'
      channel.save!(validate: false)
      expect(Whatsapp::FacebookApiClient).not_to receive(:new)

      post url, headers: admin.create_new_auth_token, params: { inbox_id: inbox.id }, as: :json

      aggregate_failures do
        expect(response).to have_http_status(:conflict)
        expect(response.parsed_body['code']).to eq('mobile_action_required')
        expect(response.parsed_body['error']).to include('WhatsApp Business app')
        expect(response.parsed_body['error']).to include('Settings → Account → Business Platform → Disconnect')
        expect(response.body).not_to include('PNID-1')
        expect(response.body).not_to include('FAKE-STORED-TOKEN')
        expect(setup.reload.setup_status).to eq(Bloomwire::WhatsappSetup::ROUTEABLE_STATUS)
      end
    end

    it 'denies an agent' do
      setup
      stub_meta
      post url, headers: agent.create_new_auth_token, params: { inbox_id: inbox.id }, as: :json
      expect(response).to have_http_status(:unauthorized).or have_http_status(:forbidden)
    end

    it 'is 404 for an inbox id that is not in this account' do
      stub_meta
      post url, headers: admin.create_new_auth_token, params: { inbox_id: inbox.id + 999_999 }, as: :json
      expect(response).to have_http_status(:not_found)
    end
  end

  # Coexistence offboarding recheck: the ONE authoritative reconciliation owner (there is no account_update /
  # PARTNER_REMOVED webhook handler). Admin + managed-mode only; marks the preserved setup `disconnected` ONLY after
  # Meta proves the number is no longer coexistence-connected; otherwise leaves state untouched. Safe DTO only.
  context 'when rechecking with managed mode active and admin (Meta stubbed)' do
    let(:recheck_url) { "#{url}/recheck" }

    before do
      enable_managed_mode
      channel.provider_config['connection_mode'] = 'coexistence'
      channel.save!(validate: false)
    end

    def stub_coexistence(onboarded:)
      client = instance_double(Whatsapp::FacebookApiClient)
      allow(client).to receive(:coexistence_onboarded?).and_return(onboarded)
      allow(Whatsapp::FacebookApiClient).to receive(:new).and_return(client)
      client
    end

    it 'marks the setup disconnected and returns a safe DTO once Meta proves it is no longer coexistence-connected' do
      setup
      stub_coexistence(onboarded: false)
      post recheck_url, headers: admin.create_new_auth_token, params: { inbox_id: inbox.id }, as: :json
      aggregate_failures do
        expect(response).to have_http_status(:ok)
        expect(response.parsed_body['disconnected']).to be(true)
        expect(response.parsed_body.dig('setup', 'status')).to eq('disconnected')
        expect(response.body).not_to include('FAKE-STORED-TOKEN')
        expect(response.body).not_to include('PNID-1')
        expect(setup.reload.setup_status).to eq('disconnected')
        expect(Channel::Whatsapp.exists?(channel.id)).to be(true)
      end
    end

    it 'returns 409 still_connected and leaves state unchanged while Meta still reports it connected' do
      setup
      stub_coexistence(onboarded: true)
      post recheck_url, headers: admin.create_new_auth_token, params: { inbox_id: inbox.id }, as: :json
      aggregate_failures do
        expect(response).to have_http_status(:conflict)
        expect(response.parsed_body['code']).to eq('still_connected')
        expect(setup.reload.setup_status).to eq(Bloomwire::WhatsappSetup::ROUTEABLE_STATUS)
      end
    end

    it 'returns 502 recheck_unverified and leaves state unchanged when Meta cannot be read (no false disconnect)' do
      setup
      client = instance_double(Whatsapp::FacebookApiClient)
      allow(client).to receive(:coexistence_onboarded?).and_raise(StandardError, 'RAW meta failure')
      allow(Whatsapp::FacebookApiClient).to receive(:new).and_return(client)
      post recheck_url, headers: admin.create_new_auth_token, params: { inbox_id: inbox.id }, as: :json
      aggregate_failures do
        expect(response).to have_http_status(:bad_gateway)
        expect(response.parsed_body['code']).to eq('recheck_unverified')
        expect(response.body).not_to include('RAW meta failure')
        expect(setup.reload.setup_status).to eq(Bloomwire::WhatsappSetup::ROUTEABLE_STATUS)
      end
    end

    it 'denies an agent' do
      setup
      stub_coexistence(onboarded: false)
      post recheck_url, headers: agent.create_new_auth_token, params: { inbox_id: inbox.id }, as: :json
      expect(response).to have_http_status(:unauthorized).or have_http_status(:forbidden)
    end
  end

  context 'when managed self-serve is not active (surface inert / 404)' do
    it 'is 404 when Bloomwire mode is OFF (stock)' do
      setup
      post url, headers: admin.create_new_auth_token, params: { inbox_id: inbox.id }, as: :json
      expect(response).to have_http_status(:not_found)
    end

    it 'recheck is 404 when Bloomwire mode is OFF (stock)' do
      setup
      post "#{url}/recheck", headers: admin.create_new_auth_token, params: { inbox_id: inbox.id }, as: :json
      expect(response).to have_http_status(:not_found)
    end
  end
end
