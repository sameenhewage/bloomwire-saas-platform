require 'rails_helper'

# Acceptance tests (Independent TDD Workflow — Acceptance Test Agent)
#
# Product truth:
#   User expects every existing, Bloomwire-tenant WhatsApp inbox to be represented
#   by a Bloomwire-owned channel integration (ownership + non-secret routing
#   metadata), without changing any Chatwoot behavior.
#   Current system: WhatsApp inboxes exist, but Bloomwire has no ownership record.
#   Done means: a backfill creates exactly one integration per eligible WhatsApp
#   inbox, copies only non-secret routing metadata, is idempotent, skips accounts
#   without a Bloomwire profile and non-WhatsApp channels, and reports counts.
RSpec.describe Bloomwire::ChannelIntegrationBackfill do
  subject(:backfill) { described_class.new }

  # provider 'default' avoids the channel_whatsapp factory's whatsapp_cloud
  # config-merge so each inbox can carry a distinct phone_number_id.
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

  describe '#perform' do
    it 'creates one integration for an existing WhatsApp inbox in a tenant with a profile' do
      account = create(:account)
      create(:bloomwire_business_profile, account: account)
      create_whatsapp_inbox(account: account, phone_number_id: 'pid-100')

      expect { backfill.perform }.to change(BloomwireChannelIntegration, :count).by(1)
    end

    it 'maps the integration to the profile, account, inbox and channel' do
      account = create(:account)
      profile = create(:bloomwire_business_profile, account: account)
      channel = create_whatsapp_inbox(account: account, phone_number_id: 'pid-101')

      backfill.perform
      integration = BloomwireChannelIntegration.last

      expect(integration.bloomwire_business_profile).to eq(profile)
      expect(integration.account).to eq(account)
      expect(integration.inbox).to eq(channel.inbox)
      expect(integration.channelable).to eq(channel)
      expect(integration.app_kind).to eq('whatsapp')
      expect(integration.provider).to eq(channel.provider)
    end

    it 'copies only non-secret routing metadata' do
      account = create(:account)
      create(:bloomwire_business_profile, account: account)
      channel = create_whatsapp_inbox(account: account, phone_number_id: 'pid-102', business_account_id: 'waba-102')

      backfill.perform
      integration = BloomwireChannelIntegration.last

      expect(integration.phone_number).to eq(channel.phone_number)
      expect(integration.phone_number_id).to eq('pid-102')
      expect(integration.business_account_id).to eq('waba-102')
      expect(integration.routing_key).to eq('pid-102')
    end

    it 'marks backfilled integrations as Bloomwire-managed' do
      account = create(:account)
      create(:bloomwire_business_profile, account: account)
      create_whatsapp_inbox(account: account, phone_number_id: 'pid-103')

      backfill.perform

      expect(BloomwireChannelIntegration.last.managed_by_bloomwire).to be(true)
    end

    it 'skips a WhatsApp inbox whose account has no Bloomwire profile' do
      account = create(:account)
      create_whatsapp_inbox(account: account, phone_number_id: 'pid-104')

      expect { backfill.perform }.not_to change(BloomwireChannelIntegration, :count)
    end

    it 'ignores non-WhatsApp channels' do
      account = create(:account)
      create(:bloomwire_business_profile, account: account)
      create(:inbox, account: account) # website widget inbox

      expect { backfill.perform }.not_to change(BloomwireChannelIntegration, :count)
    end

    it 'is idempotent: running twice does not create duplicates' do
      account = create(:account)
      create(:bloomwire_business_profile, account: account)
      create_whatsapp_inbox(account: account, phone_number_id: 'pid-105')

      backfill.perform
      expect { backfill.perform }.not_to change(BloomwireChannelIntegration, :count)
    end

    it 'returns a summary reporting created, skipped and total counts' do
      account_with_profile = create(:account)
      create(:bloomwire_business_profile, account: account_with_profile)
      create_whatsapp_inbox(account: account_with_profile, phone_number_id: 'pid-106')

      account_without_profile = create(:account)
      create_whatsapp_inbox(account: account_without_profile, phone_number_id: 'pid-107')

      result = backfill.perform

      expect(result.created).to eq(1)
      expect(result.skipped).to eq(1)
      expect(result.total).to eq(2)
    end
  end
end
