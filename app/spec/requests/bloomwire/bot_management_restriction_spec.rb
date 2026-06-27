require 'rails_helper'

# Phase 11B.7D: when Bloomwire mode + BLOOMWIRE_RESTRICT_BOT_MANAGEMENT are ON, business/customer account
# users (admins AND agents) cannot manage bots: agent-bot list/show (which expose access_token / secret /
# bot_config), create/update/destroy/avatar, token & secret reset, and inbox-level set/disconnect bot. In
# managed mode bots are Ops/SuperAdmin-owned. OFF == stock Chatwoot. 403 with a non-secret message; no
# tokens/secrets/bot config read or echoed. Fake values only; the ON guard short-circuits before any change.
RSpec.describe 'Bloomwire bot-management restriction', type: :request do
  let(:account) { create(:account) }
  let!(:administrator) { create(:user, account: account, role: :administrator) }
  let!(:agent) { create(:user, account: account, role: :agent) }
  let(:agent_bot) { create(:agent_bot, account: account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:restricted_message) { 'Bot management is managed by Bloomwire Ops. Please contact support.' }

  def set_toggle(key, value)
    config = InstallationConfig.where(name: key).first_or_initialize
    config.value = value
    config.locked = false
    config.save!
    GlobalConfig.clear_cache
  end

  def expect_blocked
    expect(response).to have_http_status(:forbidden)
    expect(response.parsed_body['error']).to eq(restricted_message)
    expect(response.parsed_body['managed_by_ops']).to be(true)
  end

  before { GlobalConfig.clear_cache }

  describe 'when bot-management restriction is ON' do
    before do
      set_toggle('BLOOMWIRE_MODE_ENABLED', true)
      set_toggle('BLOOMWIRE_RESTRICT_BOT_MANAGEMENT', true)
    end

    it 'blocks an administrator from listing bots and leaks no secrets/config' do
      get "/api/v1/accounts/#{account.id}/agent_bots", headers: administrator.create_new_auth_token, as: :json
      expect_blocked
      expect(response.body).not_to include('access_token')
      expect(response.body).not_to include('secret')
      expect(response.body).not_to include('bot_config')
    end

    it 'blocks an administrator from showing a bot' do
      get "/api/v1/accounts/#{account.id}/agent_bots/#{agent_bot.id}", headers: administrator.create_new_auth_token, as: :json
      expect_blocked
    end

    it 'blocks an AGENT from listing bots too (reads expose access_token/bot_config)' do
      get "/api/v1/accounts/#{account.id}/agent_bots", headers: agent.create_new_auth_token, as: :json
      expect_blocked
    end

    it 'blocks an administrator from creating a bot (no side effect)' do
      expect do
        post "/api/v1/accounts/#{account.id}/agent_bots",
             params: { name: 'Bot', outgoing_url: 'http://example.com' },
             headers: administrator.create_new_auth_token, as: :json
      end.not_to change(AgentBot, :count)
      expect_blocked
    end

    it 'blocks an administrator from updating a bot (unchanged)' do
      patch "/api/v1/accounts/#{account.id}/agent_bots/#{agent_bot.id}",
            params: { name: 'Changed Name' }, headers: administrator.create_new_auth_token, as: :json
      expect_blocked
      expect(agent_bot.reload.name).not_to eq('Changed Name')
    end

    it 'blocks an administrator from deleting a bot (retained)' do
      bot = agent_bot
      delete "/api/v1/accounts/#{account.id}/agent_bots/#{bot.id}", headers: administrator.create_new_auth_token, as: :json
      expect_blocked
      expect(AgentBot.exists?(bot.id)).to be(true)
    end

    it 'blocks reset_access_token' do
      post "/api/v1/accounts/#{account.id}/agent_bots/#{agent_bot.id}/reset_access_token",
           headers: administrator.create_new_auth_token, as: :json
      expect_blocked
    end

    it 'blocks reset_secret' do
      post "/api/v1/accounts/#{account.id}/agent_bots/#{agent_bot.id}/reset_secret",
           headers: administrator.create_new_auth_token, as: :json
      expect_blocked
    end

    it 'blocks avatar delete' do
      delete "/api/v1/accounts/#{account.id}/agent_bots/#{agent_bot.id}/avatar",
             headers: administrator.create_new_auth_token, as: :json
      expect_blocked
    end

    it 'blocks the inbox-level agent_bot read (renders bot secrets otherwise)' do
      get "/api/v1/accounts/#{account.id}/inboxes/#{inbox.id}/agent_bot",
          headers: administrator.create_new_auth_token, as: :json
      expect_blocked
    end

    it 'blocks inbox-level set_agent_bot' do
      post "/api/v1/accounts/#{account.id}/inboxes/#{inbox.id}/set_agent_bot",
           params: { agent_bot: agent_bot.id }, headers: administrator.create_new_auth_token, as: :json
      expect_blocked
    end

    it 'blocks inbox-level disconnect (set_agent_bot with nil bot)' do
      post "/api/v1/accounts/#{account.id}/inboxes/#{inbox.id}/set_agent_bot",
           params: { agent_bot: nil }, headers: administrator.create_new_auth_token, as: :json
      expect_blocked
    end
  end

  describe 'when bot-management restriction is OFF (stock Chatwoot)' do
    it 'allows an administrator to list bots' do
      get "/api/v1/accounts/#{account.id}/agent_bots", headers: administrator.create_new_auth_token, as: :json
      expect(response).to have_http_status(:success)
    end

    it 'allows an administrator to create a bot' do
      expect do
        post "/api/v1/accounts/#{account.id}/agent_bots",
             params: { name: 'Bot', outgoing_url: 'http://example.com' },
             headers: administrator.create_new_auth_token, as: :json
      end.to change(AgentBot, :count).by(1)
      expect(response).to have_http_status(:success)
    end

    it 'does not intercept when master mode is ON but the bot toggle is OFF' do
      set_toggle('BLOOMWIRE_MODE_ENABLED', true) # master only; bot toggle stays OFF
      get "/api/v1/accounts/#{account.id}/agent_bots", headers: administrator.create_new_auth_token, as: :json
      expect(response).to have_http_status(:success)
    end
  end

  describe 'regression: restriction toggles coexist (bot + provider + account all ON)' do
    before do
      set_toggle('BLOOMWIRE_MODE_ENABLED', true)
      set_toggle('BLOOMWIRE_RESTRICT_BOT_MANAGEMENT', true)
      set_toggle('BLOOMWIRE_RESTRICT_PROVIDER_SETUP', true)
      set_toggle('BLOOMWIRE_RESTRICT_ACCOUNT_ADMIN', true)
    end

    it 'still ALLOWS business-admin agent management (11B.7B)' do
      expect do
        post "/api/v1/accounts/#{account.id}/agents",
             params: { agent: { name: 'Reg', email: 'reg-agent@example.com', role: 'agent' } },
             headers: administrator.create_new_auth_token, as: :json
      end.to change(User, :count).by(1)
      expect(response).to have_http_status(:success)
    end

    it 'still BLOCKS inbox creation (11B.7C)' do
      post "/api/v1/accounts/#{account.id}/inboxes",
           params: { name: 'WW', channel: { type: 'web_widget', website_url: 'test.com' } },
           headers: administrator.create_new_auth_token, as: :json
      expect(response).to have_http_status(:forbidden)
    end

    it 'still BLOCKS account settings update (11B.2/11B.7A)' do
      original = account.name
      patch "/api/v1/accounts/#{account.id}",
            params: { name: 'Hacked' }, headers: administrator.create_new_auth_token, as: :json
      expect(response).to have_http_status(:forbidden)
      expect(account.reload.name).to eq(original)
    end

    it 'BLOCKS bot management' do
      get "/api/v1/accounts/#{account.id}/agent_bots", headers: administrator.create_new_auth_token, as: :json
      expect_blocked
    end
  end
end
