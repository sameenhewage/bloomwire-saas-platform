require 'rails_helper'

# Acceptance + edge/security tests (Independent TDD Workflow)
#
# Product truth:
#   Bloomwire needs a single, owned record of WHICH inbox/channel it configured
#   for WHICH tenant, plus the NON-SECRET routing identifiers a future global
#   webhook router will use (ADR 0005).
#   Current system: no such record exists; ownership/routing is implicit in
#   Chatwoot's per-channel config.
#   Done means: an integration row maps profile -> account -> inbox -> channel,
#   stays inside one tenant (cross-tenant rows are rejected, nothing persisted),
#   is unique per inbox, has a unique routing key where present, and never stores
#   provider secrets. Creating it changes no Chatwoot behavior.
RSpec.describe BloomwireChannelIntegration do
  describe 'validations' do
    it 'is valid with tenant-consistent attributes' do
      expect(build(:bloomwire_channel_integration)).to be_valid
    end

    it 'requires a bloomwire_business_profile' do
      expect(build(:bloomwire_channel_integration, bloomwire_business_profile: nil)).not_to be_valid
    end

    it 'requires an account' do
      integration = build(:bloomwire_channel_integration)
      integration.account = nil
      expect(integration).not_to be_valid
      expect(integration.errors[:account]).to be_present
    end

    it 'requires an inbox' do
      expect(build(:bloomwire_channel_integration, inbox: nil)).not_to be_valid
    end

    it 'requires a channelable' do
      expect(build(:bloomwire_channel_integration, channelable: nil)).not_to be_valid
    end

    it 'requires an app_kind' do
      expect(build(:bloomwire_channel_integration, app_kind: nil)).not_to be_valid
    end

    it 'rejects an unknown app_kind' do
      expect(build(:bloomwire_channel_integration, app_kind: 'bogus')).not_to be_valid
    end

    it 'requires a provider' do
      expect(build(:bloomwire_channel_integration, provider: nil)).not_to be_valid
    end

    it 'requires a status' do
      expect(build(:bloomwire_channel_integration, status: nil)).not_to be_valid
    end

    it 'rejects an unknown status' do
      expect(build(:bloomwire_channel_integration, status: 'bogus')).not_to be_valid
    end
  end

  describe 'defaults' do
    it 'defaults status to pending' do
      account = create(:account)
      profile = create(:bloomwire_business_profile, account: account)
      channel = create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', validate_provider_config: false, sync_templates: false)
      integration = described_class.create!(
        bloomwire_business_profile: profile, account: account, inbox: channel.reload.inbox,
        channelable: channel, app_kind: 'whatsapp', provider: channel.provider
      )

      expect(integration.status).to eq('pending')
    end

    it 'defaults managed_by_bloomwire to true' do
      account = create(:account)
      profile = create(:bloomwire_business_profile, account: account)
      channel = create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', validate_provider_config: false, sync_templates: false)
      integration = described_class.create!(
        bloomwire_business_profile: profile, account: account, inbox: channel.reload.inbox,
        channelable: channel, app_kind: 'whatsapp', provider: channel.provider
      )

      expect(integration.managed_by_bloomwire).to be(true)
    end
  end

  describe 'uniqueness' do
    it 'allows only one integration per inbox' do
      existing = create(:bloomwire_channel_integration)
      duplicate = build(:bloomwire_channel_integration,
                        account: existing.account,
                        bloomwire_business_profile: existing.bloomwire_business_profile,
                        whatsapp_channel: existing.channelable)

      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:inbox_id]).to be_present
    end

    it 'enforces a unique routing_key when present' do
      create(:bloomwire_channel_integration, routing_key: 'pid-shared')
      duplicate = build(:bloomwire_channel_integration, routing_key: 'pid-shared')

      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:routing_key]).to be_present
    end

    it 'allows multiple integrations with a nil routing_key' do
      create(:bloomwire_channel_integration, routing_key: nil)
      expect(build(:bloomwire_channel_integration, routing_key: nil)).to be_valid
    end
  end

  describe 'tenant consistency' do
    it 'rejects a profile that belongs to a different account' do
      account_a = create(:account)
      profile_b = create(:bloomwire_business_profile, account: create(:account))
      channel_a = create(:channel_whatsapp, account: account_a, provider: 'whatsapp_cloud', validate_provider_config: false, sync_templates: false)

      integration = build(:bloomwire_channel_integration,
                          account: account_a, bloomwire_business_profile: profile_b, whatsapp_channel: channel_a)

      expect(integration).not_to be_valid
      expect(integration.errors[:bloomwire_business_profile]).to be_present
    end

    it 'rejects an inbox that belongs to a different account' do
      account_a = create(:account)
      profile_a = create(:bloomwire_business_profile, account: account_a)
      channel_b = create(:channel_whatsapp, account: create(:account), validate_provider_config: false, sync_templates: false)

      integration = build(:bloomwire_channel_integration,
                          account: account_a, bloomwire_business_profile: profile_a, whatsapp_channel: channel_b)

      expect(integration).not_to be_valid
      expect(integration.errors[:inbox]).to be_present
    end

    it 'rejects a channelable that is not the linked inbox channel' do
      account_a = create(:account)
      profile_a = create(:bloomwire_business_profile, account: account_a)
      channel_one = create(:channel_whatsapp, account: account_a, provider: 'whatsapp_cloud', validate_provider_config: false, sync_templates: false)
      channel_two = create(:channel_whatsapp, account: account_a, provider: 'whatsapp_cloud', validate_provider_config: false, sync_templates: false)

      integration = build(:bloomwire_channel_integration,
                          account: account_a, bloomwire_business_profile: profile_a, whatsapp_channel: channel_one)
      integration.channelable = channel_two

      expect(integration).not_to be_valid
      expect(integration.errors[:channelable]).to be_present
    end

    it 'does not persist a cross-tenant row' do
      account_a = create(:account)
      profile_b = create(:bloomwire_business_profile, account: create(:account))
      channel_a = create(:channel_whatsapp, account: account_a, provider: 'whatsapp_cloud', validate_provider_config: false, sync_templates: false)

      integration = build(:bloomwire_channel_integration,
                          account: account_a, bloomwire_business_profile: profile_b, whatsapp_channel: channel_a)

      expect(integration.save).to be(false)
      expect(described_class.count).to eq(0)
    end
  end

  describe 'associations' do
    it 'links an optional super admin creator' do
      super_admin = create(:super_admin)
      integration = create(:bloomwire_channel_integration, created_by_super_admin: super_admin)

      expect(integration.created_by_super_admin).to eq(super_admin)
    end

    it 'is reachable from the business profile' do
      integration = create(:bloomwire_channel_integration)
      expect(integration.bloomwire_business_profile.channel_integrations).to include(integration)
    end
  end

  describe 'secrets are not stored here' do
    it 'has no columns for provider secrets or raw provider config' do
      forbidden = %w[api_key access_token token webhook_verify_token provider_config secret credentials]
      expect(described_class.column_names & forbidden).to be_empty
    end
  end

  # 4.4-b-WA.2C destroy gate: only a Bloomwire-managed WhatsApp inbox is gated for
  # destroy (disconnecting a platform-owned app). Non-managed, non-WhatsApp, missing,
  # and nil inputs are NOT gated so plain Chatwoot destroy behavior is unchanged.
  describe '.managed_whatsapp_inbox?' do
    it 'is true for a Bloomwire-managed WhatsApp integration inbox' do
      integration = create(:bloomwire_channel_integration, managed_by_bloomwire: true, app_kind: 'whatsapp')

      expect(described_class.managed_whatsapp_inbox?(integration.inbox)).to be(true)
    end

    it 'is false for a non-managed WhatsApp integration inbox' do
      integration = create(:bloomwire_channel_integration, managed_by_bloomwire: false, app_kind: 'whatsapp')

      expect(described_class.managed_whatsapp_inbox?(integration.inbox)).to be(false)
    end

    it 'is false for a managed non-WhatsApp integration inbox' do
      integration = create(:bloomwire_channel_integration, managed_by_bloomwire: true, app_kind: 'sms')

      expect(described_class.managed_whatsapp_inbox?(integration.inbox)).to be(false)
    end

    it 'is false for an inbox with no integration' do
      expect(described_class.managed_whatsapp_inbox?(create(:inbox))).to be(false)
    end

    it 'is false for a nil inbox' do
      expect(described_class.managed_whatsapp_inbox?(nil)).to be(false)
    end
  end
end
