require 'rails_helper'

RSpec.describe 'Super Admin Installation Config API', type: :request do
  let(:super_admin) { create(:super_admin) }

  describe 'GET /super_admin/installation_configs/new' do
    context 'when it is an unauthenticated super admin' do
      it 'returns unauthorized' do
        get '/super_admin/installation_configs/new'
        expect(response).to have_http_status(:redirect)
      end
    end

    context 'when it is an authenticated super admin' do
      let(:config) { create(:installation_config, { name: 'TESTCONFIG', value: 'TESTVALUE', locked: false }) }

      before do
        config
      end

      it 'shows the installation_configs create page' do
        sign_in(super_admin, scope: :super_admin)
        get '/super_admin/installation_configs/new'
        expect(response).to have_http_status(:success)
      end

      it 'shows the installation_configs edit page' do
        sign_in(super_admin, scope: :super_admin)
        editable_config = InstallationConfig.editable.first
        get "/super_admin/installation_configs/#{editable_config.id}/edit"
        expect(response).to have_http_status(:success)
      end

      it 'shows the installation_configs list page' do
        sign_in(super_admin, scope: :super_admin)
        get '/super_admin/installation_configs'
        expect(response).to have_http_status(:success)
        expect(response.body).to include(config.name)
      end
    end
  end

  describe 'PATCH /super_admin/installation_configs/:id' do
    context 'when it is an authenticated super admin' do
      it 'shows a regular success notice for config that does not require restart' do
        sign_in(super_admin, scope: :super_admin)
        config = create(:installation_config, name: 'TESTCONFIG', value: 'TESTVALUE', locked: false)

        patch "/super_admin/installation_configs/#{config.id}", params: {
          installation_config: { name: config.name, value: 'UPDATEDVALUE' }
        }

        expect(response).to have_http_status(:found)
        expect(flash[:notice]).to be_present
        expect(flash[:success]).to be_blank
      end

      it 'shows a restart success notice for runtime config changes' do
        sign_in(super_admin, scope: :super_admin)
        config = create(:installation_config, name: 'OTEL_PROVIDER', value: 'langfuse', locked: false)

        patch "/super_admin/installation_configs/#{config.id}", params: {
          installation_config: { name: config.name, value: 'langfuse' }
        }

        expect(response).to have_http_status(:found)
        expect(flash[:success]).to be_present
        expect(flash[:notice]).to be_blank
      end
    end
  end

  # Bloomwire managed-data toggles must not be persisted ON via this generic config editor while
  # privacy hardening is OFF — the path that bypasses SuperAdmin::BloomwireConfigsController's guard.
  describe 'Bloomwire managed-data privacy guard (generic write seam)' do
    before do
      sign_in(super_admin, scope: :super_admin)
      GlobalConfig.clear_cache
    end

    def seed_config(name, value)
      config = InstallationConfig.where(name: name).first_or_initialize
      config.value = value
      config.locked = false
      config.save!
      GlobalConfig.clear_cache
      config
    end

    context 'when privacy hardening is OFF' do
      it 'refuses to enable BLOOMWIRE_MANAGED_WHATSAPP_ONBOARDING via a direct PATCH' do
        config = seed_config('BLOOMWIRE_MANAGED_WHATSAPP_ONBOARDING', false)

        patch "/super_admin/installation_configs/#{config.id}", params: {
          installation_config: { name: config.name, value: 'true' }
        }

        expect(Bloomwire::Features.raw_enabled?(:managed_whatsapp_onboarding)).to be(false)
        expect(ActiveModel::Type::Boolean.new.cast(config.reload.value)).to be(false)
      end

      it 'refuses to enable BLOOMWIRE_GLOBAL_WEBHOOK_ROUTER via a direct PATCH' do
        config = seed_config('BLOOMWIRE_GLOBAL_WEBHOOK_ROUTER', false)

        patch "/super_admin/installation_configs/#{config.id}", params: {
          installation_config: { name: config.name, value: 'true' }
        }

        expect(Bloomwire::Features.raw_enabled?(:global_webhook_router)).to be(false)
        expect(ActiveModel::Type::Boolean.new.cast(config.reload.value)).to be(false)
      end

      it 'refuses to create a managed-data toggle ON via the generic create path' do
        post '/super_admin/installation_configs', params: {
          installation_config: { name: 'BLOOMWIRE_MANAGED_WHATSAPP_ONBOARDING', value: 'true' }
        }

        expect(Bloomwire::Features.raw_enabled?(:managed_whatsapp_onboarding)).to be(false)
      end
    end

    context 'when privacy hardening is ON' do
      before { seed_config('BLOOMWIRE_PRIVACY_HARDENING', true) }

      it 'allows enabling a managed-data toggle once privacy hardening is ON' do
        config = seed_config('BLOOMWIRE_MANAGED_WHATSAPP_ONBOARDING', false)

        patch "/super_admin/installation_configs/#{config.id}", params: {
          installation_config: { name: config.name, value: 'true' }
        }

        expect(Bloomwire::Features.raw_enabled?(:managed_whatsapp_onboarding)).to be(true)
        expect(ActiveModel::Type::Boolean.new.cast(config.reload.value)).to be(true)
      end
    end

    it 'leaves unrelated InstallationConfig updates unaffected (regression)' do
      config = create(:installation_config, name: 'TESTCONFIG', value: 'TESTVALUE', locked: false)

      patch "/super_admin/installation_configs/#{config.id}", params: {
        installation_config: { name: config.name, value: 'UPDATEDVALUE' }
      }

      expect(config.reload.value).to eq('UPDATEDVALUE')
    end
  end
end
