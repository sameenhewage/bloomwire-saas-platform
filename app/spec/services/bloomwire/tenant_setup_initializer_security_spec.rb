require 'rails_helper'

# Edge-case & security tests (Independent TDD Workflow — Edge & Security Test Agent)
#
# Red-teams the Phase 3 tenant setup initializer: idempotency, isolation between
# tenants, safe handling of invalid input, the non-negotiable source-of-truth
# rule (no Chatwoot conversation/message/contact data touched), and scope limits
# (no auto-activation, no billing, no channel data).
RSpec.describe Bloomwire::TenantSetupInitializer do
  describe 'idempotency & uniqueness' do
    it 'is idempotent: running twice does not create duplicate profiles' do
      account = create(:account)
      described_class.new(account_id: account.id).perform

      expect { described_class.new(account_id: account.id).perform }
        .not_to change(BloomwireBusinessProfile, :count)
    end

    it 'never creates more than one profile per account' do
      account = create(:account)

      2.times { described_class.new(account_id: account.id).perform }

      expect(BloomwireBusinessProfile.where(account_id: account.id).count).to eq(1)
    end

    it 'leaves onboarding_status at in_progress on a repeat run (no churn)' do
      account = create(:account)
      described_class.new(account_id: account.id).perform
      result = described_class.new(account_id: account.id).perform

      expect(account.reload.bloomwire_business_profile.onboarding_status).to eq('in_progress')
      expect(result.changed).to be(false)
    end
  end

  describe 'invalid input safety' do
    it 'returns a safe failure for a nonexistent account without creating a profile' do
      missing_id = (Account.maximum(:id) || 0) + 100_000

      result = nil
      expect { result = described_class.new(account_id: missing_id).perform }
        .not_to change(BloomwireBusinessProfile, :count)
      expect(result.success).to be(false)
      expect(result.changed).to be(false)
    end
  end

  describe 'tenant isolation' do
    it "does not touch another account's profile" do
      target = create(:account)
      other = create(:account)
      other_profile = create(:bloomwire_business_profile, account: other,
                                                          onboarding_status: 'not_started')

      described_class.new(account_id: target.id).perform

      expect(other_profile.reload.onboarding_status).to eq('not_started')
    end
  end

  describe 'source-of-truth protection (no Chatwoot data touched)' do
    it 'does not change the number of Chatwoot conversations' do
      create(:conversation)
      account = create(:account)

      expect { described_class.new(account_id: account.id).perform }
        .not_to change(Conversation, :count)
    end

    it 'does not change the number of Chatwoot messages' do
      create(:message)
      account = create(:account)

      expect { described_class.new(account_id: account.id).perform }
        .not_to change(Message, :count)
    end

    it 'does not change the number of Chatwoot contacts' do
      create(:contact)
      account = create(:account)

      expect { described_class.new(account_id: account.id).perform }
        .not_to change(Contact, :count)
    end

    it 'does not create any WhatsApp/channel records' do
      account = create(:account)

      expect { described_class.new(account_id: account.id).perform }
        .not_to change(Channel::Whatsapp, :count)
    end
  end

  describe 'scope limits' do
    it 'does not change business profile status to active automatically' do
      account = create(:account)

      described_class.new(account_id: account.id).perform

      expect(account.reload.bloomwire_business_profile.status).to eq('setup_pending')
    end

    it 'does not start billing/plan enforcement (plan_name untouched)' do
      account = create(:account)

      described_class.new(account_id: account.id).perform

      expect(account.reload.bloomwire_business_profile.plan_name).to be_nil
    end
  end

  describe 'safe summary (no sensitive data exposure)' do
    it 'exposes only safe summary fields, never account names or raw identifiers' do
      account = create(:account, name: 'Top Secret Tenant Ltd')

      result = described_class.new(account_id: account.id).perform

      serialized = result.to_h.to_s
      expect(serialized).not_to include('Top Secret Tenant Ltd')
      allowed_keys = %i[success profile_created previous_onboarding_status
                        current_onboarding_status changed error]
      expect(result.to_h.keys - allowed_keys).to be_empty
    end
  end
end
