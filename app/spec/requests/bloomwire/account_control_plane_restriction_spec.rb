require 'rails_helper'

# Phase 11B.2 (+ 11B.7B correction): when Bloomwire mode + BLOOMWIRE_RESTRICT_ACCOUNT_ADMIN are ON, business
# account ADMINISTRATORS are blocked from the Ops-owned account-control actions: ACCOUNT SETTINGS update and
# account WEBHOOKS. Phase 11B.7B re-scoped the guard so AGENT management (create/update/destroy/bulk_create) is
# NOW ALLOWED for the business admin (still subject to the stock Enterprise usage limit), per the business-owner
# permission matrix. The guard still runs AFTER Pundit, so non-admin agents stay on the stock policy path.
# OFF == stock Chatwoot. 403 (managed_by_ops) with a non-secret message; no secrets read or echoed. Fake values only.
RSpec.describe 'Bloomwire account control-plane restriction', type: :request do
  let(:account) { create(:account) }
  let!(:administrator) { create(:user, account: account, role: :administrator) }
  let!(:agent) { create(:user, account: account, role: :agent) }
  let(:super_admin) { create(:super_admin) }
  let(:restricted_message) { 'Account administration is managed by Bloomwire Ops. Please contact support.' }

  def set_toggle(key, value)
    config = InstallationConfig.where(name: key).first_or_initialize
    config.value = value
    config.locked = false
    config.save!
    GlobalConfig.clear_cache
  end

  def enable_restriction
    set_toggle('BLOOMWIRE_MODE_ENABLED', true)
    set_toggle('BLOOMWIRE_RESTRICT_ACCOUNT_ADMIN', true)
  end

  before { GlobalConfig.clear_cache }

  describe 'when restriction is ON' do
    before { enable_restriction }

    # Phase 11B.7B: agent management is NO LONGER part of the account-control restriction.
    it 'ALLOWS an administrator to create an agent in managed mode (11B.7B)' do
      expect do
        post "/api/v1/accounts/#{account.id}/agents",
             params: { agent: { name: 'New', email: 'new-agent@example.com', role: 'agent' } },
             headers: administrator.create_new_auth_token, as: :json
      end.to change(User, :count).by(1)
      expect(response).to have_http_status(:success)
      expect(response.parsed_body['managed_by_ops']).to be_nil
    end

    it 'ALLOWS an administrator to promote an agent to administrator in managed mode (11B.7B)' do
      target = agent
      patch "/api/v1/accounts/#{account.id}/agents/#{target.id}",
            params: { agent: { role: 'administrator' } },
            headers: administrator.create_new_auth_token, as: :json
      expect(response).to have_http_status(:success)
      expect(account.account_users.find_by(user_id: target.id).reload.role).to eq('administrator')
    end

    it 'ALLOWS an administrator to delete an agent in managed mode (11B.7B)' do
      target = agent
      delete "/api/v1/accounts/#{account.id}/agents/#{target.id}",
             headers: administrator.create_new_auth_token, as: :json
      expect(response).to have_http_status(:success)
      expect(account.account_users.exists?(user_id: target.id)).to be(false)
    end

    it 'ALLOWS an administrator to bulk-create agents in managed mode (11B.7B)' do
      expect do
        post "/api/v1/accounts/#{account.id}/agents/bulk_create",
             params: { emails: ['a@example.com', 'b@example.com'] },
             headers: administrator.create_new_auth_token, as: :json
      end.to change(User, :count).by(2)
      expect(response).to have_http_status(:success)
    end

    it 'still enforces the stock agent usage limit (402) in managed mode (11B.7B)' do
      # The stock `validate_limit` before_action is unchanged by 11B.7B; only the Bloomwire guard was removed.
      # OSS test env hardcodes usage_limits to max, so stub it to the current count to trip the stock limit.
      allow_any_instance_of(Account).to receive(:usage_limits).and_return(agents: account.users.count) # rubocop:disable RSpec/AnyInstance
      post "/api/v1/accounts/#{account.id}/agents",
           params: { agent: { name: 'Over', email: 'over-limit@example.com', role: 'agent' } },
           headers: administrator.create_new_auth_token, as: :json
      expect(response).to have_http_status(:payment_required)
    end

    it 'STILL blocks an administrator from updating account settings (403 managed_by_ops, name unchanged)' do
      original = account.name
      patch "/api/v1/accounts/#{account.id}",
            params: { name: 'Hacked Name' },
            headers: administrator.create_new_auth_token, as: :json
      expect(response).to have_http_status(:forbidden)
      expect(response.parsed_body['error']).to eq(restricted_message)
      expect(response.parsed_body['managed_by_ops']).to be(true)
      expect(account.reload.name).to eq(original)
    end

    it 'blocks an administrator from creating a webhook (403, no side effect)' do
      expect do
        post "/api/v1/accounts/#{account.id}/webhooks",
             params: { webhook: { url: 'https://example.com/hook', subscriptions: ['conversation_created'] } },
             headers: administrator.create_new_auth_token, as: :json
      end.not_to change(Webhook, :count)
      expect(response).to have_http_status(:forbidden)
    end

    it 'blocks an administrator from updating a webhook (403, unchanged)' do
      hook = create(:webhook, account: account, url: 'https://example.com/old')
      patch "/api/v1/accounts/#{account.id}/webhooks/#{hook.id}",
            params: { webhook: { url: 'https://example.com/new' } },
            headers: administrator.create_new_auth_token, as: :json
      expect(response).to have_http_status(:forbidden)
      expect(hook.reload.url).to eq('https://example.com/old')
    end

    it 'blocks an administrator from deleting a webhook (403, retained)' do
      hook = create(:webhook, account: account, url: 'https://example.com/keep')
      delete "/api/v1/accounts/#{account.id}/webhooks/#{hook.id}",
             headers: administrator.create_new_auth_token, as: :json
      expect(response).to have_http_status(:forbidden)
      expect(Webhook.exists?(hook.id)).to be(true)
    end

    it 'does not loosen anything: an agent stays blocked by the existing policy (not the Bloomwire guard)' do
      post "/api/v1/accounts/#{account.id}/agents",
           params: { agent: { name: 'X', email: 'x@example.com', role: 'agent' } },
           headers: agent.create_new_auth_token, as: :json
      expect(response).to have_http_status(:unauthorized)
      expect(response.parsed_body['managed_by_ops']).to be_nil
    end

    it 'does NOT block safe conversation/contact read workflows for an administrator' do
      get "/api/v1/accounts/#{account.id}/conversations", headers: administrator.create_new_auth_token, as: :json
      expect(response).to have_http_status(:success)
      get "/api/v1/accounts/#{account.id}/contacts", headers: administrator.create_new_auth_token, as: :json
      expect(response).to have_http_status(:success)
    end

    it 'does NOT block safe read workflows for an agent' do
      get "/api/v1/accounts/#{account.id}/conversations", headers: agent.create_new_auth_token, as: :json
      expect(response).to have_http_status(:success)
    end

    it 'keeps the SuperAdmin surface available (separate Devise scope, unaffected by the account-API guard)' do
      sign_in(super_admin, scope: :super_admin)
      get '/super_admin/bloomwire_whatsapp_setups'
      expect(response).to have_http_status(:success)
    end
  end

  describe 'when restriction is OFF (stock Chatwoot)' do
    it 'allows an administrator to create an agent when both toggles are OFF' do
      expect do
        post "/api/v1/accounts/#{account.id}/agents",
             params: { agent: { name: 'New', email: 'newoff@example.com', role: 'agent' } },
             headers: administrator.create_new_auth_token, as: :json
      end.to change(User, :count).by(1)
      expect(response).to have_http_status(:success)
    end

    it 'allows an administrator to update account settings when both toggles are OFF' do
      patch "/api/v1/accounts/#{account.id}",
            params: { name: 'Renamed' },
            headers: administrator.create_new_auth_token, as: :json
      expect(response).to have_http_status(:success)
      expect(account.reload.name).to eq('Renamed')
    end

    it 'does not intercept when master mode is ON but BLOOMWIRE_RESTRICT_ACCOUNT_ADMIN is OFF' do
      set_toggle('BLOOMWIRE_MODE_ENABLED', true) # master only; restrict toggle stays OFF
      expect do
        post "/api/v1/accounts/#{account.id}/webhooks",
             params: { webhook: { url: 'https://example.com/hook', subscriptions: ['conversation_created'] } },
             headers: administrator.create_new_auth_token, as: :json
      end.to change(Webhook, :count).by(1)
      expect(response).to have_http_status(:success)
    end
  end
end
