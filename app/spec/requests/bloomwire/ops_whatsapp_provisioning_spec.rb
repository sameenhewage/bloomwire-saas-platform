require 'rails_helper'

# Phase 12C — Ops-only WhatsApp channel/setup-mapping provisioning (backend authorization boundary).
#
# Locks the *already-implemented* boundary (no product code in 12C):
#   - Bloomwire Ops (SuperAdmin) can provision/link the non-secret Bloomwire::WhatsappSetup mapping and flip it
#     to ready_for_webhook (slice 2).
#   - Authenticated business admins/agents (the :user Devise scope) are DENIED every Ops setup/request surface,
#     and there is NO account-side route that mutates a mapping (slice 3).
#   - Secret-ish params submitted to the Ops setup surface are dropped (strong params); the registry stays
#     non-secret control-plane (slice 4). Secrets live only in Channel::Whatsapp#provider_config.
#   - With Bloomwire OFF the whole provisioning control-plane is stock/inert (slice 6).
#
# Backend authorization is the security boundary here (these are request specs hitting controllers, not UI).
# All values are fake; no Meta/WhatsApp call is made.
RSpec.describe 'Bloomwire Ops-only WhatsApp provisioning', type: :request do
  let(:super_admin) { create(:super_admin) }
  let(:account) { create(:account) }
  let(:business_admin) { create(:user, account: account, role: :administrator) }
  let(:business_agent) { create(:user, account: account, role: :agent) }

  before { GlobalConfig.clear_cache }

  # --- Slice 2: Ops can provision/link the mapping ----------------------------------------------------
  context 'when signed in as Bloomwire Ops (SuperAdmin) with managed mode ON' do
    before do
      bw_set_config('BLOOMWIRE_MODE_ENABLED', true)
      sign_in(super_admin, scope: :super_admin)
    end

    it 'provisions a fully-linked ready_for_webhook mapping in one create' do
      channel = bw_aligned_whatsapp_channel(account: account, phone_number_id: 'PNID-OPS-1',
                                            display_phone_number: '15551230091')
      expect do
        post '/super_admin/bloomwire_whatsapp_setups', params: { bloomwire_whatsapp_setup: {
          account_id: account.id, inbox_id: channel.inbox.id, channel_whatsapp_id: channel.id,
          phone_number_id: 'PNID-OPS-1', display_phone_number: '15551230091', setup_status: 'ready_for_webhook'
        } }
      end.to change(Bloomwire::WhatsappSetup, :count).by(1)

      setup = Bloomwire::WhatsappSetup.last
      expect(setup.setup_status).to eq('ready_for_webhook')
      expect(setup.channel_whatsapp_id).to eq(channel.id)
      expect(setup.inbox_id).to eq(channel.inbox.id)
      expect(setup.phone_number_id).to eq('PNID-OPS-1')
    end

    it 'links an existing channel and flips a pending mapping to ready_for_webhook' do
      channel = bw_aligned_whatsapp_channel(account: account, phone_number_id: 'PNID-OPS-2',
                                            display_phone_number: '15551230092')
      setup = create(:bloomwire_whatsapp_setup, account: account, setup_status: 'pending')

      patch "/super_admin/bloomwire_whatsapp_setups/#{setup.id}", params: { bloomwire_whatsapp_setup: {
        inbox_id: channel.inbox.id, channel_whatsapp_id: channel.id,
        phone_number_id: 'PNID-OPS-2', display_phone_number: '15551230092', setup_status: 'ready_for_webhook'
      } }

      expect(setup.reload.setup_status).to eq('ready_for_webhook')
      expect(setup.channel_whatsapp_id).to eq(channel.id)
    end

    # --- Slice 4: secret-ish params are dropped; registry stays non-secret ----------------------------
    it 'drops injected secret params on create (mapping stays non-secret control-plane)' do
      post '/super_admin/bloomwire_whatsapp_setups', params: { bloomwire_whatsapp_setup: {
        account_id: account.id, setup_status: 'configured', phone_number_id: 'PNID-SEC-1',
        api_key: 'FAKE-INJECTED-APIKEY', webhook_verify_token: 'FAKE-INJECTED-TOKEN',
        provider_config: { 'api_key' => 'FAKE-NESTED-SECRET' }
      } }

      setup = Bloomwire::WhatsappSetup.last
      expect(setup.phone_number_id).to eq('PNID-SEC-1')
      expect(setup).not_to respond_to(:api_key)
      expect(setup.attributes.values.map(&:to_s).join(' ')).not_to include('FAKE-INJECTED')
      expect(setup.attributes.values.map(&:to_s).join(' ')).not_to include('FAKE-NESTED-SECRET')
    end

    it 'drops injected secret params on update' do
      setup = create(:bloomwire_whatsapp_setup, account: account, setup_status: 'pending')

      patch "/super_admin/bloomwire_whatsapp_setups/#{setup.id}", params: { bloomwire_whatsapp_setup: {
        status_reason: 'ops note', api_key: 'FAKE-INJECTED-APIKEY-2', provider_config: { 'api_key' => 'X' }
      } }

      setup.reload
      expect(setup.status_reason).to eq('ops note')
      expect(setup.attributes.values.map(&:to_s).join(' ')).not_to include('FAKE-INJECTED')
    end
  end

  # --- Slice 3: business admin denial of every Ops surface --------------------------------------------
  context 'when an authenticated business administrator targets the Ops surfaces' do
    before do
      bw_set_config('BLOOMWIRE_MODE_ENABLED', true)
      sign_in(business_admin, scope: :user)
    end

    it 'is denied the SuperAdmin setups index (redirected to super admin sign in)' do
      get '/super_admin/bloomwire_whatsapp_setups'
      expect(response).to have_http_status(:redirect)
      expect(response.redirect_url).to include('/super_admin/sign_in')
    end

    it 'cannot create a setup mapping via the SuperAdmin surface' do
      expect do
        post '/super_admin/bloomwire_whatsapp_setups',
             params: { bloomwire_whatsapp_setup: { account_id: account.id, setup_status: 'pending' } }
      end.not_to change(Bloomwire::WhatsappSetup, :count)
      expect(response).to have_http_status(:redirect)
      expect(response.redirect_url).to include('/super_admin/sign_in')
    end

    it 'cannot update/link a setup mapping via the SuperAdmin surface' do
      setup = create(:bloomwire_whatsapp_setup, account: account, setup_status: 'pending')
      patch "/super_admin/bloomwire_whatsapp_setups/#{setup.id}",
            params: { bloomwire_whatsapp_setup: { setup_status: 'configured' } }
      expect(setup.reload.setup_status).to eq('pending')
      expect(response).to have_http_status(:redirect)
    end

    it 'is denied the SuperAdmin setup_requests queue' do
      get '/super_admin/bloomwire_whatsapp_setup_requests'
      expect(response).to have_http_status(:redirect)
      expect(response.redirect_url).to include('/super_admin/sign_in')
    end

    it 'cannot update a setup request via the SuperAdmin surface' do
      req = Bloomwire::WhatsappSetupRequest.request_for(account: account)
      patch "/super_admin/bloomwire_whatsapp_setup_requests/#{req.id}",
            params: { bloomwire_whatsapp_setup_request: { status: 'completed' } }
      expect(req.reload.status).not_to eq('completed')
      expect(response).to have_http_status(:redirect)
    end
  end

  context 'when an authenticated business agent targets the Ops surfaces' do
    before do
      bw_set_config('BLOOMWIRE_MODE_ENABLED', true)
      sign_in(business_agent, scope: :user)
    end

    it 'is denied the SuperAdmin setups index' do
      get '/super_admin/bloomwire_whatsapp_setups'
      expect(response).to have_http_status(:redirect)
      expect(response.redirect_url).to include('/super_admin/sign_in')
    end

    it 'cannot create a setup mapping via the SuperAdmin surface' do
      expect do
        post '/super_admin/bloomwire_whatsapp_setups',
             params: { bloomwire_whatsapp_setup: { account_id: account.id, setup_status: 'pending' } }
      end.not_to change(Bloomwire::WhatsappSetup, :count)
      expect(response).to have_http_status(:redirect)
    end
  end

  # --- Slice 3 (F): no account-side mapping mutation endpoint -----------------------------------------
  context 'without any account-side mapping mutation endpoint' do
    it 'exposes no account route to create or modify a Bloomwire::WhatsappSetup mapping' do
      %i[post patch put delete].each do |verb|
        expect do
          Rails.application.routes.recognize_path("/api/v1/accounts/#{account.id}/bloomwire/whatsapp_setups",
                                                  method: verb)
        end.to raise_error(ActionController::RoutingError)
      end
    end

    it 'exposes only the non-secret setup REQUEST intake on the account side' do
      recognized = Rails.application.routes.recognize_path(
        "/api/v1/accounts/#{account.id}/bloomwire/whatsapp_setup_requests", method: :post
      )
      expect(recognized).to include(controller: 'api/v1/accounts/bloomwire/whatsapp_setup_requests', action: 'create')
    end
  end

  # --- Slice 6: Bloomwire OFF == stock (provisioning control-plane inert) -----------------------------
  context 'when Bloomwire master mode is OFF (stock - provisioning control-plane inert)' do
    before { bw_set_config('BLOOMWIRE_MODE_ENABLED', false) }

    it 'does not let even a SuperAdmin create a mapping (surface unavailable)' do
      sign_in(super_admin, scope: :super_admin)
      expect do
        post '/super_admin/bloomwire_whatsapp_setups',
             params: { bloomwire_whatsapp_setup: { account_id: account.id, setup_status: 'pending' } }
      end.not_to change(Bloomwire::WhatsappSetup, :count)
      expect(response).to have_http_status(:redirect)
    end

    it 'returns 404 for the account-side request intake and creates nothing' do
      post "/api/v1/accounts/#{account.id}/bloomwire/whatsapp_setup_requests",
           headers: business_admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:not_found)
      expect(Bloomwire::WhatsappSetupRequest.count).to eq(0)
    end
  end
end
