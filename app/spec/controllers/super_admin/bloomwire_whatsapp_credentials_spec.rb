require 'rails_helper'

# Phase 14 S2a/S2d — Ops/SuperAdmin-only WhatsApp credential-capture surface (member actions on the setup
# mapping). Write-only api_key (never echoed, no-wipe on blank), Ops-only (business owner/staff have no
# /super_admin access), OFF == stock (master toggle OFF makes it inert), no live Meta call, and the
# provider_config request param is filtered from logs (S2d). Fake values only.
RSpec.describe 'SuperAdmin Bloomwire WhatsApp Credentials', type: :request do
  let(:super_admin) { create(:super_admin) }
  let(:account) { create(:account) }
  let(:channel) do
    create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud',
                              validate_provider_config: false, sync_templates: false)
  end
  let(:setup) do
    create(:bloomwire_whatsapp_setup, account: account, inbox: channel.inbox, channel_whatsapp: channel,
                                      phone_number_id: 'PNID-7', setup_status: 'configured')
  end

  def set_toggle(key, value)
    config = InstallationConfig.where(name: key).first_or_initialize
    config.value = value
    config.locked = false
    config.save!
    GlobalConfig.clear_cache
  end

  before do
    GlobalConfig.clear_cache
    channel.update!(provider_config: channel.provider_config.merge('api_key' => 'FAKE-OLD-TOKEN', 'phone_number_id' => 'PNID-7'))
  end

  context 'when not authenticated as a super admin (business owner/staff have no access)' do
    before { set_toggle('BLOOMWIRE_MODE_ENABLED', true) }

    it 'redirects the credentials page to the super admin login' do
      get credentials_super_admin_bloomwire_whatsapp_setup_path(setup)
      expect(response).to have_http_status(:redirect)
      expect(response.redirect_url).to include('/super_admin/sign_in')
    end

    it 'does not update credentials' do
      patch update_credentials_super_admin_bloomwire_whatsapp_setup_path(setup),
            params: { provider_config: { api_key: 'HACK-TOKEN' } }
      expect(response).to have_http_status(:redirect)
      expect(channel.reload.provider_config['api_key']).to eq('FAKE-OLD-TOKEN')
    end
  end

  context 'when authenticated as a super admin' do
    before { sign_in(super_admin, scope: :super_admin) }

    context 'when Bloomwire master mode is OFF (stock - surface inert)' do
      it 'does not expose the credentials surface' do
        get credentials_super_admin_bloomwire_whatsapp_setup_path(setup)
        expect(response).to have_http_status(:redirect)
        expect(response.redirect_url).not_to include('/credentials')
      end

      it 'does not update credentials' do
        patch update_credentials_super_admin_bloomwire_whatsapp_setup_path(setup),
              params: { provider_config: { api_key: 'NEW-TOKEN' } }
        expect(channel.reload.provider_config['api_key']).to eq('FAKE-OLD-TOKEN')
      end
    end

    context 'when Bloomwire master mode is ON' do
      before { set_toggle('BLOOMWIRE_MODE_ENABLED', true) }

      it 'renders the credentials page without echoing the stored api_key' do
        get credentials_super_admin_bloomwire_whatsapp_setup_path(setup)
        expect(response).to have_http_status(:success)
        expect(response.body).not_to include('FAKE-OLD-TOKEN')
      end

      it 'sets/rotates the api_key and makes no Meta call' do
        patch update_credentials_super_admin_bloomwire_whatsapp_setup_path(setup),
              params: { provider_config: { api_key: 'FAKE-NEW-TOKEN' } }
        expect(response).to have_http_status(:redirect)
        expect(channel.reload.provider_config['api_key']).to eq('FAKE-NEW-TOKEN')
        expect(a_request(:any, /graph\.facebook\.com/)).not_to have_been_made
      end

      it 'does not wipe the existing api_key on a blank submit (write-only)' do
        patch update_credentials_super_admin_bloomwire_whatsapp_setup_path(setup),
              params: { provider_config: { api_key: '' } }
        expect(channel.reload.provider_config['api_key']).to eq('FAKE-OLD-TOKEN')
      end

      it 'updates a non-secret routing id when provided' do
        patch update_credentials_super_admin_bloomwire_whatsapp_setup_path(setup),
              params: { provider_config: { business_account_id: 'WABA-NEW' } }
        expect(channel.reload.provider_config['business_account_id']).to eq('WABA-NEW')
      end

      it 'preserves setup<->channel phone_number_id alignment when only the token is updated' do
        patch update_credentials_super_admin_bloomwire_whatsapp_setup_path(setup),
              params: { provider_config: { api_key: 'FAKE-NEW-TOKEN' } }
        expect(channel.reload.provider_config['phone_number_id']).to eq(setup.reload.phone_number_id)
      end

      it 'redirects with an error when the setup has no linked channel' do
        bare_setup = create(:bloomwire_whatsapp_setup, account: account, setup_status: 'pending')
        get credentials_super_admin_bloomwire_whatsapp_setup_path(bare_setup)
        expect(response).to have_http_status(:redirect)
        expect(response.redirect_url).to include("/bloomwire_whatsapp_setups/#{bare_setup.id}")
      end
    end
  end

  describe 'S2d — provider_config is filtered from request-param logs' do
    it 'includes :provider_config in filter_parameters and redacts the blob' do
      expect(Rails.application.config.filter_parameters).to include(:provider_config)
      filtered = ActiveSupport::ParameterFilter
                 .new(Rails.application.config.filter_parameters)
                 .filter('provider_config' => { 'api_key' => 'x', 'phone_number_id' => 'y' })
      expect(filtered['provider_config']).to eq('[FILTERED]')
    end
  end

  describe 'provider_config stays scrubbed from business-facing responses' do
    it 'drops api_key via ProviderConfigScrubber when privacy hardening is ON' do
      set_toggle('BLOOMWIRE_MODE_ENABLED', true)
      set_toggle('BLOOMWIRE_PRIVACY_HARDENING', true)
      scrubbed = Bloomwire::ProviderConfigScrubber.for_response(channel.provider_config)
      expect(scrubbed).not_to have_key('api_key')
    end
  end
end
