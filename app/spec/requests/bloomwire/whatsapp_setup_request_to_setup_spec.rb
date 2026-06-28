require 'rails_helper'

# Phase 12D — Setup Request -> Setup state reflection (account API).
#
# The account-side managed WhatsApp setup REQUEST must safely reflect the Ops-owned SETUP mapping state so the
# business owner can see progress (request lifecycle + technical readiness) WITHOUT exposing any secret, raw
# routing id, or internal record id, and without letting the business user touch the mapping. The Ops workflow
# (status + linking) is unchanged; this only adds a non-secret derived `setup_state` to the account DTO.
#
# Locks the safe request->setup flow. Fake values only; no Meta/WhatsApp call is made.
RSpec.describe 'Account managed WhatsApp setup request -> setup state reflection', type: :request do
  let(:account) { create(:account) }
  let(:administrator) { create(:user, account: account, role: :administrator) }

  def latest_request
    Bloomwire::WhatsappSetupRequest.where(account_id: account.id).order(created_at: :desc).first
  end

  def account_index
    get "/api/v1/accounts/#{account.id}/bloomwire/whatsapp_setup_requests",
        headers: administrator.create_new_auth_token, as: :json
    response.parsed_body.first
  end

  before { GlobalConfig.clear_cache }

  context 'when Bloomwire mode is ON' do
    before { bw_set_config('BLOOMWIRE_MODE_ENABLED', true) }

    it 'reports a non-secret setup_state of "unlinked" on a fresh request (create + index)' do
      post "/api/v1/accounts/#{account.id}/bloomwire/whatsapp_setup_requests",
           headers: administrator.create_new_auth_token, as: :json
      expect(response).to have_http_status(:success)
      expect(response.parsed_body['setup_state']).to eq('unlinked')
      expect(account_index['setup_state']).to eq('unlinked')
    end

    it 'reflects "in_progress" once Ops links a pending/configured setup mapping' do
      req = Bloomwire::WhatsappSetupRequest.request_for(account: account)
      setup = create(:bloomwire_whatsapp_setup, account: account, setup_status: 'configured')
      req.update!(bloomwire_whatsapp_setup: setup)
      expect(account_index['setup_state']).to eq('in_progress')
    end

    it 'reflects "ready" once the linked setup is ready_for_webhook' do
      req = Bloomwire::WhatsappSetupRequest.request_for(account: account)
      setup = create(:bloomwire_whatsapp_setup, :ready_for_webhook, account: account)
      req.update!(bloomwire_whatsapp_setup: setup)
      expect(account_index['setup_state']).to eq('ready')
    end

    it 'reflects "blocked" when the linked setup is blocked' do
      req = Bloomwire::WhatsappSetupRequest.request_for(account: account)
      setup = create(:bloomwire_whatsapp_setup, account: account, setup_status: 'blocked')
      req.update!(bloomwire_whatsapp_setup: setup)
      expect(account_index['setup_state']).to eq('blocked')
    end

    it 'never exposes secrets, raw routing ids, or internal record ids alongside setup_state' do
      req = Bloomwire::WhatsappSetupRequest.request_for(account: account)
      setup = create(:bloomwire_whatsapp_setup, :ready_for_webhook, account: account,
                                                                    aligned_phone_number_id: 'PNID-REFLECT-1',
                                                                    aligned_api_key: 'FAKE-REFLECT-APIKEY')
      req.update!(bloomwire_whatsapp_setup: setup)

      get "/api/v1/accounts/#{account.id}/bloomwire/whatsapp_setup_requests",
          headers: administrator.create_new_auth_token, as: :json
      body = response.parsed_body.first

      expect(body['setup_state']).to eq('ready')
      expect(body).not_to have_key('id')
      expect(body).not_to have_key('account_id')
      expect(body).not_to have_key('bloomwire_whatsapp_setup_id')
      expect(response.body).not_to include('FAKE-REFLECT-APIKEY')
      expect(response.body).not_to include('PNID-REFLECT-1')
    end
  end

  context 'when Bloomwire mode is OFF (stock - inert)' do
    it 'does not expose the request/setup state (404)' do
      get "/api/v1/accounts/#{account.id}/bloomwire/whatsapp_setup_requests",
          headers: administrator.create_new_auth_token, as: :json
      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'Bloomwire::WhatsappSetupRequest#account_facing_setup_state (non-secret derivation)' do
    it 'is "unlinked" with no linked setup' do
      req = Bloomwire::WhatsappSetupRequest.create!(account: account, status: 'pending')
      expect(req.account_facing_setup_state).to eq('unlinked')
    end

    it 'maps pending/configured setup statuses to "in_progress"' do
      %w[pending configured].each do |status|
        setup = create(:bloomwire_whatsapp_setup, account: account, setup_status: status)
        req = Bloomwire::WhatsappSetupRequest.create!(account: account, status: 'in_progress',
                                                      bloomwire_whatsapp_setup: setup)
        expect(req.account_facing_setup_state).to eq('in_progress')
        req.destroy!
      end
    end

    it 'maps ready_for_webhook to "ready" and blocked to "blocked"' do
      ready = create(:bloomwire_whatsapp_setup, :ready_for_webhook, account: account)
      blocked = create(:bloomwire_whatsapp_setup, account: account, setup_status: 'blocked')
      ready_req = Bloomwire::WhatsappSetupRequest.create!(account: account, status: 'completed', bloomwire_whatsapp_setup: ready)
      expect(ready_req.account_facing_setup_state).to eq('ready')
      ready_req.destroy!
      blocked_req = Bloomwire::WhatsappSetupRequest.create!(account: account, status: 'blocked', bloomwire_whatsapp_setup: blocked)
      expect(blocked_req.account_facing_setup_state).to eq('blocked')
    end
  end
end
