require 'rails_helper'

# Phase 10A.1: SuperAdmin-only WhatsApp real-hop readiness console. Shows Ready/Blocked + an actionable
# checklist, the callback path, and a masked runbook — without calling Meta and without ever rendering
# secret values. Gated by Bloomwire master mode (OFF => stock). Business/agent/unauthenticated users have
# no access. Fake values only.
RSpec.describe 'SuperAdmin Bloomwire WhatsApp real-hop readiness', type: :request do
  let(:super_admin) { create(:super_admin) }
  let(:account) { create(:account) }
  let(:app_secret) { 'FAKE-APP-SECRET-NEVER-RENDER' }
  let(:verify_token) { 'FAKE-VERIFY-TOKEN-NEVER-RENDER' }
  let(:pnid) { 'FAKE-PNID-4242' }
  let(:display) { '15551234242' }

  def set_cfg(key, value)
    config = InstallationConfig.where(name: key).first_or_initialize
    config.value = value
    config.locked = false
    config.save!
    GlobalConfig.clear_cache
  end

  def enable_all_config
    set_cfg('BLOOMWIRE_MODE_ENABLED', true)
    set_cfg('BLOOMWIRE_PRIVACY_HARDENING', true)
    set_cfg('BLOOMWIRE_GLOBAL_WEBHOOK_ROUTER', true)
    set_cfg('WHATSAPP_APP_SECRET', app_secret)
    set_cfg('BLOOMWIRE_WHATSAPP_GLOBAL_VERIFY_TOKEN', verify_token)
    set_cfg('BLOOMWIRE_WHATSAPP_PUBLIC_CALLBACK_HOST', 'smoke.example.com')
  end

  def ready_setup
    channel = create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud',
                                        phone_number: "+#{display}", sync_templates: false,
                                        validate_provider_config: false)
    channel.update!(provider_config: channel.provider_config.merge('phone_number_id' => pnid, 'source' => 'embedded_signup'))
    create(:bloomwire_whatsapp_setup, account: account, inbox: channel.inbox, channel_whatsapp: channel,
                                      phone_number_id: pnid, display_phone_number: display, setup_status: 'ready_for_webhook')
  end

  def readiness_path(setup)
    "/super_admin/bloomwire_whatsapp_setups/#{setup.id}/readiness"
  end

  before { GlobalConfig.clear_cache }

  describe 'authorization (SuperAdmin only)' do
    before { set_cfg('BLOOMWIRE_MODE_ENABLED', true) }

    it 'allows a signed-in super admin' do
      sign_in(super_admin, scope: :super_admin)
      get readiness_path(ready_setup)
      expect(response).to have_http_status(:success)
    end

    it 'denies an unauthenticated user (redirect to super admin sign in)' do
      setup = ready_setup
      get readiness_path(setup)
      expect(response).to have_http_status(:redirect)
      expect(response.redirect_url).to include('/super_admin/sign_in')
    end

    it 'denies a business/account administrator' do
      admin_user = create(:user, account: account, role: :administrator)
      sign_in(admin_user, scope: :user)
      setup = ready_setup
      get readiness_path(setup)
      expect(response).to have_http_status(:redirect)
      expect(response.redirect_url).to include('/super_admin/sign_in')
    end

    it 'denies an agent/staff user' do
      agent_user = create(:user, account: account, role: :agent)
      sign_in(agent_user, scope: :user)
      setup = ready_setup
      get readiness_path(setup)
      expect(response).to have_http_status(:redirect)
      expect(response.redirect_url).to include('/super_admin/sign_in')
    end
  end

  describe 'when Bloomwire master mode is OFF (stock - surface unavailable)' do
    before { sign_in(super_admin, scope: :super_admin) }

    it 'does not expose the readiness surface' do
      set_cfg('BLOOMWIRE_MODE_ENABLED', false)
      setup = create(:bloomwire_whatsapp_setup, account: account, setup_status: 'pending')
      get readiness_path(setup)
      expect(response).to have_http_status(:redirect)
      expect(response.redirect_url).not_to include('readiness')
    end
  end

  describe 'rendering (super admin, mode ON)' do
    before { sign_in(super_admin, scope: :super_admin) }

    it 'shows READY when all checks pass' do
      enable_all_config
      get readiness_path(ready_setup)
      expect(response).to have_http_status(:success)
      expect(response.body).to include('Ready')
      expect(response.body).not_to include('data-overall-status="blocked"')
    end

    it 'shows BLOCKED with actionable missing items when config is missing' do
      set_cfg('BLOOMWIRE_MODE_ENABLED', true)
      set_cfg('WHATSAPP_APP_SECRET', nil)
      setup = create(:bloomwire_whatsapp_setup, account: account, setup_status: 'pending')
      get readiness_path(setup)
      expect(response).to have_http_status(:success)
      expect(response.body).to include('Blocked')
      expect(response.body).to include('WHATSAPP_APP_SECRET')
    end

    it 'never renders the WHATSAPP_APP_SECRET value' do
      enable_all_config
      get readiness_path(ready_setup)
      expect(response.body).not_to include(app_secret)
    end

    it 'never renders the global verify token value' do
      enable_all_config
      get readiness_path(ready_setup)
      expect(response.body).not_to include(verify_token)
    end

    it 'shows the callback path' do
      enable_all_config
      get readiness_path(ready_setup)
      expect(response.body).to include('/bloomwire/webhooks/whatsapp')
    end
  end

  describe 'PR #35 setup mapping pages remain unchanged' do
    before do
      sign_in(super_admin, scope: :super_admin)
      set_cfg('BLOOMWIRE_MODE_ENABLED', true)
    end

    it 'still renders the setup show page' do
      setup = create(:bloomwire_whatsapp_setup, account: account, setup_status: 'pending')
      get "/super_admin/bloomwire_whatsapp_setups/#{setup.id}"
      expect(response).to have_http_status(:success)
    end

    it 'still lists setups on index' do
      create(:bloomwire_whatsapp_setup, account: account, setup_status: 'pending')
      get '/super_admin/bloomwire_whatsapp_setups'
      expect(response).to have_http_status(:success)
    end
  end
end
