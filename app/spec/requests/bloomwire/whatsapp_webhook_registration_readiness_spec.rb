require 'rails_helper'

# Phase 12F — Global webhook registration readiness (SuperAdmin readiness console).
#
# Before pointing the Meta callback at the Bloomwire global router, Ops must see — in one explicit place — the
# exact callback URL/path and the GET-verification prerequisites (global router enabled, privacy hardening
# enabled, global verify token configured, app secret configured, public HTTPS host configured). This reuses
# Bloomwire::WhatsappRealHopReadiness; it NEVER calls Meta and NEVER renders a secret value. Fake values only.
RSpec.describe 'SuperAdmin global webhook registration readiness', type: :request do
  let(:super_admin) { create(:super_admin) }
  let(:account) { create(:account) }

  before do
    GlobalConfig.clear_cache
    sign_in(super_admin, scope: :super_admin)
  end

  def setup_record
    create(:bloomwire_whatsapp_setup, :ready_for_webhook, account: account,
                                                          aligned_phone_number_id: 'PNID-REG-1',
                                                          aligned_display_phone_number: '15551230066')
  end

  def get_readiness(setup)
    get "/super_admin/bloomwire_whatsapp_setups/#{setup.id}/readiness"
  end

  context 'when every GET-verification prerequisite is configured' do
    before { bw_enable_all }

    it 'shows the registration panel as ready with the exact callback path and URL' do
      get_readiness(setup_record)
      expect(response).to have_http_status(:success)
      expect(response.body).to include('data-registration-readiness="ready"')
      expect(response.body).to include('/bloomwire/webhooks/whatsapp')
      expect(response.body).to include('https://smoke.example.com/bloomwire/webhooks/whatsapp')
    end

    it 'lists each GET-verify prerequisite as a passing check' do
      get_readiness(setup_record)
      %w[global_webhook_router_enabled privacy_hardening_enabled global_verify_token_configured
         app_secret_configured public_callback_host_configured].each do |key|
        expect(response.body).to match(/data-prereq="#{key}"[^>]*data-prereq-status="pass"/)
      end
    end
  end

  context 'when a prerequisite is missing' do
    before { bw_enable_all }

    it 'shows blocked + the missing public callback host prerequisite, and no full callback URL' do
      bw_set_config('BLOOMWIRE_WHATSAPP_PUBLIC_CALLBACK_HOST', nil)
      get_readiness(setup_record)
      expect(response.body).to include('data-registration-readiness="blocked"')
      expect(response.body).to match(/data-prereq="public_callback_host_configured"[^>]*data-prereq-status="blocked"/)
      expect(response.body).not_to include('https://smoke.example.com/bloomwire/webhooks/whatsapp')
    end

    it 'shows blocked when the global verify token is missing' do
      bw_set_config('BLOOMWIRE_WHATSAPP_GLOBAL_VERIFY_TOKEN', nil)
      get_readiness(setup_record)
      expect(response.body).to include('data-registration-readiness="blocked"')
      expect(response.body).to match(/data-prereq="global_verify_token_configured"[^>]*data-prereq-status="blocked"/)
    end
  end

  context 'without leaking secrets' do
    before { bw_enable_all }

    it 'never renders the verify token or app secret values in the registration readiness' do
      bw_set_config('WHATSAPP_APP_SECRET', 'FAKE-REG-APP-SECRET')
      bw_set_config('BLOOMWIRE_WHATSAPP_GLOBAL_VERIFY_TOKEN', 'FAKE-REG-VERIFY-TOKEN')
      get_readiness(setup_record)
      expect(response.body).not_to include('FAKE-REG-APP-SECRET')
      expect(response.body).not_to include('FAKE-REG-VERIFY-TOKEN')
    end

    it 'makes no Meta/Graph call while rendering registration readiness' do
      get_readiness(setup_record)
      expect(a_request(:any, /graph\.facebook\.com/)).not_to have_been_made
    end
  end
end
