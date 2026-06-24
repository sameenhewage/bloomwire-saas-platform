require 'rails_helper'

# Acceptance + edge/security tests (Independent TDD Workflow) for the WhatsApp
# routing resolver foundation (ADR 0004 router, 4.4-b-WA.3).
#
# Product truth:
#   The future Bloomwire Global Meta/WhatsApp webhook router (ADR 0004, Phase 8)
#   must map NON-SECRET Meta identifiers (phone_number_id / WABA / routing_key)
#   to the correct Chatwoot account+inbox WITHOUT touching provider secrets and
#   WITHOUT duplicating Chatwoot conversation data.
#   Current system: BloomwireChannelIntegration stores that routing metadata, but
#   nothing reads it back deterministically.
#   Done means: a resolver returns the single managed WhatsApp integration that
#   matches the supplied identifiers; returns nil when there is no match or the
#   data is ambiguous; never picks arbitrarily; ignores non-WhatsApp / non-managed
#   rows; and never exposes a secret. This is foundation only — NOT the Phase 8
#   webhook endpoint, and it processes no Meta payloads.
RSpec.describe Bloomwire::ChannelIntegrations::WhatsappResolver do
  # Each call creates a fresh tenant (account + profile + WhatsApp channel + inbox)
  # via the factory, then overrides the NON-SECRET routing columns directly so the
  # integration row carries deterministic identifiers (the whatsapp_cloud channel
  # factory otherwise forces phone_number_id = '123456789' for every channel).
  def managed_wa(phone_number_id:, business_account_id: nil, routing_key: nil, **attrs)
    create(:bloomwire_channel_integration,
           phone_number_id: phone_number_id,
           business_account_id: business_account_id || "waba-#{phone_number_id}",
           routing_key: routing_key || "rk-#{phone_number_id}",
           **attrs)
  end

  describe '.resolve by phone_number_id' do
    it 'returns the matching managed WhatsApp integration' do
      target = managed_wa(phone_number_id: 'pid-A')
      managed_wa(phone_number_id: 'pid-B')

      expect(described_class.resolve(phone_number_id: 'pid-A')).to eq(target)
    end

    it 'is deterministic (same input returns the same row)' do
      managed_wa(phone_number_id: 'pid-A')

      first = described_class.resolve(phone_number_id: 'pid-A')
      second = described_class.resolve(phone_number_id: 'pid-A')
      expect(first).to eq(second)
    end
  end

  describe '.resolve by business_account_id + phone_number_id' do
    it 'returns the one number within a WABA that shares the business_account_id' do
      waba = 'waba-shared'
      managed_wa(phone_number_id: 'pid-A', business_account_id: waba)
      target = managed_wa(phone_number_id: 'pid-B', business_account_id: waba)

      expect(described_class.resolve(business_account_id: waba, phone_number_id: 'pid-B')).to eq(target)
    end
  end

  describe '.resolve by routing_key' do
    it 'returns the matching managed WhatsApp integration' do
      target = managed_wa(phone_number_id: 'pid-A', routing_key: 'rk-A')
      managed_wa(phone_number_id: 'pid-B', routing_key: 'rk-B')

      expect(described_class.resolve(routing_key: 'rk-A')).to eq(target)
    end
  end

  describe 'scoping' do
    it 'ignores non-WhatsApp integrations' do
      managed_wa(phone_number_id: 'pid-sms', app_kind: 'sms')

      expect(described_class.resolve(phone_number_id: 'pid-sms')).to be_nil
    end

    it 'ignores non-managed integrations' do
      managed_wa(phone_number_id: 'pid-unmanaged', managed_by_bloomwire: false)

      expect(described_class.resolve(phone_number_id: 'pid-unmanaged')).to be_nil
    end
  end

  describe 'no match' do
    it 'returns nil when nothing matches' do
      managed_wa(phone_number_id: 'pid-A')

      expect(described_class.resolve(phone_number_id: 'pid-missing')).to be_nil
    end

    it 'returns nil when no identifiers are supplied' do
      managed_wa(phone_number_id: 'pid-A')

      expect(described_class.resolve(phone_number_id: nil, routing_key: nil,
                                     business_account_id: nil, provider: nil)).to be_nil
    end
  end

  describe 'ambiguous / duplicate routing data' do
    it 'returns nil when a business_account_id alone matches more than one number' do
      waba = 'waba-ambiguous'
      managed_wa(phone_number_id: 'pid-A', business_account_id: waba)
      managed_wa(phone_number_id: 'pid-B', business_account_id: waba)

      expect(described_class.resolve(business_account_id: waba)).to be_nil
    end
  end

  describe 'tenant safety' do
    it 'does not resolve when identifiers come from two different integrations' do
      managed_wa(phone_number_id: 'pid-A', business_account_id: 'waba-A')
      managed_wa(phone_number_id: 'pid-B', business_account_id: 'waba-B')

      expect(described_class.resolve(phone_number_id: 'pid-A', business_account_id: 'waba-B')).to be_nil
    end
  end

  describe 'secrets are never exposed' do
    it 'returns a row that carries no provider secret, even when the channel stores one' do
      account = create(:account)
      profile = create(:bloomwire_business_profile, account: account)
      channel = create(:channel_whatsapp,
                       account: account,
                       validate_provider_config: false,
                       sync_templates: false,
                       provider_config: {
                         'api_key' => 'SUPER_SECRET_KEY',
                         'webhook_verify_token' => 'SUPER_SECRET_TOKEN',
                         'phone_number_id' => 'pid-secret',
                         'business_account_id' => 'waba-secret'
                       }).reload
      integration = create(:bloomwire_channel_integration,
                           account: account,
                           bloomwire_business_profile: profile,
                           whatsapp_channel: channel,
                           phone_number_id: 'pid-secret',
                           business_account_id: 'waba-secret',
                           routing_key: 'rk-secret')

      resolved = described_class.resolve(phone_number_id: 'pid-secret')
      serialized = resolved.attributes.values.map(&:to_s)

      expect(resolved).to eq(integration)
      expect(serialized).not_to include('SUPER_SECRET_KEY')
      expect(serialized).not_to include('SUPER_SECRET_TOKEN')
      forbidden = %w[api_key access_token token webhook_verify_token provider_config secret credentials]
      expect(BloomwireChannelIntegration.column_names & forbidden).to be_empty
    end
  end

  describe 'read-only (source-of-truth protection)' do
    it 'creates or mutates no records' do
      managed_wa(phone_number_id: 'pid-A')

      expect do
        described_class.resolve(phone_number_id: 'pid-A')
        described_class.resolve(phone_number_id: 'pid-missing')
      end.not_to change(BloomwireChannelIntegration, :count)
    end
  end
end
