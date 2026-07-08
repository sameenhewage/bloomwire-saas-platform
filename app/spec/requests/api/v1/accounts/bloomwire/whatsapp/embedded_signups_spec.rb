require 'rails_helper'

# Phase 17C.2: dedicated customer WhatsApp Embedded Signup endpoint. Admin-only + managed-mode-only; safe DTO;
# all Meta calls stubbed. Never touches native /whatsapp/authorization. Fake values only.
RSpec.describe 'Bloomwire customer WhatsApp Embedded Signup endpoint', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:url) { "/api/v1/accounts/#{account.id}/bloomwire/whatsapp/embedded_signup" }
  let(:body) { { code: 'META-CODE', business_id: 'BIZ-1', waba_id: 'WABA-1', phone_number_id: 'PNID-1' } }
  let(:phone_info) do
    { phone_number_id: 'PNID-1', phone_number: '+15551230001', verified: true, business_name: 'Acme' }
  end

  before { GlobalConfig.clear_cache }

  def enable_managed_mode
    bw_set_config('BLOOMWIRE_MODE_ENABLED', true)
    bw_set_config('BLOOMWIRE_PRIVACY_HARDENING', true)
    bw_set_config('BLOOMWIRE_RESTRICT_NATIVE_WHATSAPP_SETUP', true)
    bw_set_config('BLOOMWIRE_MANAGED_WHATSAPP_ONBOARDING', true)
  end

  def stub_ready(ready: true)
    allow(Bloomwire::GlobalWhatsappConfig).to receive(:new)
      .and_return(instance_double(Bloomwire::GlobalWhatsappConfig, result: { platform_ready: ready }))
  end

  def stub_meta
    allow(Whatsapp::TokenExchangeService).to receive(:new)
      .and_return(instance_double(Whatsapp::TokenExchangeService, perform: 'FAKE-CUSTOMER-TOKEN'))
    allow(Whatsapp::PhoneInfoService).to receive(:new)
      .and_return(instance_double(Whatsapp::PhoneInfoService, perform: phone_info))
    allow(Whatsapp::FacebookApiClient).to receive(:new)
      .and_return(instance_double(Whatsapp::FacebookApiClient, subscribe_app_to_waba: true, subscribed_to_waba?: true,
                                                               override_waba_callback: nil, subscribe_waba_webhook: nil,
                                                               register_phone_number: { 'success' => true }, phone_number_status: 'CONNECTED',
                                                               exchange_for_long_lived_token: 'FAKE-CUSTOMER-TOKEN', messaging_waba_ids: [],
                                                               token_actor_id: 'SYS-ACTOR-1', token_actor_type: 'SYSTEM_USER',
                                                               waba_user_tasks: %w[MANAGE]))
  end

  context 'when managed mode is active, admin, and platform ready (Meta stubbed)' do
    before do
      enable_managed_mode
      stub_ready
      stub_meta
    end

    it 'allows an account administrator and returns a safe DTO with no secrets' do
      post url, headers: admin.create_new_auth_token, params: body, as: :json
      aggregate_failures do
        expect(response).to have_http_status(:created)
        expect(response.body).not_to include('FAKE-CUSTOMER-TOKEN')
        expect(response.body).not_to include('api_key')
        expect(response.body).not_to include('provider_config')
        expect(response.parsed_body.dig('channel', 'source')).to eq('bloomwire_managed')
        expect(response.parsed_body.dig('setup', 'status')).to eq('ready_for_webhook')
      end
    end

    it 'denies an agent' do
      post url, headers: agent.create_new_auth_token, params: body, as: :json
      expect(response).to have_http_status(:unauthorized).or have_http_status(:forbidden)
    end
  end

  context 'when managed self-serve is not active (surface inert / 404)' do
    it 'is 404 when Bloomwire mode is OFF (stock)' do
      post url, headers: admin.create_new_auth_token, params: body, as: :json
      expect(response).to have_http_status(:not_found)
    end

    it 'is 404 when the managed_whatsapp_onboarding feature is OFF' do
      bw_set_config('BLOOMWIRE_MODE_ENABLED', true)
      bw_set_config('BLOOMWIRE_RESTRICT_NATIVE_WHATSAPP_SETUP', true)
      post url, headers: admin.create_new_auth_token, params: body, as: :json
      expect(response).to have_http_status(:not_found)
    end

    it 'is 404 when native WhatsApp setup is not restricted' do
      bw_set_config('BLOOMWIRE_MODE_ENABLED', true)
      bw_set_config('BLOOMWIRE_PRIVACY_HARDENING', true)
      bw_set_config('BLOOMWIRE_MANAGED_WHATSAPP_ONBOARDING', true)
      post url, headers: admin.create_new_auth_token, params: body, as: :json
      expect(response).to have_http_status(:not_found)
    end
  end

  context 'when platform config or encryption blocks setup (422, no token stored)' do
    before { enable_managed_mode }

    it 'is 422 not_ready when the platform config is incomplete' do
      stub_ready(ready: false)
      post url, headers: admin.create_new_auth_token, params: body, as: :json
      aggregate_failures do
        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.parsed_body['code']).to eq('not_ready')
        expect(Channel::Whatsapp.count).to eq(0)
      end
    end

    it 'is 422 encryption_not_configured outside dev/test (before token storage)' do
      stub_ready
      stub_meta
      allow(Chatwoot).to receive(:encryption_configured?).and_return(false)
      allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new('production'))
      post url, headers: admin.create_new_auth_token, params: body, as: :json
      aggregate_failures do
        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.parsed_body['code']).to eq('encryption_not_configured')
        expect(Channel::Whatsapp.count).to eq(0)
      end
    end
  end

  context 'when the requester belongs to a different account' do
    it 'denies an administrator of a different account' do
      enable_managed_mode
      other_admin = create(:user, account: create(:account), role: :administrator)
      post url, headers: other_admin.create_new_auth_token, params: body, as: :json
      expect(response.status).to be_in([401, 403, 404])
    end
  end

  # Phase 17E.1 — one account can register multiple WhatsApp numbers (ADR-0009). Duplicate phone_number /
  # phone_number_id stays blocked (422). All Meta calls stubbed per-number (no real Meta).
  context 'when an admin registers multiple WhatsApp numbers for one account (Phase 17E.1 contract)' do
    before do
      enable_managed_mode
      stub_ready
    end

    def stub_meta_for(phone_number_id:, phone_number:)
      allow(Whatsapp::TokenExchangeService).to receive(:new)
        .and_return(instance_double(Whatsapp::TokenExchangeService, perform: 'FAKE-CUSTOMER-TOKEN'))
      allow(Whatsapp::PhoneInfoService).to receive(:new)
        .and_return(instance_double(Whatsapp::PhoneInfoService,
                                    perform: { phone_number_id: phone_number_id, phone_number: phone_number,
                                               verified: true, business_name: 'Acme' }))
      allow(Whatsapp::FacebookApiClient).to receive(:new)
        .and_return(instance_double(Whatsapp::FacebookApiClient, subscribe_app_to_waba: true, subscribed_to_waba?: true,
                                                                 override_waba_callback: nil, subscribe_waba_webhook: nil,
                                                                 register_phone_number: { 'success' => true }, phone_number_status: 'CONNECTED',
                                                                 exchange_for_long_lived_token: 'FAKE-CUSTOMER-TOKEN', messaging_waba_ids: [],
                                                                 token_actor_id: 'SYS-ACTOR-1', token_actor_type: 'SYSTEM_USER',
                                                                 waba_user_tasks: %w[MANAGE]))
    end

    def register(phone_number_id:, phone_number:)
      stub_meta_for(phone_number_id: phone_number_id, phone_number: phone_number)
      post url, headers: admin.create_new_auth_token, params: body.merge(phone_number_id: phone_number_id), as: :json
    end

    it 'lets an admin register two different numbers as two inboxes for the same account' do
      register(phone_number_id: 'PNID-1', phone_number: '+15551230001')
      expect(response).to have_http_status(:created)
      register(phone_number_id: 'PNID-2', phone_number: '+15551230002')
      expect(response).to have_http_status(:created)

      aggregate_failures do
        expect(account.inboxes.count).to eq(2)
        expect(Bloomwire::WhatsappSetup.where(account: account).pluck(:phone_number_id)).to contain_exactly('PNID-1', 'PNID-2')
      end
    end

    it 'rejects a duplicate phone_number with 422 and creates no second inbox' do
      register(phone_number_id: 'PNID-1', phone_number: '+15551230001')
      register(phone_number_id: 'PNID-2', phone_number: '+15551230001')
      aggregate_failures do
        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.parsed_body['code']).to eq('phone_number_taken')
        expect(account.inboxes.count).to eq(1)
      end
    end

    it 'rejects a duplicate phone_number_id with 422' do
      register(phone_number_id: 'PNID-1', phone_number: '+15551230001')
      register(phone_number_id: 'PNID-1', phone_number: '+15551230002')
      aggregate_failures do
        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.parsed_body['code']).to eq('phone_number_id_conflict')
      end
    end
  end
end
