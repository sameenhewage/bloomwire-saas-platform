require 'rails_helper'

# Phase 5 (resume): the outbound-messaging recheck endpoint. Admin-only + managed-mode-only; safe DTO; all Meta
# calls stubbed. Re-verifies an existing Action-Required setup and, when the owner has granted the task, promotes
# it to routeable-ready (never a second inbox, never /register, never a secret). Fake values only.
RSpec.describe 'Bloomwire WhatsApp messaging-capability recheck endpoint', type: :request do
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
      display_phone_number: '+15551230001', setup_status: Bloomwire::WhatsappSetup::ACTION_REQUIRED_STATUS,
      status_reason: 'outbound_messaging_permission_required'
    )
  end
  let(:url) { "/api/v1/accounts/#{account.id}/bloomwire/whatsapp/messaging_capabilities/#{setup.id}" }

  before { GlobalConfig.clear_cache }

  def enable_managed_mode
    bw_set_config('BLOOMWIRE_MODE_ENABLED', true)
    bw_set_config('BLOOMWIRE_PRIVACY_HARDENING', true)
    bw_set_config('BLOOMWIRE_RESTRICT_NATIVE_WHATSAPP_SETUP', true)
    bw_set_config('BLOOMWIRE_MANAGED_WHATSAPP_ONBOARDING', true)
  end

  def stub_meta(tasks:)
    allow(Whatsapp::FacebookApiClient).to receive(:new).and_return(
      instance_double(Whatsapp::FacebookApiClient, token_actor_id: 'SYS-ACTOR-1', token_actor_type: 'SYSTEM_USER',
                                                   waba_user_tasks: tasks, assign_waba_user_tasks: nil,
                                                   messaging_waba_ids: [], subscribe_app_to_waba: nil,
                                                   subscribed_to_waba?: true, register_phone_number: { 'success' => true })
    )
  end

  context 'when managed mode is active and admin (Meta stubbed)' do
    before { enable_managed_mode }

    it 'promotes an Action-Required setup to ready when the owner has granted the task (safe DTO, no secrets)' do
      stub_meta(tasks: %w[MANAGE])
      patch url, headers: admin.create_new_auth_token, as: :json
      aggregate_failures do
        expect(response).to have_http_status(:ok)
        expect(response.parsed_body['ready']).to be(true)
        expect(response.parsed_body.dig('setup', 'status')).to eq('ready_for_webhook')
        expect(response.body).not_to include('FAKE-STORED-TOKEN')
        expect(response.body).not_to include('api_key')
        expect(response.body).not_to include('SYS-ACTOR-1')
        expect(setup.reload.setup_status).to eq('ready_for_webhook')
      end
    end

    it 'stays Action-Required with a sanitized reason when the task is still missing (no secret)' do
      stub_meta(tasks: %w[VIEW_TEMPLATES])
      patch url, headers: admin.create_new_auth_token, as: :json
      aggregate_failures do
        expect(response).to have_http_status(:ok)
        expect(response.parsed_body['ready']).to be(false)
        expect(response.parsed_body.dig('action_required', 'reason')).to eq('outbound_messaging_permission_required')
        expect(response.parsed_body['action_required']).not_to have_key('actor_id')
        expect(setup.reload.setup_status).to eq('action_required')
      end
    end

    it 'denies an agent' do
      stub_meta(tasks: %w[MANAGE])
      patch url, headers: agent.create_new_auth_token, as: :json
      expect(response).to have_http_status(:unauthorized).or have_http_status(:forbidden)
    end

    it 'is 404 for a setup id belonging to another account (no cross-account access)' do
      other = create(:account)
      other_setup = Bloomwire::WhatsappSetup.create!(account: other, setup_status: 'pending', phone_number_id: 'PNID-OTHER')
      stub_meta(tasks: %w[MANAGE])
      patch "/api/v1/accounts/#{account.id}/bloomwire/whatsapp/messaging_capabilities/#{other_setup.id}",
            headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:not_found)
    end
  end

  # BLOCKER 3: the DURABLE status read that backs the Inbox Settings surface (survives refresh / navigation /
  # re-login) — the persisted setup state is always loadable, so an Action-Required inbox is resumable forever.
  context 'when reading durable status (GET index) for the Inbox Settings surface' do
    let(:index_url) { "/api/v1/accounts/#{account.id}/bloomwire/whatsapp/messaging_capabilities?inbox_id=#{inbox.id}" }

    before { enable_managed_mode }

    it 'returns the PERSISTED Action-Required status + sanitized reason (no secret / no raw actor id)' do
      setup
      get index_url, headers: admin.create_new_auth_token, as: :json
      aggregate_failures do
        expect(response).to have_http_status(:ok)
        expect(response.parsed_body['managed']).to be(true)
        expect(response.parsed_body['ready']).to be(false)
        expect(response.parsed_body.dig('action_required', 'reason')).to eq('outbound_messaging_permission_required')
        expect(response.parsed_body.dig('setup', 'id')).to eq(setup.id)
        expect(response.body).not_to include('FAKE-STORED-TOKEN')
        expect(response.body).not_to include('SYS-ACTOR-1')
      end
    end

    it 'returns ready:true and no action_required block for a routeable setup' do
      setup.update!(setup_status: Bloomwire::WhatsappSetup::ROUTEABLE_STATUS, status_reason: nil)
      get index_url, headers: admin.create_new_auth_token, as: :json
      aggregate_failures do
        expect(response).to have_http_status(:ok)
        expect(response.parsed_body['ready']).to be(true)
        expect(response.parsed_body).not_to have_key('action_required')
      end
    end

    it 'omits the action_required block for a non-routeable setup that is NOT action_required (e.g. pending)' do
      setup.update!(setup_status: 'pending', status_reason: nil)
      get index_url, headers: admin.create_new_auth_token, as: :json
      aggregate_failures do
        expect(response).to have_http_status(:ok)
        expect(response.parsed_body['ready']).to be(false)
        expect(response.parsed_body).not_to have_key('action_required')
      end
    end

    it 'returns managed:false for an inbox with no Bloomwire managed setup' do
      get "/api/v1/accounts/#{account.id}/bloomwire/whatsapp/messaging_capabilities?inbox_id=#{inbox.id + 999_999}",
          headers: admin.create_new_auth_token, as: :json
      aggregate_failures do
        expect(response).to have_http_status(:ok)
        expect(response.parsed_body['managed']).to be(false)
      end
    end

    it 'denies an agent' do
      setup
      get index_url, headers: agent.create_new_auth_token, as: :json
      expect(response).to have_http_status(:unauthorized).or have_http_status(:forbidden)
    end
  end

  context 'when managed self-serve is not active (surface inert / 404)' do
    it 'is 404 when Bloomwire mode is OFF (stock)' do
      patch url, headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:not_found)
    end

    it 'GET index is 404 when Bloomwire mode is OFF (stock)' do
      get "/api/v1/accounts/#{account.id}/bloomwire/whatsapp/messaging_capabilities?inbox_id=#{inbox.id}",
          headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:not_found)
    end
  end
end
