require 'rails_helper'

RSpec.describe BloomwireBusinessProfile do
  describe 'validations' do
    it 'is valid with valid attributes' do
      expect(build(:bloomwire_business_profile)).to be_valid
    end

    it 'requires an account' do
      expect(build(:bloomwire_business_profile, account: nil)).not_to be_valid
    end

    it 'enforces a unique account_id' do
      existing = create(:bloomwire_business_profile)
      duplicate = build(:bloomwire_business_profile, account: existing.account)
      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:account_id]).to be_present
    end

    it 'rejects an invalid status' do
      expect(build(:bloomwire_business_profile, status: 'bogus')).not_to be_valid
    end

    it 'rejects an invalid onboarding_status' do
      expect(build(:bloomwire_business_profile, onboarding_status: 'bogus')).not_to be_valid
    end
  end

  describe 'scopes' do
    it '.active returns only active profiles' do
      active = create(:bloomwire_business_profile, status: 'active')
      create(:bloomwire_business_profile, status: 'setup_pending')
      expect(described_class.active).to contain_exactly(active)
    end

    it '.setup_pending returns only setup_pending profiles' do
      pending = create(:bloomwire_business_profile, status: 'setup_pending')
      create(:bloomwire_business_profile, status: 'active')
      expect(described_class.setup_pending).to contain_exactly(pending)
    end
  end

  describe 'account association' do
    it 'is reachable from the account' do
      profile = create(:bloomwire_business_profile)
      expect(profile.account.bloomwire_business_profile).to eq(profile)
    end
  end
end
