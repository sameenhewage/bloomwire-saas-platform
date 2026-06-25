require 'rails_helper'

# Bloomwire Phase 2A slice 2 (ADR-0003): the generic Administrate installation_configs editor must also
# mask WHATSAPP_APP_SECRET (index/show display + edit form) and never wipe it on a blank submit, while
# privacy hardening is ON (master AND-gated via Bloomwire::Features). With privacy hardening OFF or master
# OFF every page is byte-for-byte stock Chatwoot. Fake secrets only.
RSpec.describe 'Super Admin InstallationConfig App Secret masking (Bloomwire Phase 2A)', type: :request do
  let(:super_admin) { create(:super_admin) }
  let(:fake_secret) { 'fake-installconfig-app-secret-xyz' }
  let!(:secret_config) { create(:installation_config, name: 'WHATSAPP_APP_SECRET', value: fake_secret, locked: false) }

  before do
    sign_in(super_admin, scope: :super_admin)
    GlobalConfig.clear_cache
  end

  def set_toggle(key, value)
    config = InstallationConfig.where(name: key).first_or_initialize
    config.value = value
    config.locked = false
    config.save!
    GlobalConfig.clear_cache
  end

  def app_secret_value_input
    response.body[/<input[^>]*name="installation_config\[value\]"[^>]*>/]
  end

  context 'when privacy hardening is ON (master ON + privacy ON)' do
    before do
      set_toggle('BLOOMWIRE_MODE_ENABLED', true)
      set_toggle('BLOOMWIRE_PRIVACY_HARDENING', true)
    end

    it 'does not render the secret in cleartext on the index page' do
      get '/super_admin/installation_configs'
      expect(response).to have_http_status(:success)
      expect(response.body).not_to include(fake_secret)
    end

    it 'does not render the secret in cleartext on the show page' do
      get "/super_admin/installation_configs/#{secret_config.id}"
      expect(response).to have_http_status(:success)
      expect(response.body).not_to include(fake_secret)
    end

    it 'renders a password input with no echoed value on the edit page' do
      get "/super_admin/installation_configs/#{secret_config.id}/edit"
      expect(response).to have_http_status(:success)
      expect(app_secret_value_input).to be_present
      expect(app_secret_value_input).to include('type="password"')
      expect(app_secret_value_input).not_to include(fake_secret)
      expect(response.body).not_to include(fake_secret)
    end

    it 'keeps the existing secret when updated with a blank value (no wipe)' do
      patch "/super_admin/installation_configs/#{secret_config.id}", params: {
        installation_config: { name: 'WHATSAPP_APP_SECRET', value: '' }
      }
      expect(secret_config.reload.value).to eq(fake_secret)
    end

    it 'updates the secret when a non-blank value is provided' do
      patch "/super_admin/installation_configs/#{secret_config.id}", params: {
        installation_config: { name: 'WHATSAPP_APP_SECRET', value: 'fake-new-installconfig-secret' }
      }
      expect(secret_config.reload.value).to eq('fake-new-installconfig-secret')
    end

    it 'still renders a non-secret config value on the index page (regression)' do
      create(:installation_config, name: 'FAKE_PLAIN_CONFIG', value: 'plain-visible-value', locked: false)
      get '/super_admin/installation_configs'
      expect(response.body).to include('plain-visible-value')
    end
  end

  context 'when privacy hardening is OFF (stock Chatwoot baseline)' do
    it 'renders the secret in cleartext on the index page' do
      get '/super_admin/installation_configs'
      expect(response.body).to include(fake_secret)
    end

    it 'renders the secret in cleartext on the show page' do
      get "/super_admin/installation_configs/#{secret_config.id}"
      expect(response.body).to include(fake_secret)
    end
  end

  context 'when BLOOMWIRE_PRIVACY_HARDENING is stored ON but master is OFF (AND-gate keeps it stock)' do
    before { set_toggle('BLOOMWIRE_PRIVACY_HARDENING', true) } # master stays OFF

    it 'renders the secret in cleartext because the master AND-gate forces the feature OFF' do
      get '/super_admin/installation_configs'
      expect(response.body).to include(fake_secret)
    end
  end
end
