require 'rails_helper'

# Advisory duplicate-number preflight endpoint. Admin-only + managed-mode-only (404 when off) + account-scoped.
# Returns ONLY { status: available | already_connected } — never another tenant's account/inbox/channel details.
RSpec.describe 'Bloomwire WhatsApp phone-availability preflight endpoint', type: :request do
  let(:account) { create(:account) }
  let(:other_account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:url) { "/api/v1/accounts/#{account.id}/bloomwire/whatsapp/phone_availability" }

  before { GlobalConfig.clear_cache }

  def enable_managed_mode
    bw_set_config('BLOOMWIRE_MODE_ENABLED', true)
    bw_set_config('BLOOMWIRE_PRIVACY_HARDENING', true)
    bw_set_config('BLOOMWIRE_RESTRICT_NATIVE_WHATSAPP_SETUP', true)
    bw_set_config('BLOOMWIRE_MANAGED_WHATSAPP_ONBOARDING', true)
  end

  def connect_number(phone_number, on:)
    create(:channel_whatsapp, account: on, phone_number: phone_number,
                              sync_templates: false, validate_provider_config: false)
  end

  context 'when managed self-serve is not active' do
    it 'is 404 when Bloomwire mode is OFF (stock)' do
      post url, headers: admin.create_new_auth_token, params: { phone_number: '+15551230001' }, as: :json
      expect(response).to have_http_status(:not_found)
    end
  end

  context 'when managed mode is active' do
    before { enable_managed_mode }

    it 'returns available for an unused number (admin)' do
      post url, headers: admin.create_new_auth_token, params: { phone_number: '+15551239999' }, as: :json
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to eq('status' => 'available')
    end

    it 'returns already_connected when the number is connected (even on another tenant) WITHOUT leaking its details' do
      connect_number('+15551230001', on: other_account)
      post url, headers: admin.create_new_auth_token, params: { phone_number: '+1 555 123 0001' }, as: :json

      expect(response).to have_http_status(:ok)
      # (Case 4) Response is EXACTLY { status: already_connected } — nothing else.
      expect(response.parsed_body.keys).to eq(['status'])
      expect(response.parsed_body['status']).to eq('already_connected')
      body = response.body
      aggregate_failures do
        expect(body).not_to include(other_account.id.to_s)
        expect(body).not_to include(other_account.name)
        expect(body).not_to include('inbox')
        expect(body).not_to include('channel')
        expect(body).not_to include('phone_number_id')
        expect(body).not_to include('waba')
      end
    end

    it 'denies an agent' do
      post url, headers: agent.create_new_auth_token, params: { phone_number: '+15551230001' }, as: :json
      expect(response).to have_http_status(:unauthorized).or have_http_status(:forbidden)
    end

    it 'rejects an unauthenticated request' do
      post url, params: { phone_number: '+15551230001' }, as: :json
      expect(response).to have_http_status(:unauthorized)
    end

    it 'is READ-ONLY — creates no records' do
      connect_number('+15551230001', on: other_account)
      expect do
        post url, headers: admin.create_new_auth_token, params: { phone_number: '+15551230001' }, as: :json
      end.not_to(change { [Channel::Whatsapp.count, Inbox.count] })
    end

    # Enumeration protection: the global availability oracle is rate-limited per (account, actor) -> 429 on excess.
    it 'rate-limits abusive volumes with 429 and does not run the lookup' do
      allow(Rails.cache).to receive(:increment).and_return(
        Api::V1::Accounts::Bloomwire::Whatsapp::PhoneAvailabilitiesController::RATE_LIMIT + 1
      )
      expect(Bloomwire::WhatsappPhoneAvailability).not_to receive(:status_for)
      post url, headers: admin.create_new_auth_token, params: { phone_number: '+15551230001' }, as: :json
      expect(response).to have_http_status(:too_many_requests)
    end

    it 'allows requests under the rate limit' do
      allow(Rails.cache).to receive(:increment).and_return(1)
      post url, headers: admin.create_new_auth_token, params: { phone_number: '+15551239999' }, as: :json
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to eq('status' => 'available')
    end
  end
end
