require 'rails_helper'

# Structured browser onboarding-trace sink. Admin-only + managed-mode-only (404 when off) + account-scoped +
# rate-limited + strict event/metadata allow-list. Never accepts/logs a sensitive value; a logging failure
# never breaks the caller (always 204 for an authorized, allow-listed event).
RSpec.describe 'Bloomwire WhatsApp onboarding trace endpoint', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:url) { "/api/v1/accounts/#{account.id}/bloomwire/whatsapp/onboarding_traces" }
  let(:valid_body) do
    { onboarding_attempt_id: 'att-abc-123456', event: 'onboarding_started', result: 'started', elapsed_ms: 10 }
  end

  # The GlobalConfig cache (Redis) is not rolled back between examples the way the DB is, so a prior example can
  # leave a Bloomwire flag cached ON. Start every example from a clean cache → the "stock/off" default is honoured.
  before { GlobalConfig.clear_cache }

  def enable_managed_mode
    bw_set_config('BLOOMWIRE_MODE_ENABLED', true)
    bw_set_config('BLOOMWIRE_PRIVACY_HARDENING', true)
    bw_set_config('BLOOMWIRE_RESTRICT_NATIVE_WHATSAPP_SETUP', true)
    bw_set_config('BLOOMWIRE_MANAGED_WHATSAPP_ONBOARDING', true)
  end

  context 'when managed self-serve is not active' do
    it 'is 404 when Bloomwire mode is OFF (stock)' do
      post url, headers: admin.create_new_auth_token, params: valid_body, as: :json
      expect(response).to have_http_status(:not_found)
    end
  end

  context 'when managed mode is active' do
    before { enable_managed_mode }

    # (19) account-scoped + admin-authorized.
    it 'accepts an allow-listed event from an account administrator (204) and emits a sanitized trace' do
      expect(Bloomwire::OnboardingTrace).to receive(:emit).with(
        hash_including(event: 'onboarding_started', source: 'browser',
                       account_id: account.id, actor_id: admin.id, attempt_id: 'att-abc-123456')
      ).and_call_original
      post url, headers: admin.create_new_auth_token, params: valid_body, as: :json
      expect(response).to have_http_status(:no_content)
    end

    it 'denies an agent (unauthorized/forbidden)' do
      post url, headers: agent.create_new_auth_token, params: valid_body, as: :json
      expect(response).to have_http_status(:unauthorized).or have_http_status(:forbidden)
    end

    it 'rejects an unauthenticated request' do
      post url, params: valid_body, as: :json
      expect(response).to have_http_status(:unauthorized)
    end

    # (18) strict allow-list: unknown event rejected; arbitrary/sensitive keys never reach the trace.
    it 'rejects an unknown event with 422 and logs nothing' do
      expect(Bloomwire::OnboardingTrace).not_to receive(:emit)
      post url, headers: admin.create_new_auth_token,
                params: valid_body.merge(event: 'arbitrary_event'), as: :json
      expect(response).to have_http_status(:unprocessable_entity)
    end

    # (Finding 4) Forbidden/unknown top-level keys are REJECTED (4xx) BEFORE strong-param filtering — not
    # silently dropped — and NO trace is emitted for a rejected request.
    it 'rejects an unknown top-level key with 4xx and logs nothing' do
      expect(Bloomwire::OnboardingTrace).not_to receive(:emit)
      post url, headers: admin.create_new_auth_token,
                params: valid_body.merge(arbitrary: 'nope'), as: :json
      expect(response).to have_http_status(:bad_request)
    end

    %w[code auth_code access_token token phone phone_number phone_number_id waba_id business_id app_id
       configuration_id url query message metadata].each do |sensitive_key|
      it "rejects the sensitive key '#{sensitive_key}' with 4xx and logs nothing" do
        expect(Bloomwire::OnboardingTrace).not_to receive(:emit)
        post url, headers: admin.create_new_auth_token,
                  params: valid_body.merge(sensitive_key => 'SENSITIVE-VALUE'), as: :json
        expect(response).to have_http_status(:bad_request)
        expect(response.body).not_to include('SENSITIVE-VALUE')
      end
    end

    it 'accepts a clean, fully allow-listed payload (204) and emits the sanitized trace' do
      expect(Bloomwire::OnboardingTrace).to receive(:emit).and_call_original
      post url, headers: admin.create_new_auth_token, params: {
        onboarding_attempt_id: 'att-abc-123456', event: 'create_request_failed',
        result: 'failure', elapsed_ms: 250, http_status: 502, error_code: 'http_502'
      }, as: :json
      expect(response).to have_http_status(:no_content)
    end

    # (20) logging failure never breaks the caller.
    it 'still returns 204 when the trace write fails (logging never breaks onboarding)' do
      allow(Bloomwire::OnboardingTrace).to receive(:emit).and_return(false)
      post url, headers: admin.create_new_auth_token, params: valid_body, as: :json
      expect(response).to have_http_status(:no_content)
    end

    it 'rate-limits abusive volumes (429)' do
      allow(Rails.cache).to receive(:increment).and_return(
        Api::V1::Accounts::Bloomwire::Whatsapp::OnboardingTracesController::RATE_LIMIT + 1
      )
      post url, headers: admin.create_new_auth_token, params: valid_body, as: :json
      expect(response).to have_http_status(:too_many_requests)
    end

    it 'is scoped to the account in the path (a foreign account cannot post traces here)' do
      other = create(:account)
      other_url = "/api/v1/accounts/#{other.id}/bloomwire/whatsapp/onboarding_traces"
      post other_url, headers: admin.create_new_auth_token, params: valid_body, as: :json
      expect(response).to have_http_status(:unauthorized).or have_http_status(:forbidden).or have_http_status(:not_found)
    end
  end
end
