require 'rails_helper'

# Phase 11B.4B: when Bloomwire mode + BLOOMWIRE_RESTRICT_PROVIDER_SETUP are ON, business account ADMINISTRATORS
# cannot create or update inbox/channel types that store EXTERNAL credentials via inboxes#create / #update
# (email, sms, line, telegram, and enterprise voice). These are Ops/SuperAdmin-owned in managed mode. Core
# channels (web_widget) and api inboxes stay allowed; WhatsApp keeps its own native guard; agents stay on the
# existing InboxPolicy (admin-only) path, unchanged. OFF == stock Chatwoot. 403 with a non-secret message;
# no secrets/tokens/credentials/provider ids read or echoed. Fake values only; the ON guard short-circuits
# before channel build / token exchange / persistence.
RSpec.describe 'Bloomwire external-credential channel inbox restriction', type: :request do
  let(:account) { create(:account) }
  let!(:administrator) { create(:user, account: account, role: :administrator) }
  let!(:agent) { create(:user, account: account, role: :agent) }
  let(:restricted_message) { 'Provider and channel setup is managed by Bloomwire Ops. Please contact support.' }

  def channel_class(type)
    { 'email' => Channel::Email, 'sms' => Channel::Sms, 'line' => Channel::Line, 'telegram' => Channel::Telegram }[type]
  end

  def line_create_channel
    { type: 'line', line_channel_id: SecureRandom.uuid, line_channel_secret: SecureRandom.uuid, line_channel_token: SecureRandom.uuid }
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

  def create_params(type)
    {
      'email' => { name: 'Ext', channel: { type: 'email', email: 'ext@test.com' } },
      'sms' => { name: 'Ext', channel: { type: 'sms', phone_number: '+15551230000', provider_config: { test: 'test' } } },
      'line' => { name: 'Ext', channel: line_create_channel },
      'telegram' => { name: 'Ext', channel: { type: 'telegram', bot_token: 'fake-bot-token' } }
    }[type]
  end

  def expect_blocked
    expect(response).to have_http_status(:forbidden)
    expect(response.parsed_body['error']).to eq(restricted_message)
    expect(response.parsed_body['managed_by_ops']).to be(true)
  end

  before { GlobalConfig.clear_cache }

  describe 'when provider-setup restriction is ON' do
    before { enable_restriction }

    %w[email sms line telegram].each do |type|
      it "blocks an administrator from creating a #{type} inbox (403, no side effect)" do
        klass = channel_class(type)
        ch_before = klass.count
        inbox_before = Inbox.count
        post "/api/v1/accounts/#{account.id}/inboxes",
             headers: administrator.create_new_auth_token, params: create_params(type), as: :json
        expect_blocked
        expect(klass.count).to eq(ch_before)
        expect(Inbox.count).to eq(inbox_before)
      end
    end

    it 'still allows an administrator to create a web_widget inbox' do
      expect do
        post "/api/v1/accounts/#{account.id}/inboxes",
             headers: administrator.create_new_auth_token,
             params: { name: 'WW', channel: { type: 'web_widget', website_url: 'test.com' } }, as: :json
      end.to change(Channel::WebWidget, :count).by(1)
      expect(response).to have_http_status(:success)
    end

    it 'still allows an administrator to create an api inbox' do
      expect do
        post "/api/v1/accounts/#{account.id}/inboxes",
             headers: administrator.create_new_auth_token,
             params: { name: 'API', channel: { type: 'api', webhook_url: 'http://test.com' } }, as: :json
      end.to change(Channel::Api, :count).by(1)
      expect(response).to have_http_status(:success)
    end

    it 'blocks an administrator from updating an existing email channel credentials (403, unchanged)' do
      channel = create(:channel_email, account: account, imap_login: 'old@test.com', imap_password: 'oldpass', imap_enabled: true)
      inbox = channel.inbox
      patch "/api/v1/accounts/#{account.id}/inboxes/#{inbox.id}",
            headers: administrator.create_new_auth_token,
            params: { channel: { imap_login: 'new@test.com', imap_password: 'newpass' } }, as: :json
      expect_blocked
      expect(channel.reload.imap_login).to eq('old@test.com')
      expect(channel.reload.imap_password).to eq('oldpass')
    end

    it 'blocks an administrator from updating an existing sms channel (403, phone unchanged)' do
      channel = create(:channel_sms, account: account)
      original_phone = channel.phone_number
      patch "/api/v1/accounts/#{account.id}/inboxes/#{channel.inbox.id}",
            headers: administrator.create_new_auth_token,
            params: { channel: { phone_number: '+19998887777' } }, as: :json
      expect_blocked
      expect(channel.reload.phone_number).to eq(original_phone)
    end

    it 'still allows an administrator to update a web_widget channel config' do
      channel = create(:channel_widget, account: account)
      patch "/api/v1/accounts/#{account.id}/inboxes/#{channel.inbox.id}",
            headers: administrator.create_new_auth_token,
            params: { channel: { widget_color: '#FF0000' } }, as: :json
      expect(response).to have_http_status(:success)
    end

    it 'leaves agent create blocked by the existing InboxPolicy (not the Bloomwire guard)' do
      post "/api/v1/accounts/#{account.id}/inboxes",
           headers: agent.create_new_auth_token, params: create_params('email'), as: :json
      expect(response).to have_http_status(:unauthorized)
      expect(response.parsed_body['managed_by_ops']).to be_nil
    end
  end

  describe 'when provider-setup restriction is OFF (stock Chatwoot)' do
    it 'allows an administrator to create an email inbox' do
      expect do
        post "/api/v1/accounts/#{account.id}/inboxes",
             headers: administrator.create_new_auth_token, params: create_params('email'), as: :json
      end.to change(Channel::Email, :count).by(1)
      expect(response).to have_http_status(:success)
    end

    it 'does not intercept when master mode is ON but BLOOMWIRE_RESTRICT_PROVIDER_SETUP is OFF' do
      set_toggle('BLOOMWIRE_MODE_ENABLED', true) # master only; provider-setup toggle stays OFF
      expect do
        post "/api/v1/accounts/#{account.id}/inboxes",
             headers: administrator.create_new_auth_token, params: create_params('email'), as: :json
      end.to change(Channel::Email, :count).by(1)
      expect(response).to have_http_status(:success)
    end
  end
end
