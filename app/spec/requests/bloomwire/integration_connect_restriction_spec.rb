require 'rails_helper'

# Phase 11B.4C (+ 11B.7E): when Bloomwire mode + BLOOMWIRE_RESTRICT_PROVIDER_SETUP are ON, business account
# ADMINISTRATORS cannot create/update integration-connect records that store tokens / API keys / webhook URLs /
# provider settings via integrations/hooks#create|#update and integrations/slack#create|#update. These are
# Ops-owned in managed mode. Runtime/read endpoints (hooks#process_event, slack#list_all_channels) and #destroy
# stay allowed; agents remain on the existing admin-only policy/auth path, unchanged.
#
# Phase 11B.7E makes the integrations *admin surface* Ops-owned via UI hide + route block + the canAccessIntegrations
# capability — but the integrations CATALOG read (integrations/apps#index/#show) intentionally stays OPEN, because
# it is consumed by runtime conversation surfaces (ContactPanel Linear, video-call button, label suggestions);
# 403'ing it would break runtime. This spec asserts that catalog read stays open in managed mode.
# OFF == stock Chatwoot. 403 with a non-secret message; no secrets/tokens/settings read or echoed.
RSpec.describe 'Bloomwire integration connect restriction', type: :request do
  let(:account) { create(:account) }
  let!(:administrator) { create(:user, account: account, role: :administrator) }
  let!(:agent) { create(:user, account: account, role: :agent) }
  let(:restricted_message) { 'Provider and channel setup is managed by Bloomwire Ops. Please contact support.' }
  let(:inbox) { create(:inbox, account: account) }
  let(:dialogflow_params) do
    { app_id: 'dialogflow', inbox_id: inbox.id, settings: { project_id: 'xx', credentials: { test: 'test' }, region: 'europe-west1' } }
  end

  def set_toggle(key, value)
    config = InstallationConfig.where(name: key).first_or_initialize
    config.value = value
    config.locked = false
    config.save!
    GlobalConfig.clear_cache
  end

  def enable_restriction
    set_toggle('BLOOMWIRE_MODE_ENABLED', true)
    set_toggle('BLOOMWIRE_RESTRICT_PROVIDER_SETUP', true)
  end

  def expect_blocked
    expect(response).to have_http_status(:forbidden)
    expect(response.parsed_body['error']).to eq(restricted_message)
    expect(response.parsed_body['managed_by_ops']).to be(true)
  end

  before { GlobalConfig.clear_cache }

  describe 'when provider-setup restriction is ON' do
    before { enable_restriction }

    it 'blocks an administrator from creating an integration hook (403, no side effect)' do
      expect do
        post "/api/v1/accounts/#{account.id}/integrations/hooks",
             headers: administrator.create_new_auth_token, params: dialogflow_params, as: :json
      end.not_to change(Integrations::Hook, :count)
      expect_blocked
    end

    it 'blocks an administrator from updating an integration hook (403, settings unchanged)' do
      hook = create(:integrations_hook, account: account, app_id: 'custom_test', settings: { token: 'original-secret' })
      patch "/api/v1/accounts/#{account.id}/integrations/hooks/#{hook.id}",
            headers: administrator.create_new_auth_token, params: { settings: { token: 'rotated-secret' } }, as: :json
      expect_blocked
      expect(hook.reload.settings['token']).to eq('original-secret')
    end

    it 'blocks an administrator from connecting Slack (403, no hook persisted)' do
      expect do
        post "/api/v1/accounts/#{account.id}/integrations/slack",
             headers: administrator.create_new_auth_token, params: { code: SecureRandom.hex }, as: :json
      end.not_to change(Integrations::Hook, :count)
      expect_blocked
    end

    it 'blocks an administrator from updating the Slack hook (403, reference unchanged)' do
      hook = create(:integrations_hook, account: account, app_id: 'slack', reference_id: 'C-original')
      put "/api/v1/accounts/#{account.id}/integrations/slack",
          headers: administrator.create_new_auth_token, params: { reference_id: 'C-hacked' }, as: :json
      expect_blocked
      expect(hook.reload.reference_id).to eq('C-original')
    end

    it 'does NOT block hook#destroy (out of scope; admin still allowed)' do
      hook = create(:integrations_hook, account: account, app_id: 'custom_test2')
      delete "/api/v1/accounts/#{account.id}/integrations/hooks/#{hook.id}",
             headers: administrator.create_new_auth_token, as: :json
      expect(response).to have_http_status(:ok) # head :ok (empty body) — not the Bloomwire 403
    end

    it 'leaves agent hooks#create on the existing policy path (401, not the Bloomwire guard)' do
      post "/api/v1/accounts/#{account.id}/integrations/hooks",
           headers: agent.create_new_auth_token, params: dialogflow_params, as: :json
      expect(response).to have_http_status(:unauthorized)
      expect(response.parsed_body['managed_by_ops']).to be_nil
    end

    it 'leaves agent slack#create on the existing auth path (401, not the Bloomwire guard)' do
      post "/api/v1/accounts/#{account.id}/integrations/slack",
           headers: agent.create_new_auth_token, params: { code: SecureRandom.hex }, as: :json
      expect(response).to have_http_status(:unauthorized)
      expect(response.parsed_body['managed_by_ops']).to be_nil
    end

    # Phase 11B.7E: the catalog READ must stay open (runtime conversation surfaces consume it).
    it 'does NOT block the integrations catalog read (apps#index) for an administrator' do
      get "/api/v1/accounts/#{account.id}/integrations/apps",
          headers: administrator.create_new_auth_token, as: :json
      expect(response).to have_http_status(:success)
      expect(response.parsed_body['managed_by_ops']).to be_nil
    end

    it 'does NOT block the integrations catalog read (apps#index) for an agent (runtime)' do
      get "/api/v1/accounts/#{account.id}/integrations/apps",
          headers: agent.create_new_auth_token, as: :json
      expect(response).to have_http_status(:success)
    end
  end

  describe 'when provider-setup restriction is OFF (stock Chatwoot)' do
    it 'allows an administrator to create an integration hook' do
      expect do
        post "/api/v1/accounts/#{account.id}/integrations/hooks",
             headers: administrator.create_new_auth_token, params: dialogflow_params, as: :json
      end.to change(Integrations::Hook, :count).by(1)
      expect(response).to have_http_status(:success)
    end

    it 'does not intercept when master mode is ON but BLOOMWIRE_RESTRICT_PROVIDER_SETUP is OFF' do
      set_toggle('BLOOMWIRE_MODE_ENABLED', true) # master only; provider-setup toggle stays OFF
      expect do
        post "/api/v1/accounts/#{account.id}/integrations/hooks",
             headers: administrator.create_new_auth_token, params: dialogflow_params, as: :json
      end.to change(Integrations::Hook, :count).by(1)
      expect(response).to have_http_status(:success)
    end
  end
end
