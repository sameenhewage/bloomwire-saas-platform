require 'rails_helper'

# Slice 4 (ADR-0010 v3): async managed WhatsApp onboarding API. Admin-only; inert (404) unless managed self-serve
# AND the async flag are ON. The request does ZERO Meta work (only creates/updates the attempt + enqueues the job);
# account-scoped; safe DTO only. Fake values only; no real Meta (nothing is stubbed — an accidental Graph call
# would be WebMock-blocked).
RSpec.describe 'Bloomwire async WhatsApp onboarding attempts', type: :request do
  include ActiveJob::TestHelper

  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:base) { "/api/v1/accounts/#{account.id}/bloomwire/whatsapp/onboarding_attempts" }
  let(:submit_body) do
    { code: 'META-CODE', business_id: 'BIZ-1', waba_id: 'WABA-1', phone_number_id: 'PNID-1', display_phone_number: '+15551230001' }
  end

  before { GlobalConfig.clear_cache }

  # No separate positive async flag: Bloomwire managed onboarding ON => async (kill switch defaults false/off).
  def enable_async_managed_mode
    bw_set_config('BLOOMWIRE_MODE_ENABLED', true)
    bw_set_config('BLOOMWIRE_PRIVACY_HARDENING', true)
    bw_set_config('BLOOMWIRE_RESTRICT_NATIVE_WHATSAPP_SETUP', true)
    bw_set_config('BLOOMWIRE_MANAGED_WHATSAPP_ONBOARDING', true)
  end

  context 'when async managed self-serve is active (admin)' do
    before { enable_async_managed_mode }

    it 'create opens an attempt (202) with NO Meta call', if: Chatwoot.encryption_configured? do
      expect do
        post base, headers: admin.create_new_auth_token, as: :json
      end.to change { Bloomwire::WhatsappOnboardingAttempt.where(account: account).count }.by(1)
      aggregate_failures do
        expect(response).to have_http_status(:accepted)
        expect(response.parsed_body['attempt_id']).to be_present
        expect(response.parsed_body['status']).to eq('waiting_meta')
        expect(Channel::Whatsapp.count).to eq(0)
      end
    end

    it 'submit stores the code, queues, bumps generation, enqueues the job (no Meta, no persist)', if: Chatwoot.encryption_configured? do
      attempt = Bloomwire::WhatsappOnboardingAttempt.create!(account: account, status: 'waiting_meta')
      expect do
        post "#{base}/#{attempt.public_uuid}/submit", headers: admin.create_new_auth_token, params: submit_body, as: :json
      end.to have_enqueued_job(Bloomwire::WhatsappOnboardingJob).with(attempt.id, 1)
      aggregate_failures do
        expect(response).to have_http_status(:accepted)
        expect(attempt.reload.status).to eq('queued')
        expect(attempt.oauth_code).to eq('META-CODE')
        expect(attempt.submission_generation).to eq(1)
        expect(attempt.masked_phone).to eq('****0001')
        expect(response.body).not_to include('META-CODE')
        expect(Channel::Whatsapp.count).to eq(0)
      end
    end

    it 'show returns the safe DTO for this account and never a secret' do
      attempt = Bloomwire::WhatsappOnboardingAttempt.create!(account: account, status: 'processing', phone_number_id: 'PNID-1')
      get "#{base}/#{attempt.public_uuid}", headers: admin.create_new_auth_token, as: :json
      aggregate_failures do
        expect(response).to have_http_status(:success)
        expect(response.parsed_body['attempt_id']).to eq(attempt.public_uuid)
        expect(response.parsed_body).not_to have_key('oauth_code')
        expect(response.parsed_body).not_to have_key('access_token')
      end
    end

    it 'show is 404 for a public_uuid owned by another account (no cross-tenant disclosure)' do
      foreign = Bloomwire::WhatsappOnboardingAttempt.create!(account: create(:account), status: 'processing')
      get "#{base}/#{foreign.public_uuid}", headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:not_found)
    end

    it 'denies an agent' do
      post base, headers: agent.create_new_auth_token, as: :json
      expect(response).to have_http_status(:unauthorized).or have_http_status(:forbidden)
    end
  end

  context 'when the emergency kill switch is set (temporary sync fallback / rollback)' do
    before do
      enable_async_managed_mode
      bw_set_config('BLOOMWIRE_WHATSAPP_ASYNC_ONBOARDING_DISABLED', true)
    end

    it 'blocks NEW attempt creation (404) so the frontend uses the synchronous path' do
      post base, headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:not_found)
    end

    it 'blocks submit for a not-yet-queued attempt (404 => sync fallback)' do
      attempt = Bloomwire::WhatsappOnboardingAttempt.create!(account: account, status: 'waiting_meta')
      post "#{base}/#{attempt.public_uuid}/submit", headers: admin.create_new_auth_token, params: submit_body, as: :json
      expect(response).to have_http_status(:not_found)
    end

    it 'STILL lets an in-flight (queued/processing) attempt be polled to completion (continue normally)' do
      attempt = Bloomwire::WhatsappOnboardingAttempt.create!(account: account, status: 'processing', phone_number_id: 'PNID-1')
      get "#{base}/#{attempt.public_uuid}", headers: admin.create_new_auth_token, as: :json
      aggregate_failures do
        expect(response).to have_http_status(:success)
        expect(response.parsed_body['status']).to eq('processing')
      end
    end
  end

  context 'when Bloomwire managed onboarding is not available' do
    before do
      bw_set_config('BLOOMWIRE_MODE_ENABLED', true)
      bw_set_config('BLOOMWIRE_RESTRICT_NATIVE_WHATSAPP_SETUP', true) # managed_whatsapp_onboarding stays OFF
    end

    it 'is 404 for create' do
      post base, headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:not_found)
    end

    it 'is 404 for show as well (the read path also respects the base feature)' do
      attempt = Bloomwire::WhatsappOnboardingAttempt.create!(account: account, status: 'processing')
      get "#{base}/#{attempt.public_uuid}", headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:not_found)
    end
  end

  context 'when AR encryption is not configured (readiness gate)' do
    before { enable_async_managed_mode }

    it 'refuses create with a safe encryption_not_configured code (no plaintext fallback)' do
      allow(Chatwoot).to receive(:encryption_configured?).and_return(false)
      post base, headers: admin.create_new_auth_token, as: :json
      aggregate_failures do
        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.parsed_body['code']).to eq('encryption_not_configured')
        expect(Bloomwire::WhatsappOnboardingAttempt.where(account: account).count).to eq(0)
      end
    end
  end
end
