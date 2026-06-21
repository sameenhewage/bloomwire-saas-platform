require 'rails_helper'

# Acceptance coverage for the Super Admin manual tenant activation gate.
#
# Phase 3 — Business Onboarding / Tenant Setup (final slice: manual activation).
# Activation is backend-enforced: a tenant may only move to `active` when its
# Bloomwire profile exists, its Chatwoot setup is Ready, and all onboarding steps
# are completed. Failures never mutate and return a safe reason code.
RSpec.describe Bloomwire::TenantActivation do
  subject(:result) { described_class.new(profile).activate }

  let(:account) { create(:account) }
  let(:profile) do
    create(:bloomwire_business_profile, account: account,
                                        status: 'setup_pending', onboarding_status: 'in_progress')
  end

  def complete_all_steps(target)
    BloomwireOnboardingStep::DEFAULT_STEPS.each_with_index do |key, index|
      create(:bloomwire_onboarding_step, bloomwire_business_profile: target,
                                         step_key: key, status: 'completed', position: index)
    end
  end

  describe 'when the tenant is ready (Chatwoot Ready + all steps completed)' do
    before do
      create(:inbox, account: account)
      complete_all_steps(profile)
    end

    it 'succeeds with no error' do
      expect(result.success).to be(true)
      expect(result.error).to be_nil
    end

    it 'activates the profile and completes onboarding' do
      result
      expect(profile.reload.status).to eq('active')
      expect(profile.onboarding_status).to eq('completed')
    end

    it 'reports a real change, not an idempotent no-op' do
      expect(result.changed).to be(true)
      expect(result.already_active).to be(false)
    end
  end

  describe 'when Chatwoot readiness is not Ready (no inbox)' do
    before { complete_all_steps(profile) }

    it 'fails with chatwoot_not_ready and does not mutate' do
      expect(result.success).to be(false)
      expect(result.error).to eq(:chatwoot_not_ready)
      expect(profile.reload.status).to eq('setup_pending')
      expect(profile.onboarding_status).to eq('in_progress')
    end
  end

  describe 'when onboarding steps are missing (Chatwoot Ready, no steps)' do
    before { create(:inbox, account: account) }

    it 'fails with onboarding_steps_missing and does not mutate' do
      expect(result.success).to be(false)
      expect(result.error).to eq(:onboarding_steps_missing)
      expect(profile.reload.status).to eq('setup_pending')
    end
  end

  describe 'when onboarding is incomplete (a step is still pending)' do
    before do
      create(:inbox, account: account)
      create(:bloomwire_onboarding_step, bloomwire_business_profile: profile,
                                         step_key: 'business_profile', status: 'completed', position: 0)
      create(:bloomwire_onboarding_step, bloomwire_business_profile: profile,
                                         step_key: 'business_details', status: 'pending', position: 1)
    end

    it 'fails with onboarding_incomplete and does not mutate' do
      expect(result.success).to be(false)
      expect(result.error).to eq(:onboarding_incomplete)
      expect(profile.reload.status).to eq('setup_pending')
    end
  end

  describe 'when the tenant is already active' do
    let(:profile) do
      create(:bloomwire_business_profile, account: account,
                                          status: 'active', onboarding_status: 'completed')
    end

    it 'is idempotent: success, already_active, no change' do
      expect(result.success).to be(true)
      expect(result.already_active).to be(true)
      expect(result.changed).to be(false)
    end

    it 'does not run a duplicate activation transition' do
      expect(profile).not_to receive(:update!)
      result
    end
  end

  describe 'when there is no profile' do
    it 'fails safely with profile_not_found' do
      nil_result = described_class.new(nil).activate
      expect(nil_result.success).to be(false)
      expect(nil_result.error).to eq(:profile_not_found)
    end
  end
end
