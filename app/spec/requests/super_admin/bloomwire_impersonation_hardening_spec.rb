require 'rails_helper'

# Phase 15C (Issue #74): the SuperAdmin "Impersonate user" control must not place the SSO token in a rendered
# href/URL. Impersonation is started via POST; the short-lived (5 min), single-use token is generated on demand
# and handed off via a Location header (not redirect_to, so it is not written to the Rails redirect log). The
# token is also already filtered from request-parameter logs. No auth weakening: only an approved platform
# admin (SuperAdmin scope) can initiate impersonation.
RSpec.describe 'SuperAdmin impersonation hardening (Phase 15C / Issue #74)', type: :request do
  let(:super_admin) { create(:super_admin) }
  let(:target) { create(:user) }

  describe 'GET /super_admin/users/:id (show page)' do
    before { sign_in(super_admin, scope: :super_admin) }

    it 'does not render sso_auth_token in any href' do
      get "/super_admin/users/#{target.id}"

      expect(response).to have_http_status(:success)
      expect(response.body).not_to include('sso_auth_token')
    end

    it 'renders the impersonation control as a POST form (not an anchor href)' do
      get "/super_admin/users/#{target.id}"
      doc = Nokogiri::HTML(response.body)
      form = doc.css("form[action='/super_admin/users/#{target.id}/impersonate']").first

      expect(form).to be_present
      expect(form['method']).to eq('post')
      # the old token-bearing anchor must be gone
      expect(doc.css("a[href*='sso_auth_token']")).to be_empty
    end
  end

  describe 'POST /super_admin/users/:id/impersonate' do
    it 'starts impersonation for an authorized platform admin via a token-less response body' do
      sign_in(super_admin, scope: :super_admin)
      post "/super_admin/users/#{target.id}/impersonate"

      expect(response).to have_http_status(:found)
      expect(response.body).to be_blank # head :found -> no body, so no token rendered anywhere
      location = response.headers['Location']
      expect(location).to include('/app/login')
      expect(location).to include('impersonation=true')
    end

    it 'hands off a valid single-use impersonation token (handoff works end to end)' do
      sign_in(super_admin, scope: :super_admin)
      post "/super_admin/users/#{target.id}/impersonate"

      token = Rack::Utils.parse_query(URI(response.headers['Location']).query)['sso_auth_token']
      expect(target.valid_sso_auth_token?(token)).to be(true)
      expect(target.sso_auth_token_impersonation?(token)).to be(true)
    end

    it 'refuses an unauthenticated request (no SSO handoff issued)' do
      post "/super_admin/users/#{target.id}/impersonate"

      expect(response).to have_http_status(:redirect)
      expect(response.headers['Location'].to_s).not_to include('/app/login')
    end

    it 'refuses a customer/business user without SuperAdmin scope (no SSO handoff issued)' do
      sign_in(target, scope: :user)
      post "/super_admin/users/#{target.id}/impersonate"

      expect(response).to have_http_status(:redirect)
      expect(response.headers['Location'].to_s).not_to include('/app/login')
    end
  end

  describe 'impersonation token consumption safety' do
    it 'fails safely for an invalid/expired token' do
      post '/auth/sign_in', params: { email: target.email, sso_auth_token: SecureRandom.hex(32) }, as: :json
      expect(response).to have_http_status(:unauthorized)
    end

    it 'is single-use: a reused token fails safely' do
      token = target.generate_sso_auth_token(impersonation: true)

      post '/auth/sign_in', params: { email: target.email, sso_auth_token: token }, as: :json
      expect(response).to have_http_status(:success)

      post '/auth/sign_in', params: { email: target.email, sso_auth_token: token }, as: :json
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'request-parameter logging' do
    it 'filters sso_auth_token from logged parameters' do
      filtered = ActiveSupport::ParameterFilter
                 .new(Rails.application.config.filter_parameters)
                 .filter('sso_auth_token' => 'supersecretvalue')

      expect(filtered['sso_auth_token']).to eq('[FILTERED]')
    end
  end
end
