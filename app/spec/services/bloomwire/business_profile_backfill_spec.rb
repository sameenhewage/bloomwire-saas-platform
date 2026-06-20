require 'rails_helper'

# Acceptance tests (Independent TDD Workflow — Acceptance Test Agent)
#
# Product truth:
#   User expects every Chatwoot business tenant/account to have Bloomwire
#   business profile metadata.
#   Current system supports bloomwire_business_profiles, but existing accounts
#   can miss a profile.
#   Done means missing profiles can be safely backfilled, each account has at
#   most one profile, defaults are correct, repeat runs do not duplicate
#   records, and no Chatwoot conversation/contact/message data is copied.
RSpec.describe Bloomwire::BusinessProfileBackfill do
  subject(:backfill) { described_class.new }

  describe '#perform' do
    it 'creates a BloomwireBusinessProfile for an account that is missing one' do
      account = create(:account)
      expect(account.bloomwire_business_profile).to be_nil

      expect { backfill.perform }.to change(BloomwireBusinessProfile, :count).by(1)

      expect(account.reload.bloomwire_business_profile).to be_present
    end

    it 'does not create a duplicate for an account that already has a profile' do
      profile = create(:bloomwire_business_profile)

      expect { backfill.perform }.not_to change(BloomwireBusinessProfile, :count)
      expect(profile.account.reload.bloomwire_business_profile).to eq(profile)
    end

    it 'creates new profiles with the default status setup_pending' do
      account = create(:account)

      backfill.perform

      expect(account.reload.bloomwire_business_profile.status).to eq('setup_pending')
    end

    it 'creates new profiles with the default onboarding_status not_started' do
      account = create(:account)

      backfill.perform

      expect(account.reload.bloomwire_business_profile.onboarding_status).to eq('not_started')
    end

    it 'ensures every eligible account has exactly one profile after backfill' do
      create_list(:account, 3)
      create(:bloomwire_business_profile) # an account that already has one

      backfill.perform

      accounts_without_profile =
        Account.where.missing(:bloomwire_business_profile).count
      expect(accounts_without_profile).to eq(0)
      # exactly one profile per account, never more
      expect(BloomwireBusinessProfile.group(:account_id).count.values).to all(eq(1))
    end

    it 'returns a summary reporting created, skipped, and total counts' do
      create_list(:account, 2)            # missing profiles -> created
      create(:bloomwire_business_profile) # already has a profile -> skipped

      result = backfill.perform

      expect(result.created).to eq(2)
      expect(result.skipped).to eq(1)
      expect(result.total).to eq(3)
    end
  end
end
