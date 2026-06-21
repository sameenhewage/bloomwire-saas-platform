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

  describe '#onboarding_step_summary' do
    let(:profile) { create(:bloomwire_business_profile) }

    it 'reports an empty, safe summary when there are no steps' do
      summary = profile.onboarding_step_summary

      expect(summary.total).to eq(0)
      expect(summary.completed).to eq(0)
      expect(summary.pending).to eq(0)
      expect(summary.current_step).to be_nil
      expect(summary.all_completed).to be(false)
    end

    it 'counts completed/pending and reports the next pending step in order' do
      create(:bloomwire_onboarding_step, bloomwire_business_profile: profile,
                                         step_key: 'business_details', status: 'pending', position: 1)
      create(:bloomwire_onboarding_step, bloomwire_business_profile: profile,
                                         step_key: 'business_profile', status: 'completed', position: 0)
      create(:bloomwire_onboarding_step, bloomwire_business_profile: profile,
                                         step_key: 'setup_review', status: 'pending', position: 2)

      summary = profile.onboarding_step_summary

      expect(summary.total).to eq(3)
      expect(summary.completed).to eq(1)
      expect(summary.pending).to eq(2)
      expect(summary.current_step).to eq('business_details')
      expect(summary.all_completed).to be(false)
    end

    it 'reports all_completed once every step is completed' do
      create(:bloomwire_onboarding_step, bloomwire_business_profile: profile,
                                         step_key: 'business_profile', status: 'completed', position: 0)
      create(:bloomwire_onboarding_step, bloomwire_business_profile: profile,
                                         step_key: 'business_details', status: 'completed', position: 1)

      summary = profile.onboarding_step_summary

      expect(summary.all_completed).to be(true)
      expect(summary.current_step).to be_nil
      expect(summary.pending).to eq(0)
    end
  end

  describe '#onboarding_progress' do
    let(:profile) { create(:bloomwire_business_profile) }

    it 'is a safe label when there are no steps' do
      expect(profile.onboarding_progress).to eq('No onboarding steps yet')
    end

    it 'summarises completed/total and the current step' do
      create(:bloomwire_onboarding_step, bloomwire_business_profile: profile,
                                         step_key: 'business_profile', status: 'completed', position: 0)
      create(:bloomwire_onboarding_step, bloomwire_business_profile: profile,
                                         step_key: 'business_details', status: 'pending', position: 1)

      expect(profile.onboarding_progress).to eq('1 of 2 steps completed · current: Business details')
    end

    it 'announces when all steps are completed' do
      create(:bloomwire_onboarding_step, bloomwire_business_profile: profile,
                                         step_key: 'business_profile', status: 'completed', position: 0)

      expect(profile.onboarding_progress).to eq('1 of 1 steps completed · all done')
    end
  end
end
