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

      it 'returns 422 with a safe error when the tenant has no Bloomwire profile' do
        post_setup(valid_payload.merge(account_id: create(:account).id))

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.parsed_body['error']).to be_present
        expect(response.body).not_to include('super-secret-token')
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
