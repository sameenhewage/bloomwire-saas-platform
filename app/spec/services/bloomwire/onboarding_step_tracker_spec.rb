require 'rails_helper'

# Acceptance tests (Independent TDD Workflow — Acceptance Test Agent)
#
# Phase 3 — Business Onboarding / Tenant Setup, slice: "Onboarding Step Tracking".
#
# Product truth:
#   User expects Bloomwire operators to see and track where a tenant is in the
#   onboarding/setup process.
#   Current system can move onboarding_status to in_progress but has no structured
#   step tracking.
#   Done means onboarding steps can be represented, advanced safely, remain
#   tenant/profile scoped, are idempotent where needed, and never copy Chatwoot
#   conversation/contact/message data.
RSpec.describe Bloomwire::OnboardingStepTracker do
  subject(:tracker) { described_class.new(account_id: profile.account_id) }

  let(:profile) { create(:bloomwire_business_profile) }

  describe '#ensure_steps' do
    it 'represents the default onboarding steps for the tenant' do
      result = tracker.ensure_steps

      keys = profile.onboarding_steps.ordered.pluck(:step_key)
      expect(keys).to eq(BloomwireOnboardingStep::DEFAULT_STEPS)
      expect(result.total_steps).to eq(BloomwireOnboardingStep::DEFAULT_STEPS.size)
    end

    it 'creates every default step in the pending state' do
      tracker.ensure_steps

      expect(profile.onboarding_steps.pluck(:status).uniq).to eq(['pending'])
    end

    it 'reports the first step as the current step and nothing completed yet' do
      result = tracker.ensure_steps

      expect(result.completed_steps).to eq(0)
      expect(result.current_step).to eq(BloomwireOnboardingStep::DEFAULT_STEPS.first)
      expect(result.all_completed).to be(false)
    end
  end

  describe '#advance' do
    it 'completes the next pending step and advances the current step' do
      tracker.ensure_steps
      result = tracker.advance

      expect(result.changed).to be(true)
      expect(result.completed_steps).to eq(1)
      expect(result.current_step).to eq(BloomwireOnboardingStep::DEFAULT_STEPS.second)
    end

    it 'ensures the steps exist even if advance is the first call' do
      result = tracker.advance

      expect(result.total_steps).to eq(BloomwireOnboardingStep::DEFAULT_STEPS.size)
      expect(result.completed_steps).to eq(1)
    end

    it 'reaches all_completed after advancing through every step' do
      tracker.ensure_steps

      result = nil
      BloomwireOnboardingStep::DEFAULT_STEPS.size.times { result = tracker.advance }

      expect(result.all_completed).to be(true)
      expect(result.completed_steps).to eq(BloomwireOnboardingStep::DEFAULT_STEPS.size)
      expect(result.current_step).to be_nil
    end

    it 'is idempotent once all steps are completed' do
      tracker.ensure_steps
      (BloomwireOnboardingStep::DEFAULT_STEPS.size + 1).times { tracker.advance }

      final = tracker.advance
      expect(final.changed).to be(false)
      expect(final.all_completed).to be(true)
      expect(final.success).to be(true)
    end
  end

  describe 'result shape' do
    it 'returns a safe summary result' do
      result = tracker.ensure_steps

      expect(result).to respond_to(:total_steps, :completed_steps, :pending_steps,
                                   :current_step, :all_completed, :changed, :success)
      expect(result.success).to be(true)
    end
  end
end
