require 'rails_helper'

# Phase 11B.3 (PR #44 reviewer fix): close the in-flight OAuth bypass. The provider OAuth/connect *starter*
# endpoints are guarded, but the *callback completion* endpoints (where the code->token exchange and
# channel/inbox/hook/token persistence happen) were not. If BLOOMWIRE_RESTRICT_PROVIDER_SETUP is flipped ON
# after a user started a flow while it was OFF, the callback could still persist provider credentials/channels.
# These callbacks resolve the account from the signed OAuth state; the restriction toggle is global, so the
# guard fails closed BEFORE any token exchange regardless of account resolution. OFF == stock Chatwoot.
# No secrets/tokens/provider payloads are read or echoed; fake values only.
RSpec.describe 'Bloomwire provider/channel OAuth callback restriction', type: :request do
  let(:account) { create(:account) }
  let(:state) { account.to_sgid(expires_in: 15.minutes).to_s }
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

    # Strong proof on the shared OauthCallbackController base (covers Google/Microsoft/Notion): even with a
    # fully stubbed successful token exchange, the callback must NOT exchange the code or persist a channel.
    it 'fails closed on the Google email callback before token exchange or persistence' do
      google_token = stub_request(:post, 'https://accounts.google.com/o/oauth2/token')
                     .to_return(status: 200,
                                body: { id_token: JWT.encode({ email: 'x@example.com', name: 't' }, nil, 'none'),
                                        access_token: 'AT', token_type: 'Bearer', refresh_token: 'RT' }.to_json,
                                headers: { 'Content-Type' => 'application/json' })
      expect do
        get google_callback_url, params: { code: 'thecode', state: state }
      end.not_to change(Channel::Email, :count)
      expect_blocked
      expect(google_token).not_to have_been_requested
    end

    it 'fails closed on the Microsoft email callback' do
      expect do
        get microsoft_callback_url, params: { code: 'thecode', state: state }
      end.not_to change(Channel::Email, :count)
      expect_blocked
    end

    it 'fails closed on the Notion integration callback (no hook persisted)' do
      expect do
        get notion_callback_url, params: { code: 'thecode', state: state }
      end.not_to change(Integrations::Hook, :count)
      expect_blocked
    end

    it 'fails closed on the Instagram callback (no instagram channel persisted)' do
      expect do
        get instagram_callback_url, params: { code: 'thecode', state: "#{account.id}|tok" }
      end.not_to change(Channel::Instagram, :count)
      expect_blocked
    end

    it 'fails closed on the TikTok callback (no tiktok channel persisted)' do
      tiktok_state = JWT.encode({ sub: account.id, iat: Time.current.to_i }, 'secret', 'HS256')
      expect do
        get tiktok_callback_url, params: { code: 'thecode', state: tiktok_state }
      end.not_to change(Channel::Tiktok, :count)
      expect_blocked
    end

    it 'fails closed on the Twitter callback (no twitter profile persisted)' do
      expect do
        get twitter_callback_url, params: { oauth_token: 'tok', oauth_verifier: 'ver' }
      end.not_to change(Channel::TwitterProfile, :count)
      expect_blocked
    end

    it 'fails closed on the Shopify callback (no hook persisted)' do
      expect do
        get shopify_callback_url, params: { code: 'thecode', state: 'st', shop: 'my-store.myshopify.com', hmac: 'h' }
      end.not_to change(Integrations::Hook, :count)
      expect_blocked
    end
  end

  describe 'when provider-setup restriction is OFF (stock not intercepted)' do
    it 'does not intercept the Google callback with a Bloomwire 403' do
      get google_callback_url, params: { code: 'thecode', state: state }
      expect(response).not_to have_http_status(:forbidden)
    end

    it 'does not intercept when master mode is ON but BLOOMWIRE_RESTRICT_PROVIDER_SETUP is OFF' do
      set_toggle('BLOOMWIRE_MODE_ENABLED', true)
      get google_callback_url, params: { code: 'thecode', state: state }
      expect(response).not_to have_http_status(:forbidden)
    end
  end
end
