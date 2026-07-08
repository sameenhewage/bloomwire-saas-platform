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

  def stub_meta
    allow(Whatsapp::FacebookApiClient).to receive(:new).and_return(
      instance_double(Whatsapp::FacebookApiClient, deregister_phone_number: { 'success' => true })
    )
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

    it 'still disconnects (200) when the Meta deregister raises (non-fatal, WhatsWay parity)' do
      setup
      allow(Whatsapp::FacebookApiClient).to receive(:new).and_return(
        instance_double(Whatsapp::FacebookApiClient).tap do |client|
          allow(client).to receive(:deregister_phone_number).and_raise(StandardError, 'boom')
        end
      )
      post url, headers: admin.create_new_auth_token, params: { inbox_id: inbox.id }, as: :json
      aggregate_failures do
        expect(response).to have_http_status(:ok)
        expect(setup.reload.setup_status).to eq('disconnected')
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

  context 'when managed self-serve is not active (surface inert / 404)' do
    it 'is 404 when Bloomwire mode is OFF (stock)' do
      setup
      post url, headers: admin.create_new_auth_token, params: { inbox_id: inbox.id }, as: :json
      expect(response).to have_http_status(:not_found)
    end
  end
end
