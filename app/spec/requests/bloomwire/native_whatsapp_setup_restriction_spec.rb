require 'rails_helper'

# Phase 10A.2: when Bloomwire mode + BLOOMWIRE_RESTRICT_NATIVE_WHATSAPP_SETUP are ON, business (account)
# users cannot create / authorize / reconnect / reconfigure native WhatsApp channels. The guard fires only
# for native WhatsApp setup actions; OFF == stock. It never blocks webhooks, jobs, read paths, non-WhatsApp
# channels, or the SuperAdmin Bloomwire surfaces, and never renders secrets. Fake values only.
RSpec.describe 'Bloomwire native WhatsApp setup restriction', type: :request do
  let(:account) { create(:account) }
  let(:administrator) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:super_admin) { create(:super_admin) }
  let(:restricted_message) { 'WhatsApp setup is managed by Bloomwire Ops. Please contact support.' }

  def set_toggle(key, value)
    config = InstallationConfig.where(name: key).first_or_initialize
    config.value = value
    config.locked = false
    config.save!
    GlobalConfig.clear_cache
  end

  def enable_restriction
    set_toggle('BLOOMWIRE_MODE_ENABLED', true)
    set_toggle('BLOOMWIRE_RESTRICT_NATIVE_WHATSAPP_SETUP', true)
  end

  def whatsapp_inbox
    channel = create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud',
                                        validate_provider_config: false, sync_templates: false)
    channel.update!(provider_config: channel.provider_config.merge('api_key' => 'FAKE-WA-APIKEY', 'source' => 'embedded_signup'))
    channel.inbox
  end

  before { GlobalConfig.clear_cache }

  describe 'when restriction is ON' do
    before { enable_restriction }

    it 'blocks an administrator from starting WhatsApp authorization / embedded signup / reconnect' do
      post "/api/v1/accounts/#{account.id}/whatsapp/authorization",
           params: { code: 'x', business_id: 'y', waba_id: 'z' }, headers: administrator.create_new_auth_token, as: :json
      expect(response).to have_http_status(:forbidden)
      expect(response.parsed_body['error']).to eq(restricted_message)
    end

    it 'blocks an agent from starting WhatsApp authorization' do
      post "/api/v1/accounts/#{account.id}/whatsapp/authorization",
           params: { code: 'x', business_id: 'y', waba_id: 'z' }, headers: agent.create_new_auth_token, as: :json
      expect(response).to have_http_status(:forbidden)
      expect(response.parsed_body['error']).to eq(restricted_message)
    end

    it 'blocks an administrator from creating a native WhatsApp inbox/channel' do
      expect do
        post "/api/v1/accounts/#{account.id}/inboxes",
             params: { name: 'WA', channel: { type: 'whatsapp', phone_number: '+15551230000',
                                              provider_config: { api_key: 'FAKE' } } },
             headers: administrator.create_new_auth_token, as: :json
      end.not_to change(Channel::Whatsapp, :count)
      expect(response).to have_http_status(:forbidden)
      expect(response.parsed_body['error']).to eq(restricted_message)
    end

    it 'blocks an administrator from updating a WhatsApp channel provider config' do
      inbox = whatsapp_inbox
      patch "/api/v1/accounts/#{account.id}/inboxes/#{inbox.id}",
            params: { channel: { provider_config: { api_key: 'NEW-FAKE' } } },
            headers: administrator.create_new_auth_token, as: :json
      expect(response).to have_http_status(:forbidden)
      expect(response.parsed_body['error']).to eq(restricted_message)
    end

    it 'does NOT block creating a non-WhatsApp (web widget) channel' do
      expect do
        post "/api/v1/accounts/#{account.id}/inboxes",
             params: { name: 'Site', channel: { type: 'web_widget', website_url: 'https://example.com' } },
             headers: administrator.create_new_auth_token, as: :json
      end.to change(Channel::WebWidget, :count).by(1)
      expect(response).to have_http_status(:success)
    end

    it 'does NOT block reading an existing WhatsApp inbox (show)' do
      inbox = whatsapp_inbox
      get "/api/v1/accounts/#{account.id}/inboxes/#{inbox.id}", headers: administrator.create_new_auth_token, as: :json
      expect(response).to have_http_status(:success)
    end

    it 'does NOT block the native WhatsApp webhook GET route' do
      get '/webhooks/whatsapp/12345', params: { 'hub.mode' => 'subscribe', 'hub.verify_token' => 'x', 'hub.challenge' => 'c' }
      expect(response).not_to have_http_status(:forbidden)
      expect(response.body).not_to include(restricted_message)
    end

    it 'does NOT block the Bloomwire global webhook GET route (still its own gate)' do
      get '/bloomwire/webhooks/whatsapp', params: { 'hub.mode' => 'subscribe', 'hub.verify_token' => 'x', 'hub.challenge' => 'c' }
      expect(response).to have_http_status(:not_found) # router feature OFF here -> inert, NOT a 403 from this guard
      expect(response.body).not_to include(restricted_message)
    end

    it 'keeps the SuperAdmin Bloomwire setup mapping page available' do
      sign_in(super_admin, scope: :super_admin)
      get '/super_admin/bloomwire_whatsapp_setups'
      expect(response).to have_http_status(:success)
    end

    it 'keeps the SuperAdmin real-hop readiness page available' do
      sign_in(super_admin, scope: :super_admin)
      setup = create(:bloomwire_whatsapp_setup, account: account, setup_status: 'pending')
      get "/super_admin/bloomwire_whatsapp_setups/#{setup.id}/readiness"
      expect(response).to have_http_status(:success)
    end

    it 'never renders secrets in the blocked response' do
      set_toggle('WHATSAPP_APP_SECRET', 'FAKE-APP-SECRET-XYZ')
      inbox = whatsapp_inbox
      patch "/api/v1/accounts/#{account.id}/inboxes/#{inbox.id}",
            params: { channel: { provider_config: { api_key: 'NEW-FAKE' } } },
            headers: administrator.create_new_auth_token, as: :json
      expect(response).to have_http_status(:forbidden)
      expect(response.body).not_to include('FAKE-APP-SECRET-XYZ')
      expect(response.body).not_to include('FAKE-WA-APIKEY')
    end
  end

  describe 'when restriction is OFF (stock - guard inactive)' do
    it 'does not intercept WhatsApp authorization (stock validation runs)' do
      post "/api/v1/accounts/#{account.id}/whatsapp/authorization",
           params: { business_id: 'y', waba_id: 'z' }, headers: administrator.create_new_auth_token, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to include('code')
      expect(response.body).not_to include(restricted_message)
    end

    it 'does not intercept when only the restrict toggle is ON but Bloomwire mode is OFF' do
      set_toggle('BLOOMWIRE_RESTRICT_NATIVE_WHATSAPP_SETUP', true) # master stays OFF
      post "/api/v1/accounts/#{account.id}/whatsapp/authorization",
           params: { business_id: 'y', waba_id: 'z' }, headers: administrator.create_new_auth_token, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).not_to include(restricted_message)
    end
  end
end
