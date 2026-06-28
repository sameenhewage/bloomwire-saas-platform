require 'rails_helper'

# Phase 12E — Ops observability for WhatsApp setup mappings (SuperAdmin surface).
#
# Ops/SuperAdmin must see each setup's non-secret operational state (readiness Ready/Blocked, request
# linked/unlinked) and MASKED routing identifiers — never a secret, full phone_number_id, or full phone
# number — reusing Bloomwire::WhatsappRealHopReadiness. Gated by Bloomwire master mode (OFF => stock).
# Fake values only; no Meta call.
RSpec.describe 'SuperAdmin Bloomwire WhatsApp setup observability', type: :request do
  let(:super_admin) { create(:super_admin) }
  let(:account) { create(:account) }
  let(:pnid) { 'PNID-OBS-123456' }
  let(:display) { '15551230077' }
  let(:api_key) { 'FAKE-OBS-APIKEY-DO-NOT-LEAK' }

  before do
    GlobalConfig.clear_cache
    sign_in(super_admin, scope: :super_admin)
  end

  def ready_setup
    create(:bloomwire_whatsapp_setup, :ready_for_webhook, account: account,
                                                          aligned_phone_number_id: pnid,
                                                          aligned_display_phone_number: display,
                                                          aligned_api_key: api_key)
  end

  context 'when Bloomwire master mode is ON' do
    before { bw_enable_all } # mode + privacy + router + app secret + verify token + public callback host

    it 'shows a Ready operational state on the index for a fully aligned setup' do
      ready_setup
      get '/super_admin/bloomwire_whatsapp_setups'
      expect(response).to have_http_status(:success)
      expect(response.body).to include('data-readiness="ready"')
    end

    it 'shows a Blocked operational state on the index for an incomplete setup' do
      create(:bloomwire_whatsapp_setup, account: account, setup_status: 'pending')
      get '/super_admin/bloomwire_whatsapp_setups'
      expect(response).to have_http_status(:success)
      expect(response.body).to include('data-readiness="blocked"')
    end

    it 'reflects request linked / unlinked per setup on the index' do
      setup = ready_setup
      get '/super_admin/bloomwire_whatsapp_setups'
      expect(response.body).to include('data-request="unlinked"')

      Bloomwire::WhatsappSetupRequest.create!(account: account, status: 'ready_for_setup', bloomwire_whatsapp_setup: setup)
      get '/super_admin/bloomwire_whatsapp_setups'
      expect(response.body).to include('data-request="linked"')
    end

    it 'masks the routing identifiers on the index (no full phone_number_id / phone number)' do
      ready_setup
      get '/super_admin/bloomwire_whatsapp_setups'
      expect(response.body).to include('****')
      expect(response.body).not_to include(pnid)
      expect(response.body).not_to include(display)
      expect(response.body).not_to include("+#{display}")
    end

    it 'masks identifiers and shows operational state on the show page' do
      setup = ready_setup
      get "/super_admin/bloomwire_whatsapp_setups/#{setup.id}"
      expect(response).to have_http_status(:success)
      expect(response.body).to include('****')
      expect(response.body).not_to include(pnid)
      expect(response.body).not_to include("+#{display}")
    end

    it 'never leaks the channel api_key or the app secret on index or show' do
      setup = ready_setup
      bw_set_config('WHATSAPP_APP_SECRET', 'FAKE-OBS-APP-SECRET')
      get '/super_admin/bloomwire_whatsapp_setups'
      expect(response.body).not_to include(api_key)
      expect(response.body).not_to include('FAKE-OBS-APP-SECRET')
      get "/super_admin/bloomwire_whatsapp_setups/#{setup.id}"
      expect(response.body).not_to include(api_key)
      expect(response.body).not_to include('FAKE-OBS-APP-SECRET')
    end

    it 'makes no Meta/Graph call while rendering observability' do
      ready_setup
      get '/super_admin/bloomwire_whatsapp_setups'
      get "/super_admin/bloomwire_whatsapp_setups/#{Bloomwire::WhatsappSetup.last.id}"
      expect(a_request(:any, /graph\.facebook\.com/)).not_to have_been_made
    end
  end

  context 'when Bloomwire master mode is OFF (stock - surface inert)' do
    before { bw_set_config('BLOOMWIRE_MODE_ENABLED', false) }

    it 'does not expose the observability surface' do
      get '/super_admin/bloomwire_whatsapp_setups'
      expect(response).to have_http_status(:redirect)
      expect(response.redirect_url).not_to include('bloomwire_whatsapp_setups')
    end
  end
end
