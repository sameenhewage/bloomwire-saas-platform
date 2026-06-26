require 'rails_helper'

# Bloomwire global Meta WhatsApp webhook GET verification (registration readiness, ADR-0005). The global
# front-door endpoint must answer Meta's webhook-callback verification handshake using ONE global verify
# token (BLOOMWIRE_WHATSAPP_GLOBAL_VERIFY_TOKEN) rather than a per-channel token (there is no phone_number
# in the URL). Feature-gated: OFF == inert 404. ON: valid token echoes hub.challenge, otherwise fail-closed.
# GET verification never touches a phone_number_id, a Bloomwire::WhatsappSetup, or the processing job.
# Fake values only.
RSpec.describe 'Bloomwire global WhatsApp webhook GET verification', type: :request do
  let(:verify_token) { 'fake-global-verify-token' }
  let(:challenge) { '1234567890' }

  def set_toggle(key, value)
    config = InstallationConfig.where(name: key).first_or_initialize
    config.value = value
    config.locked = false
    config.save!
    GlobalConfig.clear_cache
  end

  def enable_router
    set_toggle('BLOOMWIRE_MODE_ENABLED', true)
    set_toggle('BLOOMWIRE_PRIVACY_HARDENING', true)
    set_toggle('BLOOMWIRE_GLOBAL_WEBHOOK_ROUTER', true)
  end

  def set_verify_token
    set_toggle('BLOOMWIRE_WHATSAPP_GLOBAL_VERIFY_TOKEN', verify_token)
  end

  def get_verify(token:, challenge_value: challenge, mode: 'subscribe')
    params = { 'hub.mode' => mode, 'hub.challenge' => challenge_value }
    params['hub.verify_token'] = token unless token.nil?
    get '/bloomwire/webhooks/whatsapp', params: params
  end

  before { GlobalConfig.clear_cache }

  context 'when the router feature is OFF (stock - route inert)' do
    before { set_verify_token }

    it 'returns 404 for the GET verification handshake' do
      get_verify(token: verify_token)
      expect(response).to have_http_status(:not_found)
    end

    it 'does not echo the challenge while OFF' do
      get_verify(token: verify_token)
      expect(response.body).not_to include(challenge)
    end
  end

  context 'when the router feature is ON' do
    before { enable_router }

    context 'with a valid hub.verify_token' do
      before { set_verify_token }

      it 'echoes the hub.challenge with a 200' do
        get_verify(token: verify_token)
        expect(response).to have_http_status(:ok)
        expect(response.body).to include(challenge)
      end

      it 'does not enqueue the WhatsApp processing job' do
        expect(Webhooks::WhatsappEventsJob).not_to receive(:perform_later)
        get_verify(token: verify_token)
      end

      it 'verifies without requiring a phone_number_id (never enters mapping resolution)' do
        expect(Bloomwire::Webhooks::WhatsappRouter).not_to receive(:resolve_handoff_safe_setup)
        get_verify(token: verify_token)
        expect(response).to have_http_status(:ok)
      end

      it 'verifies without any Bloomwire::WhatsappSetup row present' do
        expect(Bloomwire::WhatsappSetup.count).to eq(0)
        get_verify(token: verify_token)
        expect(response).to have_http_status(:ok)
      end

      it 'does not log the verify token' do
        logs = []
        %i[info warn error debug].each do |level|
          allow(Rails.logger).to receive(level) { |msg| logs << msg.to_s }
        end
        get_verify(token: verify_token)
        expect(logs.join("\n")).not_to include(verify_token)
      end
    end

    context 'with an invalid hub.verify_token' do
      before { set_verify_token }

      it 'returns unauthorized and does not echo the challenge' do
        get_verify(token: 'wrong-token')
        expect(response).to have_http_status(:unauthorized)
        expect(response.body).not_to include(challenge)
      end

      it 'does not enqueue the WhatsApp processing job' do
        expect(Webhooks::WhatsappEventsJob).not_to receive(:perform_later)
        get_verify(token: 'wrong-token')
      end
    end

    context 'when the global verify token is not configured (fail closed)' do
      it 'returns unauthorized even when a token is supplied' do
        get_verify(token: verify_token)
        expect(response).to have_http_status(:unauthorized)
        expect(response.body).not_to include(challenge)
      end

      it 'returns unauthorized when no token is supplied' do
        get_verify(token: nil)
        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  describe 'native WhatsApp webhook GET route is unchanged' do
    it 'still routes GET verification to the native per-channel controller' do
      expect(Rails.application.routes.recognize_path('/webhooks/whatsapp/12345', method: :get)).to eq(
        controller: 'webhooks/whatsapp', action: 'verify', phone_number: '12345'
      )
    end
  end
end
