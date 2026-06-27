require 'rails_helper'

# Phase 11B.3: when Bloomwire mode + BLOOMWIRE_RESTRICT_PROVIDER_SETUP are ON, business/customer account users
# (admins AND agents) are blocked from external provider/channel setup flows (Facebook page register/reauth,
# Twilio channel create, provider OAuth authorizations, Shopify connect). In managed mode these are owned by
# Bloomwire Ops/SuperAdmin (separate /super_admin surface, unaffected). The guard runs before the controller's
# own authorization, so endpoints that are only authentication-gated in stock (Facebook callbacks, Shopify
# auth) also block agents. OFF == stock Chatwoot. 403 with a non-secret message; no secrets/tokens/provider ids
# read or echoed. Fake values only; the ON guard short-circuits before any external API call.
RSpec.describe 'Bloomwire provider/channel setup restriction', type: :request do
  let(:account) { create(:account) }
  let!(:administrator) { create(:user, account: account, role: :administrator) }
  let!(:agent) { create(:user, account: account, role: :agent) }
  let(:restricted_message) { 'Provider and channel setup is managed by Bloomwire Ops. Please contact support.' }

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

    # --- Facebook callbacks: auth-only in stock, so AGENTS must also be blocked ---
    it 'blocks an administrator from registering a Facebook page (403, no side effect)' do
      params = attributes_for(:channel_facebook_page).merge(inbox_name: 'Blocked FB')
      fb_before = Channel::FacebookPage.count
      inbox_before = Inbox.count
      post "/api/v1/accounts/#{account.id}/callbacks/register_facebook_page",
           headers: administrator.create_new_auth_token, params: params, as: :json
      expect_blocked
      expect(Channel::FacebookPage.count).to eq(fb_before)
      expect(Inbox.count).to eq(inbox_before)
    end

    it 'blocks an AGENT from registering a Facebook page (auth-only endpoint, 403, no side effect)' do
      params = attributes_for(:channel_facebook_page).merge(inbox_name: 'Blocked FB')
      fb_before = Channel::FacebookPage.count
      post "/api/v1/accounts/#{account.id}/callbacks/register_facebook_page",
           headers: agent.create_new_auth_token, params: params, as: :json
      expect_blocked
      expect(Channel::FacebookPage.count).to eq(fb_before)
    end

    it 'blocks an agent from listing Facebook pages (auth-only endpoint, 403)' do
      post "/api/v1/accounts/#{account.id}/callbacks/facebook_pages",
           headers: agent.create_new_auth_token, as: :json
      expect_blocked
    end

    it 'blocks an administrator from reauthorizing a Facebook page (403)' do
      post "/api/v1/accounts/#{account.id}/callbacks/reauthorize_page",
           headers: administrator.create_new_auth_token, params: { inbox_id: 0, omniauth_token: 'x' }, as: :json
      expect_blocked
    end

    # --- Twilio channel create: admin-gated in stock ---
    it 'blocks an administrator from creating a Twilio channel (403, no side effect)' do
      params = { twilio_channel: { account_sid: 'sid', auth_token: 'token', phone_number: '+15551230000', name: 'Blocked Twilio', medium: 'sms' } }
      twilio_before = Channel::TwilioSms.count
      inbox_before = Inbox.count
      post "/api/v1/accounts/#{account.id}/channels/twilio_channel",
           headers: administrator.create_new_auth_token, params: params, as: :json
      expect_blocked
      expect(Channel::TwilioSms.count).to eq(twilio_before)
      expect(Inbox.count).to eq(inbox_before)
    end

    it 'blocks an agent from creating a Twilio channel (403)' do
      params = { twilio_channel: { account_sid: 'sid', auth_token: 'token', phone_number: '+15551230000', name: 'Blocked Twilio', medium: 'sms' } }
      post "/api/v1/accounts/#{account.id}/channels/twilio_channel",
           headers: agent.create_new_auth_token, params: params, as: :json
      expect_blocked
    end

    # --- Provider OAuth authorizations (shared OauthAuthorizationController base + Twitter) ---
    it 'blocks an administrator from starting Google OAuth (403, no url leaked)' do
      post "/api/v1/accounts/#{account.id}/google/authorization",
           headers: administrator.create_new_auth_token, params: { email: administrator.email }, as: :json
      expect_blocked
      expect(response.parsed_body['url']).to be_nil
    end

    it 'blocks an agent from starting Google OAuth (403)' do
      post "/api/v1/accounts/#{account.id}/google/authorization",
           headers: agent.create_new_auth_token, params: { email: agent.email }, as: :json
      expect_blocked
    end

    it 'blocks an administrator from starting Instagram OAuth (403)' do
      post "/api/v1/accounts/#{account.id}/instagram/authorization",
           headers: administrator.create_new_auth_token, as: :json
      expect_blocked
    end

    it 'blocks an administrator from starting Notion OAuth (403)' do
      post "/api/v1/accounts/#{account.id}/notion/authorization",
           headers: administrator.create_new_auth_token, as: :json
      expect_blocked
    end

    it 'blocks an administrator from starting Twitter OAuth (403)' do
      post "/api/v1/accounts/#{account.id}/twitter/authorization",
           headers: administrator.create_new_auth_token, as: :json
      expect_blocked
    end

    # --- Shopify connect: auth-only in stock, so AGENTS must also be blocked ---
    it 'blocks an AGENT from starting Shopify connect (auth-only endpoint, 403, no redirect url leaked)' do
      post "/api/v1/accounts/#{account.id}/integrations/shopify/auth",
           headers: agent.create_new_auth_token, params: { shop_domain: 'test-store.myshopify.com' }, as: :json
      expect_blocked
      expect(response.parsed_body).not_to have_key('redirect_url')
    end

    it 'blocks an administrator from starting Shopify connect (403)' do
      post "/api/v1/accounts/#{account.id}/integrations/shopify/auth",
           headers: administrator.create_new_auth_token, params: { shop_domain: 'test-store.myshopify.com' }, as: :json
      expect_blocked
    end
  end

  describe 'when provider-setup restriction is OFF (stock Chatwoot)' do
    it 'allows an administrator to start Google OAuth (stock url returned, not blocked)' do
      post "/api/v1/accounts/#{account.id}/google/authorization",
           headers: administrator.create_new_auth_token, params: { email: administrator.email }, as: :json
      expect(response).to have_http_status(:success)
      expect(response.parsed_body['url']).to be_present
      expect(response.parsed_body['managed_by_ops']).to be_nil
    end

    it 'preserves stock auth-only behavior: an agent can start Shopify connect when OFF' do
      post "/api/v1/accounts/#{account.id}/integrations/shopify/auth",
           headers: agent.create_new_auth_token, params: { shop_domain: 'test-store.myshopify.com' }, as: :json
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to have_key('redirect_url')
      expect(response.parsed_body['managed_by_ops']).to be_nil
    end

    it 'does not intercept when master mode is ON but BLOOMWIRE_RESTRICT_PROVIDER_SETUP is OFF' do
      set_toggle('BLOOMWIRE_MODE_ENABLED', true) # master only; provider-setup toggle stays OFF
      post "/api/v1/accounts/#{account.id}/google/authorization",
           headers: administrator.create_new_auth_token, params: { email: administrator.email }, as: :json
      expect(response).to have_http_status(:success)
      expect(response.parsed_body['managed_by_ops']).to be_nil
    end
  end
end
