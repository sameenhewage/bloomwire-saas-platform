require 'rails_helper'

RSpec.describe 'Super Admin Bloomwire Config', type: :request do
  let(:super_admin) { create(:super_admin) }

  before { GlobalConfig.clear_cache }

  def set_toggle(key, value)
    config = InstallationConfig.where(name: key).first_or_initialize
    config.value = value
    config.locked = false
    config.save!
    GlobalConfig.clear_cache
  end

  describe 'GET /super_admin/bloomwire_config' do
    context 'when unauthenticated' do
      it 'redirects to the super admin login (forbidden)' do
        get '/super_admin/bloomwire_config'
        expect(response).to have_http_status(:redirect)
      end
    end

    context 'when signed in as a tenant workspace user' do
      it 'is forbidden — a tenant :user session does not grant the :super_admin scope' do
        sign_in(create(:user), scope: :user)
        get '/super_admin/bloomwire_config'
        expect(response).to have_http_status(:redirect)
      end
    end

    context 'when signed in as a super admin' do
      before { sign_in(super_admin, scope: :super_admin) }

      it 'is reachable as the bootstrap surface even though master is OFF' do
        get '/super_admin/bloomwire_config'
        expect(response).to have_http_status(:success)
        expect(response.body).to include(Bloomwire::Features::MASTER)
      end

      it 'renders sub-feature controls disabled while master is OFF' do
        get '/super_admin/bloomwire_config'
        expect(response.body).to include('<fieldset disabled')
      end

      it 'unlocks sub-feature controls when master is ON and privacy hardening is ON' do
        set_toggle(Bloomwire::Features::MASTER, true)
        set_toggle('BLOOMWIRE_PRIVACY_HARDENING', true)
        get '/super_admin/bloomwire_config'
        expect(response.body).not_to include('<fieldset disabled')
      end
    end
  end

  describe 'POST /super_admin/bloomwire_config' do
    context 'when unauthenticated' do
      it 'redirects and does not change anything' do
        post '/super_admin/bloomwire_config', params: { bloomwire_config: { BLOOMWIRE_MODE_ENABLED: 'true' } }
        expect(response).to have_http_status(:redirect)
        expect(Bloomwire::Features.master_enabled?).to be(false)
      end
    end

    context 'when signed in as a super admin' do
      before { sign_in(super_admin, scope: :super_admin) }

      it 'enables the master toggle from the UI (bootstrap; no out-of-band DB edit)' do
        post '/super_admin/bloomwire_config', params: { bloomwire_config: { BLOOMWIRE_MODE_ENABLED: 'true' } }
        expect(response).to have_http_status(:redirect)
        expect(Bloomwire::Features.master_enabled?).to be(true)
      end

      it 'ignores sub-feature changes while master is OFF (inert)' do
        post '/super_admin/bloomwire_config', params: { bloomwire_config: { BLOOMWIRE_PRIVACY_HARDENING: 'true' } }
        expect(Bloomwire::Features.raw_enabled?(:privacy_hardening)).to be(false)
      end

      it 'persists a sub-feature change when master is ON' do
        set_toggle(Bloomwire::Features::MASTER, true)
        post '/super_admin/bloomwire_config', params: { bloomwire_config: { BLOOMWIRE_RESTRICT_NATIVE_WHATSAPP_SETUP: 'true' } }
        expect(Bloomwire::Features.enabled?(:restrict_native_whatsapp_setup)).to be(true)
      end

      context 'with the managed-data privacy guard (server-side, fail-closed)' do
        it 'refuses to store managed-data toggles while privacy hardening is OFF, even via direct POST' do
          set_toggle(Bloomwire::Features::MASTER, true)

          post '/super_admin/bloomwire_config', params: { bloomwire_config: {
            BLOOMWIRE_MANAGED_WHATSAPP_ONBOARDING: 'true',
            BLOOMWIRE_GLOBAL_WEBHOOK_ROUTER: 'true'
          } }

          # stored raw values must remain OFF (controller refused them)
          expect(Bloomwire::Features.raw_enabled?(:managed_whatsapp_onboarding)).to be(false)
          expect(Bloomwire::Features.raw_enabled?(:global_webhook_router)).to be(false)
          # and the service must still report them disabled
          expect(Bloomwire::Features.enabled?(:managed_whatsapp_onboarding)).to be(false)
          expect(Bloomwire::Features.enabled?(:global_webhook_router)).to be(false)
        end

        it 'stores a managed-data toggle once privacy hardening is already ON' do
          set_toggle(Bloomwire::Features::MASTER, true)
          set_toggle('BLOOMWIRE_PRIVACY_HARDENING', true)

          post '/super_admin/bloomwire_config', params: { bloomwire_config: { BLOOMWIRE_MANAGED_WHATSAPP_ONBOARDING: 'true' } }

          expect(Bloomwire::Features.raw_enabled?(:managed_whatsapp_onboarding)).to be(true)
          expect(Bloomwire::Features.enabled?(:managed_whatsapp_onboarding)).to be(true)
        end
      end
    end
  end

  describe 'super admin navigation (regression for the Administrate index-route 500)' do
    before { sign_in(super_admin, scope: :super_admin) }

    it 'renders a super-admin page with the shared nav without raising bloomwire_configs#index' do
      get '/super_admin/bloomwire_config'
      expect(response).to have_http_status(:success)
    end

    it 'shows an explicit Bloomwire Features nav link' do
      get '/super_admin/bloomwire_config'
      expect(response.body).to include('Bloomwire Features')
      expect(response.body).to include(super_admin_bloomwire_config_path)
    end
  end
end
