require 'rails_helper'

# Bloomwire WhatsApp Setup Mapping foundation: a SuperAdmin/Ops-only readiness surface that references
# existing account/inbox/Channel::Whatsapp records and tracks a setup status + non-secret routing ids.
# Secrets stay in Channel::Whatsapp#provider_config (never duplicated). Gated by Bloomwire master mode;
# OFF => stock (surface unavailable). Fake values only.
RSpec.describe 'SuperAdmin Bloomwire WhatsApp Setup Mapping', type: :request do
  let(:super_admin) { create(:super_admin) }
  let(:account) { create(:account) }

  def set_toggle(key, value)
    config = InstallationConfig.where(name: key).first_or_initialize
    config.value = value
    config.locked = false
    config.save!
    GlobalConfig.clear_cache
  end

  before { GlobalConfig.clear_cache }

  context 'when not authenticated as a super admin (business owner/staff have no access)' do
    before { set_toggle('BLOOMWIRE_MODE_ENABLED', true) }

    it 'redirects index to the super admin login' do
      get '/super_admin/bloomwire_whatsapp_setups'
      expect(response).to have_http_status(:redirect)
      expect(response.redirect_url).to include('/super_admin/sign_in')
    end

    it 'does not create a mapping' do
      expect do
        post '/super_admin/bloomwire_whatsapp_setups',
             params: { bloomwire_whatsapp_setup: { account_id: account.id, setup_status: 'pending' } }
      end.not_to change(Bloomwire::WhatsappSetup, :count)
      expect(response).to have_http_status(:redirect)
    end
  end

  context 'when authenticated as a super admin' do
    before { sign_in(super_admin, scope: :super_admin) }

    context 'when Bloomwire master mode is OFF (stock - surface not available)' do
      it 'does not expose the setup surface' do
        get '/super_admin/bloomwire_whatsapp_setups'
        expect(response).to have_http_status(:redirect)
        expect(response.redirect_url).not_to include('bloomwire_whatsapp_setups')
      end
    end

    context 'when Bloomwire master mode is ON' do
      before { set_toggle('BLOOMWIRE_MODE_ENABLED', true) }

      it 'lists setups on index' do
        create(:bloomwire_whatsapp_setup, account: account, setup_status: 'pending')
        get '/super_admin/bloomwire_whatsapp_setups'
        expect(response).to have_http_status(:success)
      end

      it 'renders the new form' do
        get '/super_admin/bloomwire_whatsapp_setups/new'
        expect(response).to have_http_status(:success)
      end

      it 'creates a setup with non-secret identifiers' do
        expect do
          post '/super_admin/bloomwire_whatsapp_setups', params: {
            bloomwire_whatsapp_setup: {
              account_id: account.id, setup_status: 'configured',
              waba_id: 'FAKE-WABA-1', phone_number_id: 'FAKE-PNID-1',
              display_phone_number: '+10000000001', status_reason: 'creds entered by ops'
            }
          }
        end.to change(Bloomwire::WhatsappSetup, :count).by(1)
        setup = Bloomwire::WhatsappSetup.last
        expect(setup.account_id).to eq(account.id)
        expect(setup.setup_status).to eq('configured')
        expect(setup.phone_number_id).to eq('FAKE-PNID-1')
      end

      it 'updates a setup status' do
        setup = create(:bloomwire_whatsapp_setup, account: account, setup_status: 'pending')
        patch "/super_admin/bloomwire_whatsapp_setups/#{setup.id}", params: {
          bloomwire_whatsapp_setup: { setup_status: 'configured', status_reason: 'creds entered' }
        }
        expect(setup.reload.setup_status).to eq('configured')
      end

      it 'rejects marking ready_for_webhook without the required routing fields' do
        setup = create(:bloomwire_whatsapp_setup, account: account, setup_status: 'pending')
        patch "/super_admin/bloomwire_whatsapp_setups/#{setup.id}", params: {
          bloomwire_whatsapp_setup: { setup_status: 'ready_for_webhook' }
        }
        expect(response).to have_http_status(:unprocessable_entity)
        expect(setup.reload.setup_status).to eq('pending')
      end

      it 'shows a setup' do
        setup = create(:bloomwire_whatsapp_setup, account: account)
        get "/super_admin/bloomwire_whatsapp_setups/#{setup.id}"
        expect(response).to have_http_status(:success)
      end

      it 'rejects an invalid setup status' do
        expect do
          post '/super_admin/bloomwire_whatsapp_setups', params: {
            bloomwire_whatsapp_setup: { account_id: account.id, setup_status: 'not_a_status' }
          }
        end.not_to change(Bloomwire::WhatsappSetup, :count)
      end
    end
  end

  describe 'privacy / no-secret + data integrity' do
    let(:whatsapp_channel) do
      channel = create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud',
                                          sync_templates: false, validate_provider_config: false)
      channel.update!(provider_config: channel.provider_config.merge('api_key' => 'FAKE-SETUP-SECRET-API',
                                                                     'source' => 'embedded_signup'))
      channel
    end

    before do
      sign_in(super_admin, scope: :super_admin)
      set_toggle('BLOOMWIRE_MODE_ENABLED', true)
      set_toggle('BLOOMWIRE_PRIVACY_HARDENING', true)
    end

    it 'stores no secret columns on the mapping (no duplicate secret store)' do
      secretish = Bloomwire::WhatsappSetup.column_names.grep(/api_key|token|secret|password/i)
      expect(secretish).to be_empty
    end

    it 'does not expose channel secrets in the setup surface with privacy hardening ON' do
      setup = create(:bloomwire_whatsapp_setup, account: account, inbox: whatsapp_channel.inbox,
                                                channel_whatsapp: whatsapp_channel, phone_number_id: 'FAKE-PNID-9',
                                                setup_status: 'configured')
      get "/super_admin/bloomwire_whatsapp_setups/#{setup.id}"
      expect(response.body).not_to include('FAKE-SETUP-SECRET-API')
      get '/super_admin/bloomwire_whatsapp_setups'
      expect(response.body).not_to include('FAKE-SETUP-SECRET-API')
    end

    it 'references valid existing records' do
      setup = create(:bloomwire_whatsapp_setup, account: account, inbox: whatsapp_channel.inbox,
                                                channel_whatsapp: whatsapp_channel)
      expect(setup.account).to eq(account)
      expect(setup.channel_whatsapp).to eq(whatsapp_channel)
      expect(setup.inbox).to eq(whatsapp_channel.inbox)
    end
  end
end
