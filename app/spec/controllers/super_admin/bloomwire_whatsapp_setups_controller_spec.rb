require 'rails_helper'

# Phase 17A: the SuperAdmin WhatsApp Setup surface is now READ-ONLY (index/show + readiness/credentials). The
# manual setup-mapping CRUD (new/create/edit/update) was removed — customer WhatsApp onboarding happens natively
# (Settings -> Inboxes -> Add Inbox). Secrets stay in Channel::Whatsapp#provider_config (never duplicated on the
# mapping). Gated by Bloomwire master mode; OFF => stock (surface unavailable). Fake values only.
# (Route absence for new/create/edit/update is asserted in bloomwire_phase_17a_removed_routes_spec.rb.)
RSpec.describe 'SuperAdmin Bloomwire WhatsApp Setup (read-only surface)', type: :request do
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

      it 'lists setups on index (read-only)' do
        create(:bloomwire_whatsapp_setup, account: account, setup_status: 'pending')
        get '/super_admin/bloomwire_whatsapp_setups'
        expect(response).to have_http_status(:success)
      end

      it 'shows a setup (read-only)' do
        setup = create(:bloomwire_whatsapp_setup, account: account)
        get "/super_admin/bloomwire_whatsapp_setups/#{setup.id}"
        expect(response).to have_http_status(:success)
      end

      # Phase 17B: the index is now the read-only "Global WhatsApp Config" page.
      it 'renders the Global WhatsApp Config page (read-only platform config)' do
        get '/super_admin/bloomwire_whatsapp_setups'
        expect(response).to have_http_status(:success)
        expect(response.body).to include('Global WhatsApp Config')
        expect(response.body).to include('Platform configuration')
        expect(response.body).to include('Meta App Secret')
        expect(response.body).to include('Webhook verify token')
        expect(response.body).to include('Connected WhatsApp inboxes')
        expect(response.body).to include('Not tracked yet')
      end

      it 'does not reintroduce provisioning or manual setup-mapping CRUD' do
        get '/super_admin/bloomwire_whatsapp_setups'
        expect(response.body).not_to include('Provision')
        expect(response.body).not_to include('New setup mapping')
        expect(response.body).not_to include('Edit mapping')
      end

      it 'shows global secrets as presence only and never renders their values' do
        allow(GlobalConfigService).to receive(:load).and_call_original
        allow(GlobalConfigService).to receive(:load)
          .with('WHATSAPP_APP_SECRET', nil).and_return('FAKE-GLOBAL-APP-SECRET')
        allow(GlobalConfigService).to receive(:load)
          .with('BLOOMWIRE_WHATSAPP_GLOBAL_VERIFY_TOKEN', nil).and_return('FAKE-GLOBAL-VERIFY-TOKEN')
        get '/super_admin/bloomwire_whatsapp_setups'
        expect(response.body).not_to include('FAKE-GLOBAL-APP-SECRET')
        expect(response.body).not_to include('FAKE-GLOBAL-VERIFY-TOKEN')
        expect(response.body).to include('Present')
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
