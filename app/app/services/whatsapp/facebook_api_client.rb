class Whatsapp::FacebookApiClient
  BASE_URI = 'https://graph.facebook.com'.freeze

  def initialize(access_token = nil)
    @access_token = access_token
    @api_version = GlobalConfigService.load('WHATSAPP_API_VERSION', Whatsapp::GraphApi::DEFAULT_VERSION)
  end

  def exchange_code_for_token(code)
    response = HTTParty.get(
      "#{BASE_URI}/#{@api_version}/oauth/access_token",
      query: {
        client_id: GlobalConfigService.load('WHATSAPP_APP_ID', ''),
        client_secret: GlobalConfigService.load('WHATSAPP_APP_SECRET', ''),
        code: code
      }
    )

    handle_response(response, 'Token exchange failed')
  end

  def fetch_phone_numbers(waba_id)
    response = HTTParty.get(
      "#{BASE_URI}/#{@api_version}/#{waba_id}/phone_numbers",
      query: { access_token: @access_token }
    )

    handle_response(response, 'WABA phone numbers fetch failed')
  end

  def debug_token(input_token)
    response = HTTParty.get(
      "#{BASE_URI}/#{@api_version}/debug_token",
      query: {
        input_token: input_token,
        access_token: build_app_access_token
      }
    )

    handle_response(response, 'Token validation failed')
  end

  def register_phone_number(phone_number_id, pin)
    response = HTTParty.post(
      "#{BASE_URI}/#{@api_version}/#{phone_number_id}/register",
      headers: request_headers,
      body: { messaging_product: 'whatsapp', pin: pin.to_s }.to_json
    )
    # Same failure contract/message as #handle_response, but raised as a structured Whatsapp::GraphApiError so the
    # managed-signup caller can log the specific Meta error (status/code/subcode/type/is_transient/fbtrace_id)
    # without ever logging the token, PIN, or raw body. On success the parsed body is returned unchanged.
    raise Whatsapp::GraphApiError.from_response('Phone registration failed', response) unless response.success?

    response.parsed_response
  end

  def phone_number_verified?(phone_number_id)
    response = HTTParty.get(
      "#{BASE_URI}/#{@api_version}/#{phone_number_id}",
      headers: request_headers
    )

    data = handle_response(response, 'Phone status check failed')
    data['code_verification_status'] == 'VERIFIED'
  end

  def phone_number_status(phone_number_id)
    response = HTTParty.get(
      "#{BASE_URI}/#{@api_version}/#{phone_number_id}",
      headers: request_headers,
      query: { fields: 'status' }
    )

    handle_response(response, 'Phone status check failed')['status']
  end

  # WABAs this token is authorized to SEND messages for (the whatsapp_business_messaging granular scope). Used to
  # resolve a duplicate number's live registration without ever guessing beyond the token's real grants.
  def messaging_waba_ids(input_token = @access_token)
    data = debug_token(input_token)['data'] || {}
    (data['granular_scopes'] || [])
      .select { |scope| scope['scope'] == 'whatsapp_business_messaging' }
      .flat_map { |scope| scope['target_ids'] }
      .compact.uniq
  end

  # Phone registrations (id + display number + live status) under a WABA. `status` is requested explicitly because
  # Meta omits it from the default phone_numbers field set.
  def waba_registrations(waba_id)
    response = HTTParty.get(
      "#{BASE_URI}/#{@api_version}/#{waba_id}/phone_numbers",
      headers: request_headers,
      query: { fields: 'id,display_phone_number,status' }
    )

    Array(handle_response(response, 'WABA phone numbers fetch failed')['data'])
  end

  # Owner business id of a WABA — used to keep duplicate-number resolution inside the SAME business (never cross a
  # tenant boundary silently). Returns nil when the owner is not visible to this token.
  def waba_owner_business_id(waba_id)
    response = HTTParty.get(
      "#{BASE_URI}/#{@api_version}/#{waba_id}",
      headers: request_headers,
      query: { fields: 'owner_business_info' }
    )

    handle_response(response, 'WABA owner lookup failed').dig('owner_business_info', 'id')
  end

  WEBHOOK_DEFAULT_FIELDS = %w[messages smb_message_echoes].freeze

  def subscribe_waba_webhook(waba_id, callback_url, verify_token, subscribed_fields: WEBHOOK_DEFAULT_FIELDS)
    # Step 1: Subscribe app to WABA first (required before override)
    # Meta requires the app to be subscribed before using override_callback_uri
    # See: https://github.com/chatwoot/chatwoot/issues/13097
    subscribe_app_to_waba(waba_id)

    # Step 2: Override callback URL for this specific WABA
    override_waba_callback(waba_id, callback_url, verify_token, subscribed_fields: subscribed_fields)
  end

  def subscribe_app_to_waba(waba_id)
    response = HTTParty.post(
      "#{BASE_URI}/#{@api_version}/#{waba_id}/subscribed_apps",
      headers: request_headers
    )

    handle_response(response, 'App subscription to WABA failed')
  end

  def override_waba_callback(waba_id, callback_url, verify_token, subscribed_fields: WEBHOOK_DEFAULT_FIELDS)
    response = HTTParty.post(
      "#{BASE_URI}/#{@api_version}/#{waba_id}/subscribed_apps",
      headers: request_headers,
      body: {
        override_callback_uri: callback_url,
        verify_token: verify_token,
        subscribed_fields: subscribed_fields
      }.to_json
    )

    handle_response(response, 'Webhook callback override failed')
  end

  def unsubscribe_waba_webhook(waba_id)
    response = HTTParty.delete(
      "#{BASE_URI}/#{@api_version}/#{waba_id}/subscribed_apps",
      headers: request_headers
    )

    handle_response(response, 'Webhook unsubscription failed')
  end

  # The system-user / user id the supplied token authenticates as (debug_token `data.user_id`). Outbound Cloud
  # API sending is authorized per-ACTOR on the WABA, so onboarding must check the EXACT stored-token actor — not
  # just the token's OAuth scopes (a token can hold whatsapp_business_messaging yet lack the WABA asset task and
  # still get Meta (#10)). Returns nil when the token cannot be introspected.
  def token_actor_id(input_token = @access_token)
    (debug_token(input_token)['data'] || {})['user_id']
  end

  # The token's actor TYPE from debug_token (`data.type`, e.g. "USER" / "SYSTEM_USER"). Used to decide whether a
  # credential may be trusted to ASSIGN a WABA asset task — a view-only SYSTEM_USER cannot self-elevate, so it is
  # never used to self-grant. Returns nil when the token cannot be introspected.
  def token_actor_type(input_token = @access_token)
    (debug_token(input_token)['data'] || {})['type']
  end

  # Business-Manager asset tasks the given user/system-user holds on a WABA (e.g. MANAGE / MESSAGING /
  # VIEW_TEMPLATES) — the effective ASSET assignment, distinct from OAuth granular scopes. Scoped through the
  # WABA's owner business so a partner system-user's assignment is visible. Returns [] when there is no
  # assignment (or it is not visible to this token).
  def waba_user_tasks(waba_id, user_id)
    query = { fields: 'id,name,tasks' }
    owner_business_id = waba_owner_business_id(waba_id)
    query[:business] = owner_business_id if owner_business_id.present?
    response = HTTParty.get(
      "#{BASE_URI}/#{@api_version}/#{waba_id}/assigned_users",
      headers: request_headers,
      query: query
    )
    users = Array(handle_response(response, 'WABA assigned users fetch failed')['data'])
    entry = users.find { |user| user['id'].to_s == user_id.to_s }
    Array(entry && entry['tasks'])
  end

  # Assign Business-Manager asset tasks to a user/system-user on a WABA. Used to ESTABLISH the outbound
  # messaging task for the stored-token actor when the onboarding credential is authorized to grant it; the
  # caller re-reads tasks to verify. Raises on a Meta rejection (e.g. a view-only token cannot self-elevate),
  # so the capability gate fails closed to an explicit Action-Required state rather than a false "ready".
  def assign_waba_user_tasks(waba_id, user_id, tasks)
    response = HTTParty.post(
      "#{BASE_URI}/#{@api_version}/#{waba_id}/assigned_users",
      headers: request_headers,
      query: { user: user_id, tasks: Array(tasks).to_json }
    )
    handle_response(response, 'WABA assigned user task assignment failed')
  end

  private

  def request_headers
    {
      'Authorization' => "Bearer #{@access_token}",
      'Content-Type' => 'application/json'
    }
  end

  def build_app_access_token
    app_id = GlobalConfigService.load('WHATSAPP_APP_ID', '')
    app_secret = GlobalConfigService.load('WHATSAPP_APP_SECRET', '')
    "#{app_id}|#{app_secret}"
  end

  def handle_response(response, error_message)
    raise "#{error_message}: #{response.body}" unless response.success?

    response.parsed_response
  end
end
