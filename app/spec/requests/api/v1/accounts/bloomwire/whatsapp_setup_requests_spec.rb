require 'rails_helper'

# Phase 11A: account-level managed WhatsApp setup request API. Business/account ADMINS can request managed
# WhatsApp setup and view their current request; agents/unauthenticated are blocked; the surface is inert when
# Bloomwire mode is OFF; requests are scoped to Current.account (no cross-account access); no secrets accepted
# or rendered. Fake values only.
RSpec.describe 'Account managed WhatsApp setup requests API', type: :request do
  let(:account) { create(:account) }
  let(:other_account) { create(:account) }
  let(:administrator) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }

  def set_toggle(key, value)
    config = InstallationConfig.where(name: key).first_or_initialize
    config.value = value
    config.locked = false
    config.save!
    GlobalConfig.clear_cache
  end

  before { GlobalConfig.clear_cache }

  describe 'when Bloomwire mode is OFF (stock - inert)' do
    it 'returns 404 for create' do
      post "/api/v1/accounts/#{account.id}/bloomwire/whatsapp_setup_requests", headers: administrator.create_new_auth_token, as: :json
      expect(response).to have_http_status(:not_found)
      expect(Bloomwire::WhatsappSetupRequest.count).to eq(0)
    end

    it 'returns 404 for index' do
      get "/api/v1/accounts/#{account.id}/bloomwire/whatsapp_setup_requests", headers: administrator.create_new_auth_token, as: :json
      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'when Bloomwire mode is ON' do
    before { set_toggle('BLOOMWIRE_MODE_ENABLED', true) }

    context 'when the requester is an account administrator' do
      it 'creates a managed setup request (pending) attributed to the requester' do
        expect do
          post "/api/v1/accounts/#{account.id}/bloomwire/whatsapp_setup_requests", headers: administrator.create_new_auth_token, as: :json
        end.to change(Bloomwire::WhatsappSetupRequest, :count).by(1)
        expect(response).to have_http_status(:success)
        body = response.parsed_body
        expect(body['status']).to eq('pending')
        expect(body['account_id']).to eq(account.id)
        expect(body['requested_by_id']).to eq(administrator.id)
      end

      it 'is idempotent: a duplicate request returns the existing active one (no duplicate)' do
        post "/api/v1/accounts/#{account.id}/bloomwire/whatsapp_setup_requests", headers: administrator.create_new_auth_token, as: :json
        first_id = response.parsed_body['id']
        expect do
          post "/api/v1/accounts/#{account.id}/bloomwire/whatsapp_setup_requests", headers: administrator.create_new_auth_token, as: :json
        end.not_to change(Bloomwire::WhatsappSetupRequest, :count)
        expect(response.parsed_body['id']).to eq(first_id)
      end

      it 'lets the admin view the current request status' do
        post "/api/v1/accounts/#{account.id}/bloomwire/whatsapp_setup_requests", headers: administrator.create_new_auth_token, as: :json
        get "/api/v1/accounts/#{account.id}/bloomwire/whatsapp_setup_requests", headers: administrator.create_new_auth_token, as: :json
        expect(response).to have_http_status(:success)
        expect(response.parsed_body.first['status']).to eq('pending')
      end

      it 'ignores any secret/Meta token params and never renders secrets' do
        post "/api/v1/accounts/#{account.id}/bloomwire/whatsapp_setup_requests",
             params: { api_key: 'FAKE-APIKEY', access_token: 'FAKE-TOKEN', provider_config: { api_key: 'x' } },
             headers: administrator.create_new_auth_token, as: :json
        expect(response).to have_http_status(:success)
        expect(response.body).not_to include('FAKE-APIKEY')
        expect(response.body).not_to include('FAKE-TOKEN')
      end
    end

    context 'when authorizing access by role' do
      it 'blocks an agent (admin-only) from creating a request' do
        post "/api/v1/accounts/#{account.id}/bloomwire/whatsapp_setup_requests", headers: agent.create_new_auth_token, as: :json
        expect(response).to have_http_status(:unauthorized)
        expect(Bloomwire::WhatsappSetupRequest.count).to eq(0)
      end

      it 'blocks an agent from viewing the request queue' do
        get "/api/v1/accounts/#{account.id}/bloomwire/whatsapp_setup_requests", headers: agent.create_new_auth_token, as: :json
        expect(response).to have_http_status(:unauthorized)
      end

      it 'blocks an unauthenticated user' do
        post "/api/v1/accounts/#{account.id}/bloomwire/whatsapp_setup_requests", as: :json
        expect(response).to have_http_status(:unauthorized)
      end

      it 'does not let an admin access another account\'s requests' do
        set_toggle('BLOOMWIRE_MODE_ENABLED', true)
        get "/api/v1/accounts/#{other_account.id}/bloomwire/whatsapp_setup_requests", headers: administrator.create_new_auth_token, as: :json
        expect(response).to have_http_status(:unauthorized)
      end
    end
  end
end
