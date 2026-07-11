require 'rails_helper'

# Bloomwire global Meta WhatsApp webhook router endpoint. Feature-gated + signature-verified; on a matching
# ready_for_webhook mapping it hands the raw payload to the EXISTING Webhooks::WhatsappEventsJob (no new
# processing, no duplicate message/conversation storage). Fail-closed otherwise. Fake values only.
RSpec.describe 'Bloomwire global WhatsApp webhook router', type: :request do
  let(:account) { create(:account) }
  let(:app_secret) { 'fake-global-app-secret' }

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

  def set_app_secret
    set_toggle('WHATSAPP_APP_SECRET', app_secret)
  end

  def meta_payload(phone_number_id:, body: 'hello')
    {
      'object' => 'whatsapp_business_account',
      'entry' => [{
        'id' => 'WABA-123',
        'changes' => [{
          'field' => 'messages',
          'value' => {
            'metadata' => { 'display_phone_number' => '15551230001', 'phone_number_id' => phone_number_id },
            'messages' => [{ 'from' => '15559990001', 'id' => 'wamid.X', 'text' => { 'body' => body } }]
          }
        }]
      }]
    }
  end

  def post_webhook(payload, signature: nil)
    body = payload.to_json
    headers = { 'CONTENT_TYPE' => 'application/json' }
    headers['X-Hub-Signature-256'] = signature || "sha256=#{OpenSSL::HMAC.hexdigest('SHA256', app_secret, body)}"
    post '/bloomwire/webhooks/whatsapp', params: body, headers: headers
  end

  # Aligned with the native job resolution path: channel.phone_number == "+<display>" and
  # channel.provider_config['phone_number_id'] == the setup's phone_number_id (the default payload display).
  def ready_setup(phone_number_id:, display_phone_number: '15551230001')
    channel = create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud',
                                        phone_number: "+#{display_phone_number}", sync_templates: false,
                                        validate_provider_config: false)
    channel.update!(provider_config: channel.provider_config.merge('phone_number_id' => phone_number_id,
                                                                   'source' => 'embedded_signup'))
    create(:bloomwire_whatsapp_setup, account: account, inbox: channel.inbox, channel_whatsapp: channel,
                                      phone_number_id: phone_number_id, setup_status: 'ready_for_webhook')
    channel
  end

  before { GlobalConfig.clear_cache }

  context 'when the router feature is OFF (stock - route inert)' do
    before { set_app_secret }

    it 'returns 404 and does not hand off to processing' do
      ready_setup(phone_number_id: 'PNID-1')
      expect(Webhooks::WhatsappEventsJob).not_to receive(:perform_later)
      post_webhook(meta_payload(phone_number_id: 'PNID-1'))
      expect(response).to have_http_status(:not_found)
    end
  end

  context 'when the router feature is ON' do
    before do
      enable_router
      set_app_secret
    end

    it 'hands a matching payload off to the existing WhatsApp processing job' do
      ready_setup(phone_number_id: 'PNID-1')
      expect(Webhooks::WhatsappEventsJob).to receive(:perform_later)
      post_webhook(meta_payload(phone_number_id: 'PNID-1'))
      expect(response).to have_http_status(:ok)
    end

    it 'fails closed for an unknown phone_number_id (no handoff, safe 200)' do
      ready_setup(phone_number_id: 'PNID-1')
      expect(Webhooks::WhatsappEventsJob).not_to receive(:perform_later)
      post_webhook(meta_payload(phone_number_id: 'PNID-UNKNOWN'))
      expect(response).to have_http_status(:ok)
    end

    it 'fails closed when the mapping is not ready_for_webhook' do
      channel = create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false,
                                          validate_provider_config: false)
      create(:bloomwire_whatsapp_setup, account: account, inbox: channel.inbox, channel_whatsapp: channel,
                                        phone_number_id: 'PNID-CFG', setup_status: 'configured')
      expect(Webhooks::WhatsappEventsJob).not_to receive(:perform_later)
      post_webhook(meta_payload(phone_number_id: 'PNID-CFG'))
      expect(response).to have_http_status(:ok)
    end

    it 'does not enqueue when the mapped channel alignment fails (provider_config phone_number_id mismatch)' do
      channel = ready_setup(phone_number_id: 'PNID-1')
      channel.update!(provider_config: channel.provider_config.merge('phone_number_id' => 'PNID-DIFFERENT'))
      expect(Webhooks::WhatsappEventsJob).not_to receive(:perform_later)
      post_webhook(meta_payload(phone_number_id: 'PNID-1'))
      expect(response).to have_http_status(:ok)
    end

    it 'rejects a request with an invalid Meta signature' do
      ready_setup(phone_number_id: 'PNID-1')
      expect(Webhooks::WhatsappEventsJob).not_to receive(:perform_later)
      post_webhook(meta_payload(phone_number_id: 'PNID-1'), signature: 'sha256=deadbeef')
      expect(response).to have_http_status(:unauthorized)
    end

    it 'does not create app-side conversation records (no duplication)' do
      ready_setup(phone_number_id: 'PNID-1')
      allow(Webhooks::WhatsappEventsJob).to receive(:perform_later)
      expect { post_webhook(meta_payload(phone_number_id: 'PNID-1')) }.not_to change(Conversation, :count)
    end

    it 'does not create app-side message records (no duplication)' do
      ready_setup(phone_number_id: 'PNID-1')
      allow(Webhooks::WhatsappEventsJob).to receive(:perform_later)
      expect { post_webhook(meta_payload(phone_number_id: 'PNID-1')) }.not_to change(Message, :count)
    end

    it 'logs only redacted, non-secret diagnostics from the router (no tokens, no full ids)' do
      channel = ready_setup(phone_number_id: 'PNID-9999')
      channel.update!(provider_config: channel.provider_config.merge('api_key' => 'FAKE-WH-APIKEY',
                                                                     'source' => 'embedded_signup'))
      router_logs = []
      %i[info warn error debug].each do |level|
        allow(Rails.logger).to receive(level) { |msg| router_logs << msg.to_s if msg.to_s.include?('[BLOOMWIRE ROUTER]') }
      end
      # Non-matching id => router takes its explicit (redacted) diagnostic log path.
      post_webhook(meta_payload(phone_number_id: 'PNID-UNKNOWN-1234'))
      joined = router_logs.join("\n")
      expect(joined).to include('[BLOOMWIRE ROUTER]')
      expect(joined).to include('****1234')
      expect(joined).not_to include('PNID-UNKNOWN-1234')
      expect(joined).not_to include('FAKE-WH-APIKEY')
    end
  end

  # account_update / PARTNER_REMOVED is Meta's authoritative Coexistence offboarding signal. It is WABA-keyed
  # (no message phone_number_id), so it is handled by the reconciler in the signed front door and is NEVER routed
  # to the message-only Webhooks::WhatsappEventsJob. Signature is still verified first; logs stay redacted.
  context 'when the router feature is ON (account_update / PARTNER_REMOVED reconciliation)' do
    before do
      enable_router
      set_app_secret
    end

    def coexistence_setup(waba_id:, phone_number_id:, display_phone_number: '15551230001',
                          status: 'ready_for_webhook')
      channel = create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud',
                                          phone_number: "+#{display_phone_number}", sync_templates: false,
                                          validate_provider_config: false)
      channel.update!(provider_config: channel.provider_config.merge(
        'phone_number_id' => phone_number_id, 'business_account_id' => waba_id,
        'connection_mode' => 'coexistence', 'source' => 'bloomwire_managed', 'api_key' => 'FAKE-WH-APIKEY'
      ))
      create(:bloomwire_whatsapp_setup, account: account, inbox: channel.inbox, channel_whatsapp: channel,
                                        phone_number_id: phone_number_id, waba_id: waba_id,
                                        display_phone_number: "+#{display_phone_number}", setup_status: status)
    end

    def account_update_payload(waba_id:, event: 'PARTNER_REMOVED')
      { 'object' => 'whatsapp_business_account',
        'entry' => [{ 'id' => waba_id, 'time' => 1_700_000_000,
                      'changes' => [{ 'field' => 'account_update',
                                      'value' => { 'event' => event,
                                                   'waba_info' => { 'waba_id' => waba_id,
                                                                    'owner_business_id' => 'BIZ-1' } } }] }] }
    end

    it 'reconciles PARTNER_REMOVED (marks the coexistence setup disconnected) and never enqueues the message job' do
      setup = coexistence_setup(waba_id: 'WABA-RM', phone_number_id: 'PNID-RM')
      expect(Webhooks::WhatsappEventsJob).not_to receive(:perform_later)

      post_webhook(account_update_payload(waba_id: 'WABA-RM'))

      aggregate_failures do
        expect(response).to have_http_status(:ok)
        expect(setup.reload.setup_status).to eq(Bloomwire::WhatsappSetup::DISCONNECTED_STATUS)
      end
    end

    it 'rejects an invalid Meta signature and changes nothing' do
      setup = coexistence_setup(waba_id: 'WABA-RM', phone_number_id: 'PNID-RM')
      expect(Webhooks::WhatsappEventsJob).not_to receive(:perform_later)

      post_webhook(account_update_payload(waba_id: 'WABA-RM'), signature: 'sha256=deadbeef')

      aggregate_failures do
        expect(response).to have_http_status(:unauthorized)
        expect(setup.reload.setup_status).to eq(Bloomwire::WhatsappSetup::ROUTEABLE_STATUS)
      end
    end

    it 'does not enqueue the message job for an unrelated account_update event and changes nothing' do
      setup = coexistence_setup(waba_id: 'WABA-RM', phone_number_id: 'PNID-RM')
      expect(Webhooks::WhatsappEventsJob).not_to receive(:perform_later)

      post_webhook(account_update_payload(waba_id: 'WABA-RM', event: 'ACCOUNT_VERIFIED'))

      aggregate_failures do
        expect(response).to have_http_status(:ok)
        expect(setup.reload.setup_status).to eq(Bloomwire::WhatsappSetup::ROUTEABLE_STATUS)
      end
    end

    it 'is idempotent across a duplicate PARTNER_REMOVED delivery' do
      setup = coexistence_setup(waba_id: 'WABA-RM', phone_number_id: 'PNID-RM')
      post_webhook(account_update_payload(waba_id: 'WABA-RM'))
      post_webhook(account_update_payload(waba_id: 'WABA-RM'))

      aggregate_failures do
        expect(response).to have_http_status(:ok)
        expect(setup.reload.setup_status).to eq(Bloomwire::WhatsappSetup::DISCONNECTED_STATUS)
      end
    end

    it 'logs only redacted diagnostics for the reconciliation (masked WABA tail, no full WABA, no token)' do
      coexistence_setup(waba_id: 'WABA-SECRET-7788', phone_number_id: 'PNID-RM')
      router_logs = []
      %i[info warn error debug].each do |level|
        allow(Rails.logger).to receive(level) { |msg| router_logs << msg.to_s if msg.to_s.include?('[BLOOMWIRE ROUTER]') }
      end

      post_webhook(account_update_payload(waba_id: 'WABA-SECRET-7788'))

      joined = router_logs.join("\n")
      aggregate_failures do
        expect(joined).to include('[BLOOMWIRE ROUTER]')
        expect(joined).to include('****7788')
        expect(joined).not_to include('WABA-SECRET-7788')
        expect(joined).not_to include('FAKE-WH-APIKEY')
      end
    end
  end

  describe 'native WhatsApp webhook route is unchanged' do
    it 'still routes to the native controller' do
      expect(Rails.application.routes.recognize_path('/webhooks/whatsapp/12345', method: :post)).to eq(
        controller: 'webhooks/whatsapp', action: 'process_payload', phone_number: '12345'
      )
    end
  end
end
