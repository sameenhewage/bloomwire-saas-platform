require 'rails_helper'

# Phase 11A: SuperAdmin/Ops queue for managed WhatsApp setup requests. Ops can view all requests, update
# status + status_reason, and jump to the setup mapping/readiness when a Bloomwire::WhatsappSetup is linked.
# Gated by Bloomwire master mode (OFF => stock). SuperAdmin-only. Never renders secrets. Fake values only.
RSpec.describe 'SuperAdmin Bloomwire WhatsApp setup requests', type: :request do
  let(:super_admin) { create(:super_admin) }
  let(:account) { create(:account) }

  def set_toggle(key, value)
    config = InstallationConfig.where(name: key).first_or_initialize
    config.value = value
    config.locked = false
    config.save!
    GlobalConfig.clear_cache
  end

  before { GlobalConfig.clear_cache }

  describe 'authorization' do
    before { set_toggle('BLOOMWIRE_MODE_ENABLED', true) }

    it 'redirects an unauthenticated user to the super admin sign in' do
      req = Bloomwire::WhatsappSetupRequest.create!(account: account, status: 'pending')
      get "/super_admin/bloomwire_whatsapp_setup_requests/#{req.id}"
      expect(response).to have_http_status(:redirect)
      expect(response.redirect_url).to include('/super_admin/sign_in')
    end
  end

  describe 'when Bloomwire master mode is OFF (stock - surface unavailable)' do
    before { sign_in(super_admin, scope: :super_admin) }

    it 'does not expose the request queue' do
      get '/super_admin/bloomwire_whatsapp_setup_requests'
      expect(response).to have_http_status(:redirect)
      expect(response.redirect_url).not_to include('bloomwire_whatsapp_setup_requests')
    end
  end

  describe 'when Bloomwire master mode is ON (super admin)' do
    before do
      sign_in(super_admin, scope: :super_admin)
      set_toggle('BLOOMWIRE_MODE_ENABLED', true)
    end

    it 'lists the request queue' do
      Bloomwire::WhatsappSetupRequest.create!(account: account, status: 'pending')
      get '/super_admin/bloomwire_whatsapp_setup_requests'
      expect(response).to have_http_status(:success)
    end

    it 'shows a request with account + status' do
      req = Bloomwire::WhatsappSetupRequest.create!(account: account, status: 'pending')
      get "/super_admin/bloomwire_whatsapp_setup_requests/#{req.id}"
      expect(response).to have_http_status(:success)
      expect(response.body).to include('pending')
    end

    it 'updates the status and status reason' do
      req = Bloomwire::WhatsappSetupRequest.create!(account: account, status: 'pending')
      patch "/super_admin/bloomwire_whatsapp_setup_requests/#{req.id}", params: {
        bloomwire_whatsapp_setup_request: { status: 'in_progress', status_reason: 'ops gathering Meta details' }
      }
      expect(req.reload.status).to eq('in_progress')
      expect(req.status_reason).to eq('ops gathering Meta details')
    end

    it 'can move a request to completed (stamps completed_at)' do
      req = Bloomwire::WhatsappSetupRequest.create!(account: account, status: 'in_progress')
      patch "/super_admin/bloomwire_whatsapp_setup_requests/#{req.id}", params: {
        bloomwire_whatsapp_setup_request: { status: 'completed' }
      }
      expect(req.reload.status).to eq('completed')
      expect(req.completed_at).to be_present
    end

    it 'links to the setup mapping + readiness when a setup is associated' do
      setup = create(:bloomwire_whatsapp_setup, account: account, setup_status: 'pending')
      req = Bloomwire::WhatsappSetupRequest.create!(account: account, status: 'ready_for_setup', bloomwire_whatsapp_setup: setup)
      get "/super_admin/bloomwire_whatsapp_setup_requests/#{req.id}"
      expect(response.body).to include("/super_admin/bloomwire_whatsapp_setups/#{setup.id}")
      expect(response.body).to include("/super_admin/bloomwire_whatsapp_setups/#{setup.id}/readiness")
    end

    it 'persists a same-account setup mapping link' do
      setup = create(:bloomwire_whatsapp_setup, account: account, setup_status: 'pending')
      req = Bloomwire::WhatsappSetupRequest.create!(account: account, status: 'pending')
      patch "/super_admin/bloomwire_whatsapp_setup_requests/#{req.id}", params: {
        bloomwire_whatsapp_setup_request: { bloomwire_whatsapp_setup_id: setup.id }
      }
      expect(req.reload.bloomwire_whatsapp_setup_id).to eq(setup.id)
    end

    it 'rejects linking a cross-account setup mapping (422, not persisted)' do
      other_account = create(:account)
      other_setup = create(:bloomwire_whatsapp_setup, account: other_account, setup_status: 'pending')
      req = Bloomwire::WhatsappSetupRequest.create!(account: account, status: 'pending')
      patch "/super_admin/bloomwire_whatsapp_setup_requests/#{req.id}", params: {
        bloomwire_whatsapp_setup_request: { bloomwire_whatsapp_setup_id: other_setup.id }
      }
      expect(response).to have_http_status(:unprocessable_entity)
      expect(req.reload.bloomwire_whatsapp_setup_id).to be_nil
    end

    it 'does not render secrets in the queue or show page' do
      set_toggle('WHATSAPP_APP_SECRET', 'FAKE-APP-SECRET-QUEUE')
      channel = create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', validate_provider_config: false, sync_templates: false)
      channel.update!(provider_config: channel.provider_config.merge('api_key' => 'FAKE-QUEUE-APIKEY'))
      setup = create(:bloomwire_whatsapp_setup, account: account, inbox: channel.inbox, channel_whatsapp: channel,
                                                phone_number_id: 'FAKE-PNID-Q', setup_status: 'configured')
      req = Bloomwire::WhatsappSetupRequest.create!(account: account, status: 'ready_for_setup', bloomwire_whatsapp_setup: setup)
      get '/super_admin/bloomwire_whatsapp_setup_requests'
      expect(response.body).not_to include('FAKE-APP-SECRET-QUEUE')
      expect(response.body).not_to include('FAKE-QUEUE-APIKEY')
      get "/super_admin/bloomwire_whatsapp_setup_requests/#{req.id}"
      expect(response.body).not_to include('FAKE-APP-SECRET-QUEUE')
      expect(response.body).not_to include('FAKE-QUEUE-APIKEY')
    end
  end
end
