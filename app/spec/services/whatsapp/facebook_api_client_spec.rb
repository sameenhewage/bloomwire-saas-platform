require 'rails_helper'

describe Whatsapp::FacebookApiClient do
  let(:access_token) { 'test_access_token' }
  let(:api_client) { described_class.new(access_token) }
  # Approved Meta Graph API version contract: the client must default to v25.0 (the shared source of truth),
  # not an older inherited version. We stub the load with the NEW default arg so the version the client
  # actually requests is asserted through every generated Graph URL below.
  let(:api_version) { Whatsapp::GraphApi::DEFAULT_VERSION }
  let(:app_id) { 'test_app_id' }
  let(:app_secret) { 'test_app_secret' }

  before do
    allow(GlobalConfigService).to receive(:load).with('WHATSAPP_API_VERSION', Whatsapp::GraphApi::DEFAULT_VERSION).and_return(api_version)
    allow(GlobalConfigService).to receive(:load).with('WHATSAPP_APP_ID', '').and_return(app_id)
    allow(GlobalConfigService).to receive(:load).with('WHATSAPP_APP_SECRET', '').and_return(app_secret)
    # Graph HTTP timeouts are config-driven via Whatsapp::GraphApiTimeouts; stub the provider so these specs do not
    # need to also stub the timeout config keys on GlobalConfigService.
    allow(Whatsapp::GraphApiTimeouts).to receive_messages(open_seconds: 5, read_seconds: 25)
  end

  it 'defaults to the approved v25.0 Graph API version' do
    expect(Whatsapp::GraphApi::DEFAULT_VERSION).to eq('v25.0')
    expect(api_version).to eq('v25.0')
  end

  describe 'generated Meta Graph URLs use the approved v25.0 version' do
    let(:waba_id) { 'waba-x' }

    it 'builds the token-exchange, WABA, phone, debug, register and webhook-subscription URLs on /v25.0/' do
      stub = stub_request(:any, %r{https://graph\.facebook\.com/v25\.0/.*}).to_return(
        status: 200, body: { data: [], success: true, code_verification_status: 'VERIFIED' }.to_json,
        headers: { 'Content-Type' => 'application/json' }
      )
      api_client.exchange_code_for_token('c')
      api_client.fetch_phone_numbers(waba_id)
      api_client.debug_token('t')
      api_client.register_phone_number('pnid', '123456')
      api_client.phone_number_verified?('pnid')
      api_client.phone_number_status('pnid')
      api_client.subscribe_app_to_waba(waba_id)
      expect(stub).to have_been_requested.at_least_once
      expect(a_request(:any, %r{https://graph\.facebook\.com/v(1[0-9]|2[0-4])\.0/})).not_to have_been_made
    end
  end

  describe '#exchange_code_for_token' do
    let(:code) { 'test_code' }

    context 'when successful' do
      before do
        stub_request(:get, "https://graph.facebook.com/#{api_version}/oauth/access_token")
          .with(query: { client_id: app_id, client_secret: app_secret, code: code })
          .to_return(
            status: 200,
            body: { access_token: 'new_token' }.to_json,
            headers: { 'Content-Type' => 'application/json' }
          )
      end

      it 'returns the response data' do
        result = api_client.exchange_code_for_token(code)
        expect(result['access_token']).to eq('new_token')
      end
    end

    context 'when failed' do
      before do
        stub_request(:get, "https://graph.facebook.com/#{api_version}/oauth/access_token")
          .with(query: { client_id: app_id, client_secret: app_secret, code: code })
          .to_return(status: 400, body: { error: 'Invalid code' }.to_json)
      end

      it 'raises an error' do
        expect { api_client.exchange_code_for_token(code) }.to raise_error(/Token exchange failed/)
      end
    end
  end

  describe '#exchange_for_long_lived_token' do
    let(:short_token) { 'short-lived-user-token' }

    it 'exchanges via the fb_exchange_token grant and returns the long-lived token (WhatsWay-proven step)' do
      stub_request(:get, "https://graph.facebook.com/#{api_version}/oauth/access_token")
        .with(query: { grant_type: 'fb_exchange_token', client_id: app_id, client_secret: app_secret,
                       fb_exchange_token: short_token })
        .to_return(status: 200, body: { access_token: 'long-lived-60d' }.to_json,
                   headers: { 'Content-Type' => 'application/json' })
      expect(api_client.exchange_for_long_lived_token(short_token)).to eq('long-lived-60d')
    end

    it 'fails open to the input token when Meta does not return a long-lived token' do
      stub_request(:get, "https://graph.facebook.com/#{api_version}/oauth/access_token")
        .with(query: hash_including(grant_type: 'fb_exchange_token'))
        .to_return(status: 400, body: { error: 'bad' }.to_json)
      expect(api_client.exchange_for_long_lived_token(short_token)).to eq(short_token)
    end

    # WhatsWay-exact: WhatsWay does NOT try/catch this fetch, so a transport error PROPAGATES and the caller
    # (perform_meta_steps) fails closed. We must NOT swallow it into a fail-open short token (that would diverge).
    it 'propagates a transport error (does NOT fail open) — matches WhatsWay' do
      allow(HTTParty).to receive(:get).and_raise(StandardError, 'network down')
      expect { api_client.exchange_for_long_lived_token(short_token) }.to raise_error(StandardError, 'network down')
    end
  end

  describe '#deregister_phone_number' do
    let(:phone_number_id) { 'PNID-1' }

    it 'POSTs /deregister with messaging_product and returns the parsed body' do
      stub = stub_request(:post, "https://graph.facebook.com/#{api_version}/#{phone_number_id}/deregister")
             .with(body: { messaging_product: 'whatsapp' }.to_json,
                   headers: { 'Authorization' => "Bearer #{access_token}" })
             .to_return(status: 200, body: { success: true }.to_json, headers: { 'Content-Type' => 'application/json' })
      expect(api_client.deregister_phone_number(phone_number_id)).to eq('success' => true)
      expect(stub).to have_been_requested
    end

    it 'raises a Whatsapp::GraphApiError on failure (the caller treats it as non-fatal)' do
      stub_request(:post, "https://graph.facebook.com/#{api_version}/#{phone_number_id}/deregister")
        .to_return(status: 400, body: { error: { message: 'nope', code: 100 } }.to_json,
                   headers: { 'Content-Type' => 'application/json' })
      expect { api_client.deregister_phone_number(phone_number_id) }.to raise_error(Whatsapp::GraphApiError)
    end
  end

  describe '#fetch_phone_numbers' do
    let(:waba_id) { 'test_waba_id' }

    context 'when successful' do
      before do
        stub_request(:get, "https://graph.facebook.com/#{api_version}/#{waba_id}/phone_numbers")
          .with(query: { access_token: access_token })
          .to_return(
            status: 200,
            body: { data: [{ id: '123', display_phone_number: '1234567890' }] }.to_json,
            headers: { 'Content-Type' => 'application/json' }
          )
      end

      it 'returns the phone numbers data' do
        result = api_client.fetch_phone_numbers(waba_id)
        expect(result['data']).to be_an(Array)
        expect(result['data'].first['id']).to eq('123')
      end
    end

    context 'when failed' do
      before do
        stub_request(:get, "https://graph.facebook.com/#{api_version}/#{waba_id}/phone_numbers")
          .with(query: { access_token: access_token })
          .to_return(status: 403, body: { error: 'Access denied' }.to_json)
      end

      it 'raises an error' do
        expect { api_client.fetch_phone_numbers(waba_id) }.to raise_error(/WABA phone numbers fetch failed/)
      end
    end
  end

  describe '#debug_token' do
    let(:input_token) { 'test_input_token' }
    let(:app_access_token) { "#{app_id}|#{app_secret}" }

    context 'when successful' do
      before do
        stub_request(:get, "https://graph.facebook.com/#{api_version}/debug_token")
          .with(query: { input_token: input_token, access_token: app_access_token })
          .to_return(
            status: 200,
            body: { data: { app_id: app_id, is_valid: true } }.to_json,
            headers: { 'Content-Type' => 'application/json' }
          )
      end

      it 'returns the debug token data' do
        result = api_client.debug_token(input_token)
        expect(result['data']['is_valid']).to be(true)
      end
    end

    context 'when failed' do
      before do
        stub_request(:get, "https://graph.facebook.com/#{api_version}/debug_token")
          .with(query: { input_token: input_token, access_token: app_access_token })
          .to_return(status: 400, body: { error: 'Invalid token' }.to_json)
      end

      it 'raises an error' do
        expect { api_client.debug_token(input_token) }.to raise_error(/Token validation failed/)
      end
    end
  end

  describe '#register_phone_number' do
    let(:phone_number_id) { 'test_phone_id' }
    let(:pin) { '123456' }

    context 'when successful' do
      before do
        stub_request(:post, "https://graph.facebook.com/#{api_version}/#{phone_number_id}/register")
          .with(
            headers: { 'Authorization' => "Bearer #{access_token}", 'Content-Type' => 'application/json' },
            body: { messaging_product: 'whatsapp', pin: pin }.to_json
          )
          .to_return(
            status: 200,
            body: { success: true }.to_json,
            headers: { 'Content-Type' => 'application/json' }
          )
      end

      it 'returns success response' do
        result = api_client.register_phone_number(phone_number_id, pin)
        expect(result['success']).to be(true)
      end
    end

    context 'when failed' do
      before do
        stub_request(:post, "https://graph.facebook.com/#{api_version}/#{phone_number_id}/register")
          .with(
            headers: { 'Authorization' => "Bearer #{access_token}", 'Content-Type' => 'application/json' },
            body: { messaging_product: 'whatsapp', pin: pin }.to_json
          )
          .to_return(status: 400, body: { error: 'Registration failed' }.to_json)
      end

      it 'raises an error' do
        expect { api_client.register_phone_number(phone_number_id, pin) }.to raise_error(/Phone registration failed/)
      end
    end

    context 'when Meta returns a structured Graph error' do
      let(:meta_body) do
        { error: { message: '(#100) Object with ID does not exist or app lacks permission',
                   type: 'OAuthException', code: 100, error_subcode: 33, is_transient: false,
                   fbtrace_id: 'SAFE_TRACE_ID' } }.to_json
      end

      before do
        stub_request(:post, "https://graph.facebook.com/#{api_version}/#{phone_number_id}/register")
          .to_return(status: 400, body: meta_body, headers: { 'Content-Type' => 'application/json' })
      end

      it 'raises a Whatsapp::GraphApiError carrying the sanitized Meta error fields (still matching the legacy message)' do
        api_client.register_phone_number(phone_number_id, pin)
      rescue Whatsapp::GraphApiError => e
        aggregate_failures do
          expect(e.message).to match(/Phone registration failed/)
          expect(e.http_status).to eq(400)
          expect(e.error_code).to eq(100)
          expect(e.error_subcode).to eq(33)
          expect(e.error_type).to eq('OAuthException')
          expect(e.is_transient).to be(false)
          expect(e.fbtrace_id).to eq('SAFE_TRACE_ID')
          expect(e.safe_message).to include('does not exist')
        end
      else
        raise 'expected Whatsapp::GraphApiError to be raised'
      end
    end
  end

  describe '#phone_number_status' do
    let(:phone_number_id) { 'test_phone_id' }

    it 'returns the Meta connection status' do
      stub_request(:get, "https://graph.facebook.com/#{api_version}/#{phone_number_id}")
        .with(query: { fields: 'status' })
        .to_return(status: 200, body: { status: 'CONNECTED' }.to_json, headers: { 'Content-Type' => 'application/json' })
      expect(api_client.phone_number_status(phone_number_id)).to eq('CONNECTED')
    end

    it 'raises an error when the status check fails' do
      stub_request(:get, "https://graph.facebook.com/#{api_version}/#{phone_number_id}")
        .with(query: { fields: 'status' })
        .to_return(status: 400, body: { error: 'bad' }.to_json)
      expect { api_client.phone_number_status(phone_number_id) }.to raise_error(/Phone status check failed/)
    end
  end

  describe '#subscribe_waba_webhook' do
    let(:waba_id) { 'test_waba_id' }
    let(:callback_url) { 'https://example.com/webhook' }
    let(:verify_token) { 'test_verify_token' }

    context 'when successful' do
      before do
        # Step 1: Subscribe app to WABA (no body)
        stub_request(:post, "https://graph.facebook.com/#{api_version}/#{waba_id}/subscribed_apps")
          .with(
            headers: { 'Authorization' => "Bearer #{access_token}", 'Content-Type' => 'application/json' }
          )
          .to_return(
            status: 200,
            body: { success: true }.to_json,
            headers: { 'Content-Type' => 'application/json' }
          )

        # Step 2: Override callback URL (with body)
        stub_request(:post, "https://graph.facebook.com/#{api_version}/#{waba_id}/subscribed_apps")
          .with(
            headers: { 'Authorization' => "Bearer #{access_token}", 'Content-Type' => 'application/json' },
            body: { override_callback_uri: callback_url, verify_token: verify_token,
                    subscribed_fields: %w[messages smb_message_echoes] }.to_json
          )
          .to_return(
            status: 200,
            body: { success: true }.to_json,
            headers: { 'Content-Type' => 'application/json' }
          )
      end

      it 'returns success response' do
        result = api_client.subscribe_waba_webhook(waba_id, callback_url, verify_token)
        expect(result['success']).to be(true)
      end
    end

    context 'when app subscription fails' do
      before do
        stub_request(:post, "https://graph.facebook.com/#{api_version}/#{waba_id}/subscribed_apps")
          .with(
            headers: { 'Authorization' => "Bearer #{access_token}", 'Content-Type' => 'application/json' }
          )
          .to_return(status: 400, body: { error: 'App subscription to WABA failed' }.to_json)
      end

      it 'raises an error' do
        expect { api_client.subscribe_waba_webhook(waba_id, callback_url, verify_token) }.to raise_error(/App subscription to WABA failed/)
      end
    end

    context 'when callback override fails' do
      before do
        # Step 1 succeeds
        stub_request(:post, "https://graph.facebook.com/#{api_version}/#{waba_id}/subscribed_apps")
          .with(
            headers: { 'Authorization' => "Bearer #{access_token}", 'Content-Type' => 'application/json' }
          )
          .to_return(
            status: 200,
            body: { success: true }.to_json,
            headers: { 'Content-Type' => 'application/json' }
          )

        # Step 2 fails
        stub_request(:post, "https://graph.facebook.com/#{api_version}/#{waba_id}/subscribed_apps")
          .with(
            headers: { 'Authorization' => "Bearer #{access_token}", 'Content-Type' => 'application/json' },
            body: { override_callback_uri: callback_url, verify_token: verify_token,
                    subscribed_fields: %w[messages smb_message_echoes] }.to_json
          )
          .to_return(status: 400, body: { error: 'Webhook callback override failed' }.to_json)
      end

      it 'raises an error' do
        expect { api_client.subscribe_waba_webhook(waba_id, callback_url, verify_token) }.to raise_error(/Webhook callback override failed/)
      end
    end
  end

  describe '#unsubscribe_waba_webhook' do
    let(:waba_id) { 'test_waba_id' }

    context 'when successful' do
      before do
        stub_request(:delete, "https://graph.facebook.com/#{api_version}/#{waba_id}/subscribed_apps")
          .with(
            headers: { 'Authorization' => "Bearer #{access_token}", 'Content-Type' => 'application/json' }
          )
          .to_return(
            status: 200,
            body: { success: true }.to_json,
            headers: { 'Content-Type' => 'application/json' }
          )
      end

      it 'returns success response' do
        result = api_client.unsubscribe_waba_webhook(waba_id)
        expect(result['success']).to be(true)
      end
    end

    context 'when failed' do
      before do
        stub_request(:delete, "https://graph.facebook.com/#{api_version}/#{waba_id}/subscribed_apps")
          .with(
            headers: { 'Authorization' => "Bearer #{access_token}", 'Content-Type' => 'application/json' }
          )
          .to_return(status: 400, body: { error: 'Webhook unsubscription failed' }.to_json)
      end

      it 'raises an error' do
        expect { api_client.unsubscribe_waba_webhook(waba_id) }.to raise_error(/Webhook unsubscription failed/)
      end
    end
  end

  describe '#token_actor_id' do
    let(:input_token) { 'actor-token' }
    let(:app_access_token) { "#{app_id}|#{app_secret}" }

    it 'returns the debug_token data.user_id (the system-user/user the token authenticates as)' do
      stub_request(:get, "https://graph.facebook.com/#{api_version}/debug_token")
        .with(query: { input_token: input_token, access_token: app_access_token })
        .to_return(status: 200, body: { data: { user_id: 'SYS-USER-9', type: 'SYSTEM_USER' } }.to_json,
                   headers: { 'Content-Type' => 'application/json' })
      expect(api_client.token_actor_id(input_token)).to eq('SYS-USER-9')
    end
  end

  describe '#token_actor_type' do
    let(:input_token) { 'actor-token' }
    let(:app_access_token) { "#{app_id}|#{app_secret}" }

    it 'returns the debug_token data.type (used to gate whether a token may assign a WABA task)' do
      stub_request(:get, "https://graph.facebook.com/#{api_version}/debug_token")
        .with(query: { input_token: input_token, access_token: app_access_token })
        .to_return(status: 200, body: { data: { user_id: 'USER-9', type: 'USER' } }.to_json,
                   headers: { 'Content-Type' => 'application/json' })
      expect(api_client.token_actor_type(input_token)).to eq('USER')
    end
  end

  describe '#waba_user_tasks' do
    let(:waba_id) { 'waba-x' }
    let(:user_id) { 'ACTOR-1' }

    before do
      stub_request(:get, "https://graph.facebook.com/#{api_version}/#{waba_id}")
        .with(query: { fields: 'owner_business_info' })
        .to_return(status: 200, body: { owner_business_info: { id: 'BIZ-OWNER' } }.to_json,
                   headers: { 'Content-Type' => 'application/json' })
    end

    it 'returns the asset tasks the exact actor holds on the WABA (scoped through the owner business)' do
      stub_request(:get, "https://graph.facebook.com/#{api_version}/#{waba_id}/assigned_users")
        .with(query: { fields: 'id,name,tasks', business: 'BIZ-OWNER' })
        .to_return(status: 200,
                   body: { data: [{ id: 'OTHER', tasks: ['MANAGE'] },
                                  { id: user_id, tasks: %w[VIEW_TEMPLATES MANAGE] }] }.to_json,
                   headers: { 'Content-Type' => 'application/json' })
      expect(api_client.waba_user_tasks(waba_id, user_id)).to contain_exactly('VIEW_TEMPLATES', 'MANAGE')
    end

    it 'returns nil when the actor is ABSENT from the list (absence is not proof of missing -> unverifiable)' do
      stub_request(:get, "https://graph.facebook.com/#{api_version}/#{waba_id}/assigned_users")
        .with(query: { fields: 'id,name,tasks', business: 'BIZ-OWNER' })
        .to_return(status: 200, body: { data: [{ id: 'SOMEONE-ELSE', tasks: ['MANAGE'] }] }.to_json,
                   headers: { 'Content-Type' => 'application/json' })
      expect(api_client.waba_user_tasks(waba_id, user_id)).to be_nil
    end

    it 'returns [] (not nil) when the actor is PRESENT but holds no tasks (authoritative verified-missing)' do
      stub_request(:get, "https://graph.facebook.com/#{api_version}/#{waba_id}/assigned_users")
        .with(query: { fields: 'id,name,tasks', business: 'BIZ-OWNER' })
        .to_return(status: 200, body: { data: [{ id: user_id, tasks: [] }] }.to_json,
                   headers: { 'Content-Type' => 'application/json' })
      expect(api_client.waba_user_tasks(waba_id, user_id)).to eq([])
    end
  end

  describe '#subscribed_to_waba?' do
    let(:waba_id) { 'waba-x' }

    it 'is true when THIS app is present in the WABA subscribed_apps list' do
      stub_request(:get, "https://graph.facebook.com/#{api_version}/#{waba_id}/subscribed_apps")
        .to_return(status: 200,
                   body: { data: [{ whatsapp_business_api_data: { id: app_id, name: 'Bloomwire' } }] }.to_json,
                   headers: { 'Content-Type' => 'application/json' })
      expect(api_client.subscribed_to_waba?(waba_id)).to be(true)
    end

    it 'is false when this app is NOT in the subscribed_apps list' do
      stub_request(:get, "https://graph.facebook.com/#{api_version}/#{waba_id}/subscribed_apps")
        .to_return(status: 200, body: { data: [{ whatsapp_business_api_data: { id: 'OTHER-APP' } }] }.to_json,
                   headers: { 'Content-Type' => 'application/json' })
      expect(api_client.subscribed_to_waba?(waba_id)).to be(false)
    end
  end

  describe '#assign_waba_user_tasks' do
    let(:waba_id) { 'waba-x' }
    let(:user_id) { 'ACTOR-1' }

    it 'POSTs the exact user + tasks JSON and returns the parsed success body' do
      stub = stub_request(:post, "https://graph.facebook.com/#{api_version}/#{waba_id}/assigned_users")
             .with(query: { user: user_id, tasks: '["MANAGE"]' },
                   headers: { 'Authorization' => "Bearer #{access_token}" })
             .to_return(status: 200, body: { success: true }.to_json, headers: { 'Content-Type' => 'application/json' })
      result = api_client.assign_waba_user_tasks(waba_id, user_id, %w[MANAGE])
      aggregate_failures do
        expect(result['success']).to be(true)
        expect(stub).to have_been_requested
      end
    end

    it 'raises when Meta rejects the assignment (so the capability gate fails closed)' do
      stub_request(:post, "https://graph.facebook.com/#{api_version}/#{waba_id}/assigned_users")
        .with(query: { user: user_id, tasks: '["MANAGE"]' })
        .to_return(status: 400, body: { error: 'not permitted' }.to_json)
      expect { api_client.assign_waba_user_tasks(waba_id, user_id, %w[MANAGE]) }
        .to raise_error(/WABA assigned user task assignment failed/)
    end
  end
end
