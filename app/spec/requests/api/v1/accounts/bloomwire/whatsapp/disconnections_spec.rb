require 'rails_helper'

# Managed WhatsApp "Disconnect" endpoint: admin-only + managed-mode-only; requires the preserved account/inbox/
# channel/phone-aligned Setup before any Meta call. Standard returns success only after Meta verifies DISCONNECTED
# and updates that same Setup; Coexistence stays unchanged until webhook proof. Safe DTO, no delete/unsubscribe/secret.
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

    it 'fails closed with no success DTO or Meta call when the preserved Setup is missing' do
      inbox
      counts_before = [Inbox.count, Channel::Whatsapp.count, Bloomwire::WhatsappSetup.count]
      expect(Whatsapp::FacebookApiClient).not_to receive(:new)

      post url, headers: admin.create_new_auth_token, params: { inbox_id: inbox.id }, as: :json

      aggregate_failures do
        expect(response).to have_http_status(:not_found)
        expect(response.parsed_body['code']).to eq('not_found')
        expect(response.parsed_body['disconnected']).not_to be(true)
        expect(response.parsed_body).not_to have_key('setup')
        expect(response.body).not_to include('FAKE-STORED-TOKEN')
        expect(response.body).not_to include('PNID-1')
        expect([Inbox.count, Channel::Whatsapp.count, Bloomwire::WhatsappSetup.count]).to eq(counts_before)
      end
    end

    it 'fails closed before any Meta call when the Setup phone mapping is stale' do
      setup.phone_number_id = 'PNID-STALE'
      setup.save!(validate: false)
      state_before = [setup.reload.attributes, Inbox.count, Channel::Whatsapp.count, Bloomwire::WhatsappSetup.count]
      expect(Whatsapp::FacebookApiClient).not_to receive(:new)

      post url, headers: admin.create_new_auth_token, params: { inbox_id: inbox.id }, as: :json

      aggregate_failures do
        expect(response).to have_http_status(:not_found)
        expect(response.parsed_body['code']).to eq('not_found')
        expect(response.parsed_body['disconnected']).not_to be(true)
        expect([setup.reload.attributes, Inbox.count, Channel::Whatsapp.count, Bloomwire::WhatsappSetup.count]).to eq(state_before)
      end
    end

    it 'disconnects the aligned Standard mapping, returns a safe DTO, and reuses the same records' do
      record_ids = [inbox.id, channel.id, setup.id]
      counts_before = [Inbox.count, Channel::Whatsapp.count, Bloomwire::WhatsappSetup.count]
      stub_meta

      post url, headers: admin.create_new_auth_token, params: { inbox_id: inbox.id }, as: :json

      aggregate_failures do
        expect(response).to have_http_status(:ok)
        expect(response.parsed_body['disconnected']).to be(true)
        expect(response.parsed_body.dig('setup', 'id')).to eq(setup.id)
        expect(response.parsed_body.dig('setup', 'status')).to eq('disconnected')
        expect(response.body).not_to include('FAKE-STORED-TOKEN')
        expect(response.body).not_to include('api_key')
        expect(response.body).not_to include('PNID-1')
        expect(setup.reload.setup_status).to eq('disconnected')
        expect([inbox.reload.id, channel.reload.id, setup.reload.id]).to eq(record_ids)
        expect([Inbox.count, Channel::Whatsapp.count, Bloomwire::WhatsappSetup.count]).to eq(counts_before)
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

    it 'enforces Coexistence mobile offboarding without Meta or changing the preserved records' do
      record_ids = [inbox.id, channel.id, setup.id]
      counts_before = [Inbox.count, Channel::Whatsapp.count, Bloomwire::WhatsappSetup.count]
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
        expect([inbox.reload.id, channel.reload.id, setup.reload.id]).to eq(record_ids)
        expect([Inbox.count, Channel::Whatsapp.count, Bloomwire::WhatsappSetup.count]).to eq(counts_before)
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
