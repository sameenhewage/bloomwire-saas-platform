require 'rails_helper'

# Platform-context endpoint for Bloomwire Admin external-channel setup
# (4.4-b-WA.2B). The route is generic (app_kind selects the adapter); WhatsApp is
# the first supported kind. Only a signed-in SuperAdmin (Bloomwire platform
# operator) may call it; Dialog tenant admins/agents may NOT. Responses expose a
# safe DTO only — never raw provider_config / API keys / tokens.
RSpec.describe 'SuperAdmin::BloomwireChannelIntegrations', type: :request do
  let(:super_admin) { create(:super_admin) }
  let(:account) { create(:account) }

  let(:valid_payload) do
    {
      account_id: account.id,
      app_kind: 'whatsapp',
      channel: {
        phone_number: '+15551230009',
        phone_number_id: 'pnid-req-009',
        business_account_id: 'waba-req-009',
        api_key: 'super-secret-token',
        business_name: 'Req Co'
      }
    }
  end

  before do
    create(:bloomwire_business_profile, account: account)
    teardown = instance_double(Whatsapp::WebhookTeardownService, perform: nil)
    allow(Whatsapp::WebhookTeardownService).to receive(:new).and_return(teardown)
    setup = instance_double(Whatsapp::WebhookSetupService, perform: nil)
    allow(Whatsapp::WebhookSetupService).to receive(:new).and_return(setup)
    allow(Channel::Whatsapp).to receive(:new).and_wrap_original do |method, *args|
      channel = method.call(*args)
      allow(channel).to receive(:validate_provider_config)
      allow(channel).to receive(:sync_templates)
      channel
    end
    # Confirm the supplied WhatsApp phone metadata against Meta by default (the new
    # pre-activation check queries Whatsapp::FacebookApiClient); failure cases re-stub it.
    phone_lookup = instance_double(Whatsapp::FacebookApiClient)
    allow(Whatsapp::FacebookApiClient).to receive(:new).and_return(phone_lookup)
    allow(phone_lookup).to receive(:fetch_phone_numbers).and_return(
      'data' => [{ 'id' => 'pnid-req-009', 'display_phone_number' => '+15551230009' }]
    )
    # The post-activation readiness gate queries Meta health; default to a registered/ready
    # number so the happy path activates. The readiness-failure examples re-stub it.
    ready = { code_verification_status: 'VERIFIED', platform_type: 'CLOUD_API', throughput: { 'level' => 'STANDARD' } }
    health = instance_double(Whatsapp::HealthService, fetch_health_status: ready)
    allow(Whatsapp::HealthService).to receive(:new).and_return(health)
  end

  def post_setup(payload = valid_payload)
    post '/super_admin/bloomwire/channel_integrations', params: payload, as: :json
  end

  describe 'POST /super_admin/bloomwire/channel_integrations' do
    context 'when signed in as a super admin (platform context)' do
      before { sign_in(super_admin, scope: :super_admin) }

      it 'creates the channel + inbox + integration and returns a minimal safe DTO' do
        expect { post_setup }.to change(BloomwireChannelIntegration, :count).by(1)

        expect(response).to have_http_status(:created)
        body = response.parsed_body
        expect(body['app_kind']).to eq('whatsapp')
        expect(body['provider']).to eq('whatsapp_cloud')
        expect(body['status']).to eq('active')
        expect(body['managed_by_bloomwire']).to be(true)
        expect(body['phone_number_masked']).to be_present
      end

      it 'never exposes raw phone/vendor identifiers or secrets' do
        post_setup

        # secrets + raw phone + Meta vendor identifiers must be absent from the body
        forbidden = ['super-secret-token', 'provider_config', 'api_key', 'token',
                     '+15551230009', '15551230009', 'pnid-req-009', 'waba-req-009']
        forbidden.each { |value| expect(response.body).not_to include(value) }

        %w[phone_number phone_number_id business_account_id routing_key].each do |key|
          expect(response.parsed_body).not_to have_key(key)
        end

        # only a masked phone (last 4) is shared
        expect(response.parsed_body['phone_number_masked']).to include('0009')
      end

      it 'does not return 201/active when provider webhook registration fails' do
        failing = instance_double(Whatsapp::WebhookSetupService)
        allow(Whatsapp::WebhookSetupService).to receive(:new).and_return(failing)
        allow(failing).to receive(:perform).and_raise(RuntimeError, 'Webhook setup failed: Meta down')

        post_setup

        expect(response).not_to have_http_status(:created)
        expect(response.parsed_body['error']).to be_present
        expect(BloomwireChannelIntegration.last.status).to eq('pending')
      end

      it 'does not return 201/active (safe error, pending row, no raw data) when the phone is not registered/ready' do
        # The webhook subscribe SUCCEEDS (default stub) but Meta reports the number unprovisioned —
        # the swallowed-registration gap. Setup must stay pending and must leak no provider data.
        health = instance_double(Whatsapp::HealthService,
                                 fetch_health_status: { code_verification_status: 'VERIFIED', platform_type: 'NOT_APPLICABLE' })
        allow(Whatsapp::HealthService).to receive(:new).and_return(health)

        post_setup

        expect(response).not_to have_http_status(:created)
        expect(response.parsed_body['error']).to be_present
        expect(BloomwireChannelIntegration.last.status).to eq('pending')
        ['super-secret-token', 'provider_config', 'pnid-req-009', 'waba-req-009', '+15551230009']
          .each { |value| expect(response.body).not_to include(value) }
      end

      it 'does not return 201/active when Meta reports throughput.level NOT_APPLICABLE (no messaging capacity)' do
        # Webhook subscribe SUCCEEDS and the number is code-verified on a platform, but it has no
        # assigned throughput, so sends would not work — the integration must stay pending.
        not_ready = { code_verification_status: 'VERIFIED', platform_type: 'CLOUD_API', throughput: { 'level' => 'NOT_APPLICABLE' } }
        health = instance_double(Whatsapp::HealthService, fetch_health_status: not_ready)
        allow(Whatsapp::HealthService).to receive(:new).and_return(health)

        post_setup

        expect(response).not_to have_http_status(:created)
        expect(response.parsed_body['error']).to be_present
        expect(BloomwireChannelIntegration.last.status).to eq('pending')
      end

      it 'returns 422 with a safe error when the tenant has no Bloomwire profile' do
        post_setup(valid_payload.merge(account_id: create(:account).id))

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.parsed_body['error']).to be_present
        expect(response.body).not_to include('super-secret-token')
      end

      it 'returns a safe 422 (never a 500) when channel is not a parameter object' do
        ['not-an-object', %w[a b]].each do |bad_channel|
          post_setup(valid_payload.merge(channel: bad_channel))

          expect(response).to have_http_status(:unprocessable_entity)
          expect(response.parsed_body['error']).to eq('Missing or invalid channel parameters.')
        end
      end

      it 'returns a safe 422 (no raw provider data) and creates nothing when Meta rejects the phone metadata' do
        lookup = instance_double(Whatsapp::FacebookApiClient)
        allow(Whatsapp::FacebookApiClient).to receive(:new).and_return(lookup)
        allow(lookup).to receive(:fetch_phone_numbers).and_return(
          'data' => [{ 'id' => 'a-different-pnid', 'display_phone_number' => '+15550000000' }]
        )

        expect { post_setup }.not_to change(BloomwireChannelIntegration, :count)
        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.parsed_body['error'])
          .to eq('The WhatsApp phone number ID was not found in the supplied WhatsApp Business Account.')

        ['pnid-req-009', 'waba-req-009', 'a-different-pnid', '+15551230009', 'super-secret-token']
          .each { |value| expect(response.body).not_to include(value) }
      end

      it 'stores the canonical +<digits> phone number (so inbound webhooks resolve the channel)' do
        formatted = valid_payload.merge(channel: valid_payload[:channel].merge(phone_number: '+1 (555) 123-0009'))
        lookup = instance_double(Whatsapp::FacebookApiClient)
        allow(Whatsapp::FacebookApiClient).to receive(:new).and_return(lookup)
        allow(lookup).to receive(:fetch_phone_numbers).and_return(
          'data' => [{ 'id' => 'pnid-req-009', 'display_phone_number' => '+1 555-123-0009' }]
        )

        post_setup(formatted)

        expect(response).to have_http_status(:created)
        expect(Channel::Whatsapp.last.phone_number).to eq('+15551230009')
        expect(BloomwireChannelIntegration.last.phone_number).to eq('+15551230009')
        expect(response.body).not_to include('+1 (555) 123-0009')
      end
    end

    context 'when signed in as a Dialog tenant account administrator (not platform)' do
      let(:tenant_admin) { create(:user) }

      before do
        create(:account_user, account: account, user: tenant_admin, role: :administrator)
        sign_in(tenant_admin, scope: :user)
      end

      it 'is not authorized and creates nothing' do
        expect { post_setup }.not_to change(BloomwireChannelIntegration, :count)
        expect(response).not_to have_http_status(:created)
      end
    end

    context 'when signed in as a Dialog agent' do
      let(:agent) { create(:user) }

      before do
        create(:account_user, account: account, user: agent, role: :agent)
        sign_in(agent, scope: :user)
      end

      it 'is not authorized and creates nothing' do
        expect { post_setup }.not_to change(BloomwireChannelIntegration, :count)
        expect(response).not_to have_http_status(:created)
      end
    end

    context 'when not authenticated as a super admin' do
      it 'creates nothing' do
        expect { post_setup }.not_to change(BloomwireChannelIntegration, :count)
      end
    end
  end
end
