# Phase 12B — shared helpers for the Bloomwire WhatsApp E2E test harness (NO real Meta).
#
# Provides: managed-mode config toggling (InstallationConfig + GlobalConfig cache), a Meta HMAC signed-payload
# builder, inbound text / status webhook payload builders, an aligned whatsapp_cloud channel helper, the
# Graph send URL, a Redis dedup cleaner, and a WebMock no-real-Meta guard. All values are deliberately fake;
# no secret is ever a real credential.
module BloomwireWhatsappE2EHelpers
  META_GRAPH_HOST = 'graph.facebook.com'.freeze

  # --- fake, non-secret credentials (never real) -------------------------------------------------------
  def bw_app_secret = 'FAKE-BLOOMWIRE-APP-SECRET-DO-NOT-LEAK'
  def bw_verify_token = 'FAKE-BLOOMWIRE-VERIFY-TOKEN-DO-NOT-LEAK'
  def bw_public_callback_host = 'smoke.example.com'

  # --- config / toggles (DB-backed, read via GlobalConfigService) ---------------------------------------
  def bw_set_config(key, value)
    config = InstallationConfig.where(name: key).first_or_initialize
    config.value = value
    config.locked = false
    config.save!
    GlobalConfig.clear_cache
  end

  def bw_enable_router
    bw_set_config('BLOOMWIRE_MODE_ENABLED', true)
    bw_set_config('BLOOMWIRE_PRIVACY_HARDENING', true)
    bw_set_config('BLOOMWIRE_GLOBAL_WEBHOOK_ROUTER', true)
  end

  def bw_set_app_secret(secret = bw_app_secret)
    bw_set_config('WHATSAPP_APP_SECRET', secret)
  end

  def bw_set_verify_token(token = bw_verify_token)
    bw_set_config('BLOOMWIRE_WHATSAPP_GLOBAL_VERIFY_TOKEN', token)
  end

  def bw_set_public_callback_host(host = bw_public_callback_host)
    bw_set_config('BLOOMWIRE_WHATSAPP_PUBLIC_CALLBACK_HOST', host)
  end

  # Everything the real-hop readiness gate checks (toggles + secrets + callback host).
  def bw_enable_all
    bw_enable_router
    bw_set_app_secret
    bw_set_verify_token
    bw_set_public_callback_host
  end

  # --- Meta signature (X-Hub-Signature-256: sha256=HMAC-SHA256(secret, raw_body)) ------------------------
  def bw_sign(body, secret: bw_app_secret)
    "sha256=#{OpenSSL::HMAC.hexdigest('SHA256', secret, body)}"
  end

  # --- inbound webhook payload builders -----------------------------------------------------------------
  # A realistic Meta WhatsApp Cloud inbound TEXT payload that the existing pipeline turns into a Message.
  # rubocop:disable Metrics/ParameterLists
  def bw_inbound_text_payload(phone_number_id:, display_phone_number: '15551230001', from: '15559990001',
                              wamid: 'wamid.INBOUND-1', body: 'hello there', name: 'Test Customer')
    {
      'object' => 'whatsapp_business_account',
      'entry' => [{
        'id' => 'WABA-FAKE',
        'changes' => [{
          'field' => 'messages',
          'value' => {
            'metadata' => { 'display_phone_number' => display_phone_number, 'phone_number_id' => phone_number_id },
            'contacts' => [{ 'profile' => { 'name' => name }, 'wa_id' => from }],
            'messages' => [{ 'from' => from, 'id' => wamid, 'timestamp' => '1700000000',
                             'text' => { 'body' => body }, 'type' => 'text' }]
          }
        }]
      }]
    }
  end

  # A Meta WhatsApp Cloud delivery/read/failed STATUS payload keyed on a previously-sent message's wamid.
  def bw_status_payload(phone_number_id:, wamid:, status:, display_phone_number: '15551230001',
                        recipient: '15559990001', errors: nil)
    status_hash = { 'id' => wamid, 'status' => status, 'timestamp' => '1700000300', 'recipient_id' => recipient }
    status_hash['errors'] = errors if errors
    {
      'object' => 'whatsapp_business_account',
      'entry' => [{
        'id' => 'WABA-FAKE',
        'changes' => [{
          'field' => 'statuses',
          'value' => {
            'metadata' => { 'display_phone_number' => display_phone_number, 'phone_number_id' => phone_number_id },
            'statuses' => [status_hash]
          }
        }]
      }]
    }
  end
  # rubocop:enable Metrics/ParameterLists

  # --- POST to the Bloomwire global router endpoint -----------------------------------------------------
  # signature: :valid (default) signs with `secret`; pass a String to force an exact (e.g. bad) signature;
  # pass nil to omit the header entirely.
  def bw_post_router(payload, signature: :valid, secret: bw_app_secret)
    body = payload.to_json
    headers = { 'CONTENT_TYPE' => 'application/json' }
    sig = signature == :valid ? bw_sign(body, secret: secret) : signature
    headers['X-Hub-Signature-256'] = sig unless sig.nil?
    post '/bloomwire/webhooks/whatsapp', params: body, headers: headers
  end

  # --- aligned channel helper (for outbound specs that don't need a Bloomwire mapping) ------------------
  def bw_aligned_whatsapp_channel(account:, phone_number_id: 'PNID-OUT-1', display_phone_number: '15551230002',
                                  api_key: 'FAKE-OUT-APIKEY')
    channel = create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud',
                                        phone_number: "+#{display_phone_number}",
                                        sync_templates: false, validate_provider_config: false)
    channel.update!(provider_config: channel.provider_config.merge('phone_number_id' => phone_number_id,
                                                                   'source' => 'embedded_signup',
                                                                   'api_key' => api_key))
    channel
  end

  # --- misc --------------------------------------------------------------------------------------------
  def bw_graph_messages_url(phone_number_id, version: 'v24.0')
    "https://#{META_GRAPH_HOST}/#{version}/#{phone_number_id}/messages"
  end

  def bw_clear_message_dedup
    Redis::Alfred.scan_each(match: 'MESSAGE_SOURCE_KEY::*') { |key| Redis::Alfred.delete(key) }
  end

  # WebMock guard: with disable_net_connect!(allow_localhost: true) any non-localhost host (Meta Graph)
  # is blocked unless explicitly stubbed — this is the no-real-Meta guarantee.
  def bw_meta_net_connect_blocked?
    !WebMock.net_connect_allowed?("https://#{META_GRAPH_HOST}/v24.0/whatever/messages")
  end
end

RSpec.configure do |config|
  config.include BloomwireWhatsappE2EHelpers
end
