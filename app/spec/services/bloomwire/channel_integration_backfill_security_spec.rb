require 'rails_helper'

# Edge-case & security tests (Independent TDD Workflow — Edge & Security Test Agent)
#
# Red-teams the backfill: secrets must never be copied into the ownership table,
# routing must never be ambiguous across tenants, and Chatwoot conversation /
# message / contact data is NEVER copied or mutated.
RSpec.describe Bloomwire::ChannelIntegrationBackfill do
  subject(:backfill) { described_class.new }

  def create_whatsapp_inbox(account:, phone_number_id:, business_account_id: 'waba-001')
    create(:channel_whatsapp,
           account: account,
           validate_provider_config: false,
           sync_templates: false,
           provider_config: {
             'api_key' => 'super_secret_key',
             'webhook_verify_token' => 'super_secret_verify_token',
             'phone_number_id' => phone_number_id,
             'business_account_id' => business_account_id
           }).reload
  end

  describe 'no secrets are copied' do
    it 'does not persist provider credentials onto the integration' do
      account = create(:account)
      create(:bloomwire_business_profile, account: account)
      create_whatsapp_inbox(account: account, phone_number_id: 'pid-200')

      backfill.perform
      serialized = BloomwireChannelIntegration.last.attributes.values.map(&:to_s)

      expect(serialized).not_to include('super_secret_key')
      expect(serialized).not_to include('super_secret_verify_token')
    end

    it 'stores no secret columns on the integration table' do
      forbidden = %w[api_key access_token token webhook_verify_token provider_config secret credentials]
      expect(BloomwireChannelIntegration.column_names & forbidden).to be_empty
    end
  end

  describe 'routing ambiguity is prevented' do
    it 'never creates two managed integrations sharing the same routing key' do
      account_one = create(:account)
      create(:bloomwire_business_profile, account: account_one)
      create_whatsapp_inbox(account: account_one, phone_number_id: 'dup-pid')

      account_two = create(:account)
      create(:bloomwire_business_profile, account: account_two)
      create_whatsapp_inbox(account: account_two, phone_number_id: 'dup-pid')

      expect { backfill.perform }.to change(BloomwireChannelIntegration, :count).by(1)
      expect(BloomwireChannelIntegration.where(routing_key: 'dup-pid').count).to eq(1)
    end

    it 'does not raise when a routing-key collision is encountered (fails safe)' do
      account_one = create(:account)
      create(:bloomwire_business_profile, account: account_one)
      create_whatsapp_inbox(account: account_one, phone_number_id: 'dup-pid-2')

      account_two = create(:account)
      create(:bloomwire_business_profile, account: account_two)
      create_whatsapp_inbox(account: account_two, phone_number_id: 'dup-pid-2')

      expect { backfill.perform }.not_to raise_error
    end
  end

  describe 'concurrent creation races (TOCTOU between the existence check and save)' do
    it 'does not raise if a concurrent insert makes the row invalid before save (RecordInvalid)' do
      account = create(:account)
      create(:bloomwire_business_profile, account: account)
      create_whatsapp_inbox(account: account, phone_number_id: 'pid-race-invalid')

      racy = instance_double(BloomwireChannelIntegration)
      allow(racy).to receive(:save).and_raise(ActiveRecord::RecordInvalid.new(BloomwireChannelIntegration.new))
      allow(BloomwireChannelIntegration).to receive(:new).and_return(racy)

      expect { backfill.perform }.not_to raise_error
      expect(BloomwireChannelIntegration.count).to eq(0)
    end

    it 'does not raise if the database rejects a duplicate before save (RecordNotUnique)' do
      account = create(:account)
      create(:bloomwire_business_profile, account: account)
      create_whatsapp_inbox(account: account, phone_number_id: 'pid-race-unique')

      racy = instance_double(BloomwireChannelIntegration)
      allow(racy).to receive(:save).and_raise(ActiveRecord::RecordNotUnique.new('duplicate key'))
      allow(BloomwireChannelIntegration).to receive(:new).and_return(racy)

      expect { backfill.perform }.not_to raise_error
      expect(BloomwireChannelIntegration.count).to eq(0)
    end
  end

  describe 'behavior-neutral inbox deletion (pre-2C deny slice)' do
    # 2A must not block the existing inbox-delete workflow: both the sync path and
    # the async DeleteObjectJob ultimately call inbox.destroy!. The FK uses
    # ON DELETE CASCADE, so deleting an inbox removes its ownership metadata
    # instead of raising an FK error. Denying deletion of managed inboxes is 2C.
    it 'is removed when its inbox is destroyed, without raising an FK error' do
      integration = create(:bloomwire_channel_integration)
      inbox = integration.inbox

      # Channel teardown calls an external webhook service; stub it so the spec
      # exercises only the inbox-destroy / FK-cascade behavior.
      allow(Whatsapp::WebhookTeardownService).to receive(:new).and_return(instance_double(Whatsapp::WebhookTeardownService, perform: true))

      expect { inbox.destroy! }.not_to raise_error
      expect(BloomwireChannelIntegration.exists?(integration.id)).to be(false)
    end
  end

  describe 'source-of-truth protection (no Chatwoot data copied)' do
    it 'does not change Chatwoot conversation, message or contact counts' do
      account = create(:account)
      create(:bloomwire_business_profile, account: account)
      create_whatsapp_inbox(account: account, phone_number_id: 'pid-300')
      create(:conversation)
      create(:message)
      create(:contact)

      conversation_count = Conversation.count
      message_count = Message.count
      contact_count = Contact.count

      backfill.perform

      expect(Conversation.count).to eq(conversation_count)
      expect(Message.count).to eq(message_count)
      expect(Contact.count).to eq(contact_count)
    end
  end

  describe 'tenant safety' do
    it 'creates an integration only for accounts that own a Bloomwire profile' do
      account_without_profile = create(:account)
      create_whatsapp_inbox(account: account_without_profile, phone_number_id: 'pid-301')

      backfill.perform

      expect(BloomwireChannelIntegration.count).to eq(0)
    end

    it 'keeps every integration within a single tenant' do
      account = create(:account)
      create(:bloomwire_business_profile, account: account)
      create_whatsapp_inbox(account: account, phone_number_id: 'pid-302')

      backfill.perform
      integration = BloomwireChannelIntegration.last

      expect(integration.account_id).to eq(account.id)
      expect(integration.bloomwire_business_profile.account_id).to eq(account.id)
      expect(integration.inbox.account_id).to eq(account.id)
      expect(integration.channelable.account_id).to eq(account.id)
    end
  end
end
