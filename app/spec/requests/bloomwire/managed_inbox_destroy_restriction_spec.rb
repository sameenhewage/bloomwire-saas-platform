require 'rails_helper'

# The former Phase 11B.5B managed/provider DESTROY restriction is now LIFTED: an Account Administrator may remove
# ANY of their own inboxes (universal "Remove inbox"). A WhatsApp delete (any source, when Bloomwire mode is ON)
# routes through the Meta-safe async deprovision (Bloomwire::WhatsappInboxDeprovisionService → no Meta call); every
# other inbox type uses the stock DeleteObjectJob. This spec pins that universal-delete routing AND the STILL-ACTIVE
# provider WEBHOOK-registration restriction (inboxes#register_webhook stays 403 when BLOOMWIRE_RESTRICT_PROVIDER_SETUP
# is ON). Agents stay on the existing InboxPolicy (admin-only) path (401); reset_secret / sync_templates / health are
# untouched; OFF (master OFF) == stock Chatwoot.
RSpec.describe 'Bloomwire managed inbox destroy + webhook registration restriction', type: :request do
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

  # Build a managed/provider inbox owned by `account`. Some channel factories attach their auto-created inbox
  # to a different account (e.g. line uses an `inbox` association), so we pin ownership defensively.
  def managed_inbox(factory, **)
    channel = create(factory, account: account, **)
    inbox = channel.inbox
    inbox.update!(account: account) unless inbox.account_id == account.id
    inbox
  end

  def whatsapp_cloud_inbox
    managed_inbox(:channel_whatsapp, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false)
  end

  def expect_blocked
    expect(response).to have_http_status(:forbidden)
    expect(response.parsed_body['error']).to eq(restricted_message)
    expect(response.parsed_body['managed_by_ops']).to be(true)
  end

  before { GlobalConfig.clear_cache }

  describe 'when provider-setup restriction is ON' do
    before { enable_restriction }

    it 'allows an administrator to remove the managed WhatsApp inbox via the Meta-safe async deprovision (no DeleteObjectJob, no Meta call)' do
      inbox = whatsapp_cloud_inbox
      expect(DeleteObjectJob).not_to receive(:perform_later)
      expect(Whatsapp::FacebookApiClient).not_to receive(:new)
      expect do
        delete "/api/v1/accounts/#{account.id}/inboxes/#{inbox.id}", headers: administrator.create_new_auth_token, as: :json
      end.to have_enqueued_job(Bloomwire::WhatsappInboxDeprovisionJob)
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['managed_by_ops']).to be_nil
    end

    {
      'email' => :channel_email,
      'sms' => :channel_sms,
      'line' => :channel_line,
      'telegram' => :channel_telegram
    }.each do |label, factory|
      it "allows an administrator to destroy a #{label} provider inbox via the stock DeleteObjectJob" do
        inbox = managed_inbox(factory)
        expect(Bloomwire::WhatsappInboxDeprovisionJob).not_to receive(:perform_later)
        expect(DeleteObjectJob).to receive(:perform_later)
        delete "/api/v1/accounts/#{account.id}/inboxes/#{inbox.id}", headers: administrator.create_new_auth_token, as: :json
        expect(response).to have_http_status(:ok)
        expect(response.parsed_body['managed_by_ops']).to be_nil
      end
    end

    it 'still allows an administrator to destroy a web_widget inbox (stock)' do
      inbox = managed_inbox(:channel_widget)
      expect(DeleteObjectJob).to receive(:perform_later)
      delete "/api/v1/accounts/#{account.id}/inboxes/#{inbox.id}", headers: administrator.create_new_auth_token, as: :json
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['managed_by_ops']).to be_nil
    end

    it 'still allows an administrator to destroy an api inbox (stock)' do
      inbox = managed_inbox(:channel_api)
      expect(DeleteObjectJob).to receive(:perform_later)
      delete "/api/v1/accounts/#{account.id}/inboxes/#{inbox.id}", headers: administrator.create_new_auth_token, as: :json
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['managed_by_ops']).to be_nil
    end

    it 'blocks an administrator from re-registering a provider webhook (403, service not invoked)' do
      inbox = whatsapp_cloud_inbox
      expect(Whatsapp::WebhookSetupService).not_to receive(:new)
      post "/api/v1/accounts/#{account.id}/inboxes/#{inbox.id}/register_webhook", headers: administrator.create_new_auth_token, as: :json
      expect_blocked
    end

    it 'leaves agent destroy on the existing InboxPolicy path (not the Bloomwire guard)' do
      inbox = whatsapp_cloud_inbox
      delete "/api/v1/accounts/#{account.id}/inboxes/#{inbox.id}", headers: agent.create_new_auth_token, as: :json
      expect(response).to have_http_status(:unauthorized)
      expect(response.parsed_body['managed_by_ops']).to be_nil
    end

    # Out-of-scope existing ops: this slice must NOT touch reset_secret / sync_templates / health.
    it 'does not block reset_secret on an api inbox' do
      inbox = managed_inbox(:channel_api)
      post "/api/v1/accounts/#{account.id}/inboxes/#{inbox.id}/reset_secret", headers: administrator.create_new_auth_token, as: :json
      expect(response).not_to have_http_status(:forbidden)
      expect(response.parsed_body['managed_by_ops']).to be_nil
    end

    it 'does not block sync_templates on a whatsapp inbox' do
      inbox = whatsapp_cloud_inbox
      post "/api/v1/accounts/#{account.id}/inboxes/#{inbox.id}/sync_templates", headers: administrator.create_new_auth_token, as: :json
      expect(response).not_to have_http_status(:forbidden)
      expect(response.parsed_body['managed_by_ops']).to be_nil
    end

    it 'does not block health on a whatsapp cloud inbox' do
      inbox = whatsapp_cloud_inbox
      allow(Whatsapp::HealthService).to receive(:new).and_return(instance_double(Whatsapp::HealthService, fetch_health_status: {}))
      get "/api/v1/accounts/#{account.id}/inboxes/#{inbox.id}/health", headers: administrator.create_new_auth_token, as: :json
      expect(response).not_to have_http_status(:forbidden)
    end
  end

  describe 'when provider-setup restriction is OFF (stock Chatwoot)' do
    it 'allows an administrator to destroy a managed WhatsApp inbox (stock)' do
      inbox = whatsapp_cloud_inbox
      expect(DeleteObjectJob).to receive(:perform_later)
      delete "/api/v1/accounts/#{account.id}/inboxes/#{inbox.id}", headers: administrator.create_new_auth_token, as: :json
      expect(response).to have_http_status(:ok)
    end

    it 'allows an administrator to re-register a provider webhook (stock)' do
      inbox = whatsapp_cloud_inbox
      allow(Whatsapp::WebhookSetupService).to receive(:new).and_return(instance_double(Whatsapp::WebhookSetupService, register_callback: true))
      post "/api/v1/accounts/#{account.id}/inboxes/#{inbox.id}/register_webhook", headers: administrator.create_new_auth_token, as: :json
      expect(response).to have_http_status(:ok)
    end

    it 'routes a WhatsApp delete through the Meta-safe deprovision when master mode is ON (restrict OFF)' do
      set_toggle('BLOOMWIRE_MODE_ENABLED', true) # master only; provider-setup toggle stays OFF
      inbox = whatsapp_cloud_inbox
      expect(DeleteObjectJob).not_to receive(:perform_later)
      expect do
        delete "/api/v1/accounts/#{account.id}/inboxes/#{inbox.id}", headers: administrator.create_new_auth_token, as: :json
      end.to have_enqueued_job(Bloomwire::WhatsappInboxDeprovisionJob)
      expect(response).to have_http_status(:ok)
    end
  end
end
