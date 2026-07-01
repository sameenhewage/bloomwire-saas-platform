require 'rails_helper'

# Phase 17A — Bloomwire WhatsApp Ops surfaces: authorization + account-side boundary.
#
# The SuperAdmin manual setup-mapping CRUD and the customer-provisioning flow were REMOVED in Phase 17A. What
# remains and is locked here:
#   - Authenticated business admins/agents (the :user Devise scope) are DENIED every SuperAdmin Ops surface
#     (the read-only setups surface + the parked setup-requests queue).
#   - There is NO account-side route that mutates a Bloomwire::WhatsappSetup mapping; the only account-side
#     Bloomwire endpoint is the non-secret setup-REQUEST intake.
#   - With Bloomwire OFF the account-side intake is stock/inert (404).
#
# Backend authorization is the security boundary (request specs hitting controllers, not UI). All values are
# fake; no Meta/WhatsApp call is made. (Route absence for the removed CRUD is asserted in
# bloomwire_phase_17a_removed_routes_spec.rb.)
RSpec.describe 'Bloomwire WhatsApp Ops surfaces boundary', type: :request do
  let(:super_admin) { create(:super_admin) }
  let(:account) { create(:account) }
  let(:business_admin) { create(:user, account: account, role: :administrator) }
  let(:business_agent) { create(:user, account: account, role: :agent) }

  before { GlobalConfig.clear_cache }

  context 'when an authenticated business administrator targets the Ops surfaces' do
    before do
      bw_set_config('BLOOMWIRE_MODE_ENABLED', true)
      sign_in(business_admin, scope: :user)
    end

    it 'is denied the SuperAdmin setups index (redirected to super admin sign in)' do
      get '/super_admin/bloomwire_whatsapp_setups'
      expect(response).to have_http_status(:redirect)
      expect(response.redirect_url).to include('/super_admin/sign_in')
    end

    it 'is denied the SuperAdmin setup_requests queue' do
      get '/super_admin/bloomwire_whatsapp_setup_requests'
      expect(response).to have_http_status(:redirect)
      expect(response.redirect_url).to include('/super_admin/sign_in')
    end

    it 'cannot update a setup request via the SuperAdmin surface' do
      req = Bloomwire::WhatsappSetupRequest.request_for(account: account)
      patch "/super_admin/bloomwire_whatsapp_setup_requests/#{req.id}",
            params: { bloomwire_whatsapp_setup_request: { status: 'completed' } }
      expect(req.reload.status).not_to eq('completed')
      expect(response).to have_http_status(:redirect)
    end
  end

  context 'when an authenticated business agent targets the Ops surfaces' do
    before do
      bw_set_config('BLOOMWIRE_MODE_ENABLED', true)
      sign_in(business_agent, scope: :user)
    end

    it 'is denied the SuperAdmin setups index' do
      get '/super_admin/bloomwire_whatsapp_setups'
      expect(response).to have_http_status(:redirect)
      expect(response.redirect_url).to include('/super_admin/sign_in')
    end
  end

  # No account-side mapping-mutation endpoint exists; only the non-secret setup-REQUEST intake.
  context 'without any account-side mapping mutation endpoint' do
    it 'exposes no account route to create or modify a Bloomwire::WhatsappSetup mapping' do
      %i[post patch put delete].each do |verb|
        expect do
          Rails.application.routes.recognize_path("/api/v1/accounts/#{account.id}/bloomwire/whatsapp_setups",
                                                  method: verb)
        end.to raise_error(ActionController::RoutingError)
      end
    end

    it 'exposes only the non-secret setup REQUEST intake on the account side' do
      recognized = Rails.application.routes.recognize_path(
        "/api/v1/accounts/#{account.id}/bloomwire/whatsapp_setup_requests", method: :post
      )
      expect(recognized).to include(controller: 'api/v1/accounts/bloomwire/whatsapp_setup_requests', action: 'create')
    end
  end

  context 'when Bloomwire master mode is OFF (stock - account-side intake inert)' do
    before { bw_set_config('BLOOMWIRE_MODE_ENABLED', false) }

    it 'returns 404 for the account-side request intake and creates nothing' do
      post "/api/v1/accounts/#{account.id}/bloomwire/whatsapp_setup_requests",
           headers: business_admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:not_found)
      expect(Bloomwire::WhatsappSetupRequest.count).to eq(0)
    end
  end
end
