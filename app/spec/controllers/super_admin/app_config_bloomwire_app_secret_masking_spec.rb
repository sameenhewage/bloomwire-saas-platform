require 'rails_helper'

# Bloomwire Phase 2A (ADR-0003): mask the SuperAdmin WhatsApp Embedded App Secret under
# BLOOMWIRE_PRIVACY_HARDENING. With privacy hardening OFF (or master OFF) behavior must stay
# byte-for-byte stock Chatwoot. Fake secrets only.
RSpec.describe 'Super Admin WhatsApp Embedded App Secret masking (Bloomwire Phase 2A)', type: :request do
  let(:super_admin) { create(:super_admin) }
  let(:fake_secret) { 'fake-test-app-secret-do-not-use' }

  before do
    sign_in(super_admin, scope: :super_admin)
    set_config('WHATSAPP_APP_SECRET', fake_secret)
  end

  def set_config(key, value)
    config = InstallationConfig.where(name: key).first_or_initialize
    config.value = value
    config.locked = false
    config.save!
    GlobalConfig.clear_cache
  end

  def app_secret_input
    response.body[/<input[^>]*name="app_config\[WHATSAPP_APP_SECRET\]"[^>]*>/]
  end

  describe 'GET /super_admin/app_config?config=whatsapp_embedded' do
    context 'without Bloomwire privacy hardening (stock Chatwoot baseline)' do
      it 'echoes the stored App Secret in the rendered form (documents the pre-fix exposure)' do
        get '/super_admin/app_config?config=whatsapp_embedded'
        expect(response).to have_http_status(:success)
        expect(response.body).to include(fake_secret)
      end
    end

    context 'when master is ON but privacy hardening is OFF (stock preserved)' do
      before { set_config('BLOOMWIRE_MODE_ENABLED', true) }

      it 'still renders stock behavior (App Secret echoed)' do
        get '/super_admin/app_config?config=whatsapp_embedded'
        expect(response.body).to include(fake_secret)
      end
    end

    context 'when master is ON and privacy hardening is ON' do
      before do
        set_config('BLOOMWIRE_MODE_ENABLED', true)
        set_config('BLOOMWIRE_PRIVACY_HARDENING', true)
      end

      it 'never echoes the stored App Secret anywhere in the response' do
        get '/super_admin/app_config?config=whatsapp_embedded'
        expect(response).to have_http_status(:success)
        expect(response.body).not_to include(fake_secret)
      end

      it 'renders the App Secret field as a password input (not a text field)' do
        get '/super_admin/app_config?config=whatsapp_embedded'
        expect(app_secret_input).to be_present
        expect(app_secret_input).to include('type="password"')
        expect(app_secret_input).not_to include(fake_secret)
      end
    end
  end

  describe 'POST /super_admin/app_config?config=whatsapp_embedded (save flow)' do
    context 'when master is ON and privacy hardening is ON' do
      before do
        set_config('BLOOMWIRE_MODE_ENABLED', true)
        set_config('BLOOMWIRE_PRIVACY_HARDENING', true)
      end

      it 'keeps the existing App Secret when submitted blank (no accidental wipe)' do
        post '/super_admin/app_config?config=whatsapp_embedded', params: {
          app_config: { WHATSAPP_APP_SECRET: '', WHATSAPP_APP_ID: 'fake-app-id' }
        }
        expect(GlobalConfig.get('WHATSAPP_APP_SECRET')['WHATSAPP_APP_SECRET']).to eq(fake_secret)
        expect(GlobalConfig.get('WHATSAPP_APP_ID')['WHATSAPP_APP_ID']).to eq('fake-app-id')
      end

      it 'updates the App Secret when a new non-blank value is provided' do
        post '/super_admin/app_config?config=whatsapp_embedded', params: {
          app_config: { WHATSAPP_APP_SECRET: 'fake-new-secret' }
        }
        expect(GlobalConfig.get('WHATSAPP_APP_SECRET')['WHATSAPP_APP_SECRET']).to eq('fake-new-secret')
      end
    end

    context 'when privacy hardening is OFF (stock save behavior preserved)' do
      it 'saves a non-secret config (facebook) normally' do
        post '/super_admin/app_config?config=facebook', params: { app_config: { FB_APP_ID: 'fake-fb-id' } }
        expect(GlobalConfig.get('FB_APP_ID')['FB_APP_ID']).to eq('fake-fb-id')
      end
    end
  end
end
