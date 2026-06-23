require 'rails_helper'

# Service specs for the GENERIC Bloomwire external-channel setup orchestrator
# (4.4-b-WA.2B). WhatsApp is the first adapter, but the orchestrator is
# channel-agnostic: app_kind/provider are inputs and the adapter is selected by
# app_kind. The platform-context setup path creates a Channel::Whatsapp + Inbox +
# BloomwireChannelIntegration for a tenant, storing only NON-SECRET routing
# metadata on the integration. It is behavior-neutral for Dialog tenants (2C
# deny is a later slice).
RSpec.describe Bloomwire::ChannelSetup::Service do
  let(:super_admin) { create(:super_admin) }
  let(:account) { create(:account) }
  let!(:profile) { create(:bloomwire_business_profile, account: account) }

  let(:whatsapp_params) do
    {
      phone_number: '+15551230001',
      phone_number_id: 'pnid-2b-001',
      business_account_id: 'waba-2b-001',
      api_key: 'super-secret-token',
      business_name: 'Acme Co'
    }
  end

  # Stub only the external WhatsApp HTTP boundary (provider validation, template
  # sync, webhook services) so the real Whatsapp::ChannelCreationService + model
  # wiring run without network. Mirrors spec/services/whatsapp/channel_creation_service_spec.
  before do
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

  def perform_setup(actor: super_admin, target: account, app_kind: 'whatsapp', params: whatsapp_params)
    described_class.new(actor: actor, account: target, app_kind: app_kind, params: params).perform
  end

  describe 'successful WhatsApp setup (happy path)' do
    it 'creates exactly one channel, one inbox and one integration' do
      expect { perform_setup }
        .to change(Channel::Whatsapp, :count).by(1)
        .and change(Inbox, :count).by(1)
        .and change(BloomwireChannelIntegration, :count).by(1)
    end

    it 'returns a successful result carrying the integration' do
      result = perform_setup
      expect(result.success?).to be(true)
      expect(result.integration).to be_a(BloomwireChannelIntegration)
    end

    it 'links the integration to the tenant profile, account, inbox and channel' do
      integration = perform_setup.integration
      channel = Channel::Whatsapp.last
      expect(integration.bloomwire_business_profile).to eq(profile)
      expect(integration.account).to eq(account)
      expect(integration.inbox).to eq(channel.inbox)
      expect(integration.channelable).to eq(channel)
    end

    it 'records the acting super admin as the creator' do
      expect(perform_setup.integration.created_by_super_admin).to eq(super_admin)
    end
  end

  describe 'provider webhook registration (embedded_signup skips the model auto-setup)' do
    let(:webhook_setup) { instance_double(Whatsapp::WebhookSetupService, perform: nil) }

    before { allow(Whatsapp::WebhookSetupService).to receive(:new).and_return(webhook_setup) }

    it 'registers the WhatsApp webhook for the created channel after the setup commits' do
      perform_setup

      expect(Whatsapp::WebhookSetupService)
        .to have_received(:new).with(kind_of(Channel::Whatsapp), 'waba-2b-001', 'super-secret-token')
      expect(webhook_setup).to have_received(:perform)
    end
  end

  describe 'provider webhook failure (must not report success/active)' do
    before do
      failing = instance_double(Whatsapp::WebhookSetupService)
      allow(Whatsapp::WebhookSetupService).to receive(:new).and_return(failing)
      allow(failing).to receive(:perform).and_raise(RuntimeError, 'Webhook setup failed: Meta unavailable')
    end

    it 'returns :webhook_setup_failed and leaves the integration pending (not active)' do
      result = perform_setup

      expect(result.success?).to be(false)
      expect(result.error).to eq(:webhook_setup_failed)
      expect(BloomwireChannelIntegration.last.status).to eq('pending')
    end

    it 'still creates the channel + inbox + pending integration so a retry can resume' do
      expect { perform_setup }
        .to change(Channel::Whatsapp, :count).by(1)
        .and change(Inbox, :count).by(1)
        .and change(BloomwireChannelIntegration, :count).by(1)
    end
  end

  describe 'retry after a failed webhook (resume pending, never duplicate)' do
    it 'resumes the SAME pending integration and activates it without creating duplicate rows' do
      failing = instance_double(Whatsapp::WebhookSetupService)
      allow(Whatsapp::WebhookSetupService).to receive(:new).and_return(failing)
      allow(failing).to receive(:perform).and_raise(RuntimeError, 'Meta down')
      expect(perform_setup.error).to eq(:webhook_setup_failed)
      pending = BloomwireChannelIntegration.last
      expect(pending.status).to eq('pending')

      ok = instance_double(Whatsapp::WebhookSetupService, perform: nil)
      allow(Whatsapp::WebhookSetupService).to receive(:new).and_return(ok)

      before_counts = [Channel::Whatsapp.count, Inbox.count, BloomwireChannelIntegration.count]
      result = perform_setup

      expect([Channel::Whatsapp.count, Inbox.count, BloomwireChannelIntegration.count]).to eq(before_counts)
      expect(result.success?).to be(true)
      expect(result.integration.id).to eq(pending.id)
      expect(result.integration.reload.status).to eq('active')
    end
  end

  describe 'integration fields (decided lifecycle + non-secret routing metadata)' do
    let(:integration) { perform_setup.integration }

    it 'marks the integration managed_by_bloomwire and active' do
      expect(integration.managed_by_bloomwire).to be(true)
      expect(integration.status).to eq('active')
    end

    it 'stores generic app_kind/provider supplied by the adapter' do
      expect(integration.app_kind).to eq('whatsapp')
      expect(integration.provider).to eq('whatsapp_cloud')
    end

    it 'stores non-secret routing metadata with routing_key = phone_number_id' do
      expect(integration.phone_number).to eq('+15551230001')
      expect(integration.phone_number_id).to eq('pnid-2b-001')
      expect(integration.business_account_id).to eq('waba-2b-001')
      expect(integration.routing_key).to eq('pnid-2b-001')
    end
  end

  describe 'secret isolation' do
    it 'keeps WhatsApp credentials on the channel provider_config only' do
      integration = perform_setup.integration
      expect(integration.channelable.provider_config['api_key']).to eq('super-secret-token')
      serialized = integration.attributes.values.map(&:to_s)
      expect(serialized).not_to include('super-secret-token')
    end

    it 'has no secret columns on the integration table' do
      forbidden = %w[api_key access_token token webhook_verify_token provider_config secret credentials]
      expect(BloomwireChannelIntegration.column_names & forbidden).to be_empty
    end
  end

  describe 'authorization (platform context only)' do
    it 'rejects a non-super-admin actor without creating anything' do
      tenant_admin = create(:user)
      result = nil
      expect { result = perform_setup(actor: tenant_admin) }.not_to change(Channel::Whatsapp, :count)
      expect(result.success?).to be(false)
      expect(result.error).to eq(:unauthorized)
    end

    it 'rejects a nil actor' do
      expect(perform_setup(actor: nil).error).to eq(:unauthorized)
    end
  end

  describe 'tenant / profile safety' do
    it 'rejects setup for an account without a Bloomwire profile' do
      result = perform_setup(target: create(:account))
      expect(result.error).to eq(:profile_not_found)
      expect(BloomwireChannelIntegration.count).to eq(0)
    end
  end

  describe 'duplicate safety' do
    it 'rejects a duplicate routing_key (phone_number_id) without creating a channel' do
      create(:bloomwire_channel_integration, routing_key: 'pnid-2b-001')
      result = nil
      expect { result = perform_setup }.not_to change(Channel::Whatsapp, :count)
      expect(result.error).to eq(:duplicate_routing_key)
    end

    it 'rejects a duplicate phone number safely' do
      create(:channel_whatsapp, account: create(:account), phone_number: '+15551230001',
                                provider: 'whatsapp_cloud', validate_provider_config: false, sync_templates: false)
      result = perform_setup
      expect(result.success?).to be(false)
      expect(result.error).to eq(:duplicate_phone_number)
    end
  end

  describe 'unsupported channel kind' do
    it 'fails cleanly for an app_kind that has no adapter yet' do
      result = perform_setup(app_kind: 'sms')
      expect(result.success?).to be(false)
      expect(result.error).to eq(:unsupported_app_kind)
    end
  end

  describe 'transactional integrity' do
    it 'rolls back the channel and inbox if integration persistence fails' do
      allow(BloomwireChannelIntegration).to receive(:create!)
        .and_raise(ActiveRecord::RecordInvalid.new(BloomwireChannelIntegration.new))
      before_counts = [Channel::Whatsapp.count, Inbox.count]

      result = perform_setup

      expect(result.success?).to be(false)
      expect([Channel::Whatsapp.count, Inbox.count]).to eq(before_counts)
    end
  end

  describe 'source-of-truth protection (no Chatwoot data mutated)' do
    it 'does not change Chatwoot conversation, message or contact counts' do
      create(:conversation)
      create(:message)
      create(:contact)
      counts = [Conversation.count, Message.count, Contact.count]

      perform_setup

      expect([Conversation.count, Message.count, Contact.count]).to eq(counts)
    end
  end
end
