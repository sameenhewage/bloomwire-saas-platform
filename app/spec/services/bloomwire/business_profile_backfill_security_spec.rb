require 'rails_helper'

# Edge-case & security tests (Independent TDD Workflow — Edge & Security Test Agent)
#
# Red-teams the backfill: idempotency, uniqueness, safe skipping, and the
# non-negotiable source-of-truth rule that Chatwoot conversation/message/contact
# data is NEVER copied or exposed by Bloomwire.
RSpec.describe Bloomwire::BusinessProfileBackfill do
  subject(:backfill) { described_class.new }

  describe 'idempotency & uniqueness' do
    it 'is idempotent: running twice does not create duplicate profiles' do
      create_list(:account, 3)

      backfill.perform
      expect { backfill.perform }.not_to change(BloomwireBusinessProfile, :count)
    end

    it 'reports zero created and only skips on a second run' do
      create_list(:account, 2)

      backfill.perform
      result = backfill.perform

      expect(result.created).to eq(0)
      expect(result.skipped).to eq(2)
      expect(result.total).to eq(2)
    end

    it 'never produces more than one profile per account_id' do
      create_list(:account, 4)

      backfill.perform
      backfill.perform

      duplicates = BloomwireBusinessProfile.group(:account_id).having('COUNT(*) > 1').count
      expect(duplicates).to be_empty
    end

    it 'leaves an existing profile completely untouched (safe skip)' do
      profile = create(:bloomwire_business_profile,
                       status: 'active',
                       onboarding_status: 'completed',
                       industry: 'Retail / E-commerce',
                       plan_name: 'Pro')
      original_attributes = profile.attributes

      backfill.perform

      expect(profile.reload.attributes).to eq(original_attributes)
    end
  end

  describe 'source-of-truth protection (no Chatwoot data copied)' do
    it 'does not change the number of Chatwoot conversations' do
      create(:conversation)
      create(:account)

      expect { backfill.perform }.not_to change(Conversation, :count)
    end

    it 'does not change the number of Chatwoot messages' do
      create(:message)
      create(:account)

      expect { backfill.perform }.not_to change(Message, :count)
    end

    it 'does not change the number of Chatwoot contacts' do
      create(:contact)
      create(:account)

      expect { backfill.perform }.not_to change(Contact, :count)
    end

    it 'stores no conversation/message/contact content columns on the profile table' do
      forbidden = %w[conversation_id message_id contact_id phone_number phone
                     conversations messages contacts content body transcript]
      overlap = BloomwireBusinessProfile.column_names & forbidden
      expect(overlap).to be_empty
    end
  end

  describe 'safe summary (no sensitive data exposure)' do
    it 'exposes only numeric counts, never account names or raw identifiers' do
      account = create(:account, name: 'Top Secret Tenant Ltd')

      result = backfill.perform

      serialized = result.respond_to?(:to_h) ? result.to_h.to_s : result.inspect
      expect(serialized).not_to include('Top Secret Tenant Ltd')
      expect(serialized).not_to include(account.id.to_s) if account.id.to_s.length > 3
      expect(result.to_h.values).to all(be_a(Integer)) if result.respond_to?(:to_h)
    end
  end

  describe 'orphan / invalid account safety' do
    it 'creates a profile only for real, persisted accounts (no orphans)' do
      create_list(:account, 2)

      backfill.perform

      expect(BloomwireBusinessProfile.where.missing(:account)).to be_empty
      expect(BloomwireBusinessProfile.count).to eq(Account.count)
    end

    it 'does not create a profile for an account that was destroyed before the run' do
      account = create(:account)
      account_id = account.id
      account.destroy!

      backfill.perform

      expect(BloomwireBusinessProfile.where(account_id: account_id)).to be_empty
    end
  end
end
