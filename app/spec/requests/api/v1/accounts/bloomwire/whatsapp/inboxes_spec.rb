require 'rails_helper'

# Admin "Remove WhatsApp Inbox" deprovision endpoint. Admin-only + managed-mode-only (404 when off) + account-scoped.
# The request path is short: it blocks routing + enqueues the async deletion and returns 202 (removal_started).
RSpec.describe 'Bloomwire admin Remove WhatsApp Inbox endpoint', type: :request do
  include ActiveJob::TestHelper

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
    it 'is 404 (feature-off stock behavior) and enqueues nothing' do
      inbox, = managed_inbox(on: account)
      expect do
        delete url_for(inbox), headers: admin.create_new_auth_token, as: :json
      end.not_to have_enqueued_job(Bloomwire::WhatsappInboxDeprovisionJob)
      expect(response).to have_http_status(:not_found)
      expect(Inbox.exists?(inbox.id)).to be(true)
    end
  end

  context 'when managed mode is active' do
    before { enable_managed_mode }

    it 'accepts the removal (202), blocks routing, and enqueues the async deletion job' do
      inbox, _channel, setup = managed_inbox(on: account)

      expect do
        delete url_for(inbox), headers: admin.create_new_auth_token, as: :json
      end.to have_enqueued_job(Bloomwire::WhatsappInboxDeprovisionJob)

      expect(response).to have_http_status(:accepted)
      expect(response.parsed_body).to eq('status' => 'removal_started')
      expect(setup.reload.setup_status).to eq('blocked') # routing stopped immediately
      expect(Inbox.exists?(inbox.id)).to be(true) # heavy delete is async
    end

    it 'removes the inbox + channel + setup once the enqueued job runs' do
      inbox, channel, setup = managed_inbox(on: account)
      perform_enqueued_jobs(only: Bloomwire::WhatsappInboxDeprovisionJob) do
        delete url_for(inbox), headers: admin.create_new_auth_token, as: :json
      end
      aggregate_failures do
        expect(Inbox.exists?(inbox.id)).to be(false)
        expect(Channel::Whatsapp.exists?(channel.id)).to be(false)
        expect(Bloomwire::WhatsappSetup.exists?(setup.id)).to be(false)
      end
    end

    it 'forbids an agent (403) and enqueues nothing' do
      inbox, = managed_inbox(on: account)
      expect do
        delete url_for(inbox), headers: agent.create_new_auth_token, as: :json
      end.not_to have_enqueued_job(Bloomwire::WhatsappInboxDeprovisionJob)
      expect(response).to have_http_status(:unauthorized).or have_http_status(:forbidden)
      expect(Inbox.exists?(inbox.id)).to be(true)
    end

    it 'cannot delete another tenant’s inbox (account-scoped -> 404, untouched)' do
      other_inbox, = managed_inbox(on: other_account)
      delete "/api/v1/accounts/#{account.id}/bloomwire/whatsapp/inboxes/#{other_inbox.id}",
             headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:not_found)
      expect(Inbox.exists?(other_inbox.id)).to be(true)
    end

    it 'is idempotent: after the job has removed it, a repeat delete returns 404' do
      inbox, = managed_inbox(on: account)
      perform_enqueued_jobs(only: Bloomwire::WhatsappInboxDeprovisionJob) do
        delete url_for(inbox), headers: admin.create_new_auth_token, as: :json
      end
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
