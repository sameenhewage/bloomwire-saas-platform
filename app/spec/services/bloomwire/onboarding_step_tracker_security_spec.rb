require 'rails_helper'

# Edge-case & security tests (Independent TDD Workflow — Edge & Security Test Agent)
#
# Red-teams the onboarding step tracker: idempotency, uniqueness, tenant
# isolation, safe handling of invalid input, the non-negotiable source-of-truth
# rule (no Chatwoot conversation/message/contact data touched), and scope limits
# (no profile lifecycle change, no billing, no channel data).
RSpec.describe Bloomwire::OnboardingStepTracker do
  describe 'idempotency & uniqueness' do
    it 'is idempotent: ensure_steps twice does not create duplicate steps' do
      profile = create(:bloomwire_business_profile)
      described_class.new(account_id: profile.account_id).ensure_steps

      expect { described_class.new(account_id: profile.account_id).ensure_steps }
        .not_to change(BloomwireOnboardingStep, :count)
    end

    it 'never creates more than the default number of steps per profile' do
      profile = create(:bloomwire_business_profile)

      3.times { described_class.new(account_id: profile.account_id).ensure_steps }

      expect(profile.onboarding_steps.count).to eq(BloomwireOnboardingStep::DEFAULT_STEPS.size)
    end

    it 'enforces a unique step_key per profile at the database level' do
      profile = create(:bloomwire_business_profile)
      profile.onboarding_steps.create!(step_key: 'business_profile', position: 0)

      expect { profile.onboarding_steps.create!(step_key: 'business_profile', position: 1) }
        .to raise_error(ActiveRecord::RecordInvalid)
    end
  end

  describe 'invalid input safety' do
    it 'returns a safe failure for a nonexistent account without creating steps' do
      missing_id = (Account.maximum(:id) || 0) + 100_000

      result = nil
      expect { result = described_class.new(account_id: missing_id).ensure_steps }
        .not_to change(BloomwireOnboardingStep, :count)
      expect(result.success).to be(false)
      expect(result.error).to eq(:account_not_found)
    end

    it 'returns a safe failure when the account has no profile, without creating a profile' do
      account = create(:account)

      result = nil
      expect { result = described_class.new(account_id: account.id).ensure_steps }
        .not_to change(BloomwireBusinessProfile, :count)
      expect(result.success).to be(false)
      expect(result.error).to eq(:profile_not_found)
    end
  end

  describe 'tenant isolation' do
    it "does not touch another tenant's steps when advancing" do
      target = create(:bloomwire_business_profile)
      other = create(:bloomwire_business_profile)
      described_class.new(account_id: other.account_id).ensure_steps

      described_class.new(account_id: target.account_id).advance

      expect(other.onboarding_steps.where(status: 'completed').count).to eq(0)
    end
  end

  describe 'source-of-truth protection (no Chatwoot data touched)' do
    let(:profile) { create(:bloomwire_business_profile) }

    it 'does not change the number of Chatwoot conversations' do
      create(:conversation)
      expect { described_class.new(account_id: profile.account_id).advance }
        .not_to change(Conversation, :count)
    end

    it 'does not change the number of Chatwoot messages' do
      create(:message)
      expect { described_class.new(account_id: profile.account_id).advance }
        .not_to change(Message, :count)
    end

    it 'does not change the number of Chatwoot contacts' do
      create(:contact)
      expect { described_class.new(account_id: profile.account_id).advance }
        .not_to change(Contact, :count)
    end

    it 'does not create any WhatsApp/channel records' do
      expect { described_class.new(account_id: profile.account_id).advance }
        .not_to change(Channel::Whatsapp, :count)
    end
  end

  describe 'scope limits' do
    it 'does not change the business profile onboarding_status' do
      profile = create(:bloomwire_business_profile, onboarding_status: 'in_progress')

      described_class.new(account_id: profile.account_id).advance

      expect(profile.reload.onboarding_status).to eq('in_progress')
    end

    it 'does not change the business profile status (no auto-activation)' do
      profile = create(:bloomwire_business_profile, status: 'setup_pending')

      described_class.new(account_id: profile.account_id).advance

      expect(profile.reload.status).to eq('setup_pending')
    end

    it 'does not start billing/plan enforcement (plan_name untouched)' do
      profile = create(:bloomwire_business_profile, plan_name: nil)

      described_class.new(account_id: profile.account_id).advance

      expect(profile.reload.plan_name).to be_nil
    end
  end

  describe 'safe summary (no sensitive data exposure)' do
    it 'exposes only safe summary fields, never account names or raw identifiers' do
      profile = create(:bloomwire_business_profile)
      account = profile.account
      account.update!(name: 'Top Secret Tenant Ltd')

      result = described_class.new(account_id: account.id).ensure_steps

      serialized = result.to_h.to_s
      expect(serialized).not_to include('Top Secret Tenant Ltd')
      allowed_keys = %i[success total_steps completed_steps pending_steps
                        current_step all_completed changed error]
      expect(result.to_h.keys - allowed_keys).to be_empty
    end
  end
end
