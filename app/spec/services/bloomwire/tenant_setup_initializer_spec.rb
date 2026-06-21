require 'rails_helper'

# Acceptance tests (Independent TDD Workflow — Acceptance Test Agent)
#
# Phase 3 — Business Onboarding / Tenant Setup, first slice:
# "Bloomwire Tenant Setup Foundation".
#
# Product truth:
#   User expects Bloomwire operators to start preparing a business tenant for
#   onboarding after the business profile exists.
#   Current system has profiles with onboarding_status but no safe setup
#   initializer that moves a tenant from not_started to in_progress.
#   Done means a platform-safe service initializes tenant setup for one
#   account/profile, ensures the profile exists, moves onboarding_status to
#   in_progress when appropriate, stays idempotent, never downgrades a completed
#   tenant, and never copies Chatwoot conversation/contact/message data.
RSpec.describe Bloomwire::TenantSetupInitializer do
  subject(:initializer) { described_class.new(account_id: account.id) }

  describe '#perform' do
    context 'when the account already has a profile with onboarding_status not_started' do
      let(:account) { create(:account) }
      let!(:profile) do
        create(:bloomwire_business_profile, account: account,
                                            status: 'setup_pending',
                                            onboarding_status: 'not_started')
      end

      it 'initializes setup without creating a new profile' do
        expect { initializer.perform }.not_to change(BloomwireBusinessProfile, :count)
      end

      it 'moves onboarding_status from not_started to in_progress' do
        result = initializer.perform

        expect(profile.reload.onboarding_status).to eq('in_progress')
        expect(result.previous_onboarding_status).to eq('not_started')
        expect(result.current_onboarding_status).to eq('in_progress')
        expect(result.changed).to be(true)
      end
    end

    context 'when onboarding_status is already in_progress' do
      let(:account) { create(:account) }
      let!(:profile) do
        create(:bloomwire_business_profile, account: account, onboarding_status: 'in_progress')
      end

      it 'keeps onboarding_status as in_progress and reports no change' do
        result = initializer.perform

        expect(profile.reload.onboarding_status).to eq('in_progress')
        expect(result.changed).to be(false)
        expect(result.current_onboarding_status).to eq('in_progress')
      end
    end

    context 'when onboarding_status is completed' do
      let(:account) { create(:account) }
      let!(:profile) do
        create(:bloomwire_business_profile, account: account,
                                            status: 'active',
                                            onboarding_status: 'completed')
      end

      it 'does not downgrade completed to in_progress' do
        result = initializer.perform

        expect(profile.reload.onboarding_status).to eq('completed')
        expect(result.changed).to be(false)
        expect(result.current_onboarding_status).to eq('completed')
      end
    end

    context 'when the account has no profile yet' do
      let(:account) { create(:account) }

      it 'creates/ensures exactly one profile' do
        expect(account.bloomwire_business_profile).to be_nil

        expect { initializer.perform }.to change(BloomwireBusinessProfile, :count).by(1)
        expect(account.reload.bloomwire_business_profile).to be_present
      end

      it 'creates the profile with safe Phase 2 defaults then moves it to in_progress' do
        result = initializer.perform
        profile = account.reload.bloomwire_business_profile

        expect(profile.status).to eq('setup_pending')
        expect(result.profile_created).to be(true)
        expect(result.current_onboarding_status).to eq('in_progress')
      end
    end

    context 'when reporting the result' do
      let(:account) { create(:account) }

      it 'returns a safe summary result' do
        result = initializer.perform

        expect(result).to respond_to(:profile_created, :previous_onboarding_status,
                                     :current_onboarding_status, :changed)
        expect(result.to_h.keys).to include(:profile_created, :previous_onboarding_status,
                                            :current_onboarding_status, :changed)
      end
    end
  end
end
