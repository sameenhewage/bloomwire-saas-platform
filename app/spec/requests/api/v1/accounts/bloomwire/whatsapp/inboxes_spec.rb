require 'rails_helper'

# Admin "Remove WhatsApp Inbox" deprovision endpoint. Admin-only + managed-mode-only (404 when off) + account-scoped.
RSpec.describe 'Bloomwire admin Remove WhatsApp Inbox endpoint', type: :request do
  let(:account) { create(:account) }
  let(:other_account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }

  before { GlobalConfig.clear_cache }

  def enable_managed_mode
    bw_set_config('BLOOMWIRE_MODE_ENABLED', true)
    bw_set_config('BLOOMWIRE_PRIVACY_HARDENING', true)
    bw_set_config('BLOOMWIRE_RESTRICT_NATIVE_WHATSAPP_SETUP', true)
    bw_set_config('BLOOMWIRE_MANAGED_WHATSAPP_ONBOARDING', true)
  end

  def managed_inbox(on:, phone_number: '+15551230001', phone_number_id: 'PNID-1')
    channel = create(:channel_whatsapp, account: on, provider: 'whatsapp_cloud', phone_number: phone_number,
                                        sync_templates: false, validate_provider_config: false)
    channel.provider_config = {
      'source' => 'bloomwire_managed', 'phone_number_id' => phone_number_id,
      'business_account_id' => 'WABA-1', 'api_key' => 'FAKE-KEY'
    }
    channel.save!(validate: false)
    inbox = channel.inbox
    setup = create(:bloomwire_whatsapp_setup, account: on, inbox: inbox, channel_whatsapp: channel,
                                              phone_number_id: phone_number_id, waba_id: 'WABA-1',
                                              display_phone_number: phone_number, setup_status: 'ready_for_webhook')
    [inbox, channel, setup]
  end

  def url_for(inbox) = "/api/v1/accounts/#{account.id}/bloomwire/whatsapp/inboxes/#{inbox.id}"

  context 'when managed self-serve is OFF (stock)' do
    it 'is 404 (feature-off stock behavior)' do
      inbox, = managed_inbox(on: account)
      delete url_for(inbox), headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:not_found)
      expect(Inbox.exists?(inbox.id)).to be(true)
    end
  end

  context 'when managed mode is active' do
    before { enable_managed_mode }

    it 'lets an administrator remove the inbox (+ channel + setup)' do
      inbox, channel, setup = managed_inbox(on: account)
      delete url_for(inbox), headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:ok)
      aggregate_failures do
        expect(Inbox.exists?(inbox.id)).to be(false)
        expect(Channel::Whatsapp.exists?(channel.id)).to be(false)
        expect(Bloomwire::WhatsappSetup.exists?(setup.id)).to be(false)
      end
    end

    it 'forbids an agent (403) and deletes nothing' do
      inbox, = managed_inbox(on: account)
      delete url_for(inbox), headers: agent.create_new_auth_token, as: :json
      expect(response).to have_http_status(:unauthorized).or have_http_status(:forbidden)
      expect(Inbox.exists?(inbox.id)).to be(true)
    end

    it 'cannot delete another tenant’s inbox (account-scoped -> 404, untouched)' do
      other_inbox, = managed_inbox(on: other_account)
      # Same account-scoped route, foreign inbox id.
      delete "/api/v1/accounts/#{account.id}/bloomwire/whatsapp/inboxes/#{other_inbox.id}",
             headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:not_found)
      expect(Inbox.exists?(other_inbox.id)).to be(true)
    end

    it 'is idempotent: a repeat delete returns 404' do
      inbox, = managed_inbox(on: account)
      delete url_for(inbox), headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:ok)
      delete url_for(inbox), headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:not_found)
    end

    it 'never exposes the phone number, phone_number_id, WABA id or credentials in the response' do
      inbox, = managed_inbox(on: account, phone_number: '+15551230001', phone_number_id: 'PNID-SECRET')
      delete url_for(inbox), headers: admin.create_new_auth_token, as: :json
      body = response.body
      aggregate_failures do
        expect(body).not_to include('15551230001')
        expect(body).not_to include('PNID-SECRET')
        expect(body).not_to include('WABA-1')
        expect(body).not_to include('FAKE-KEY')
      end
    end
  end
end
