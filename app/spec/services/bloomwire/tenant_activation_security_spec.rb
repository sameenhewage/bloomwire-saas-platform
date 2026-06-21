require 'rails_helper'

# Edge & security coverage for the Super Admin manual tenant activation gate.
#
# Guarantees (see AGENTS.md rules 1, 3, 4, 6, 8 and this slice's Product Truth Gate):
# - Activation is strictly tenant-scoped: only the target profile changes.
# - A failed activation mutates nothing.
# - Activation never creates/modifies Chatwoot inbox/channel/conversation/contact/
#   message records (it is a control-plane status change only).
# - Failure reasons are safe, non-identifying symbol codes (no raw data).
RSpec.describe Bloomwire::TenantActivation do
  let(:account) { create(:account) }

  def make_ready(profile)
    create(:inbox, account: profile.account)
    BloomwireOnboardingStep::DEFAULT_STEPS.each_with_index do |key, index|
      create(:bloomwire_onboarding_step, bloomwire_business_profile: profile,
                                         step_key: key, status: 'completed', position: index)
    end
  end

  describe 'tenant isolation' do
    it 'activates only the target profile and leaves other tenants untouched' do
      target = create(:bloomwire_business_profile, account: account,
                                                   status: 'setup_pending', onboarding_status: 'in_progress')
      other = create(:bloomwire_business_profile, account: create(:account),
                                                  status: 'setup_pending', onboarding_status: 'in_progress')
      make_ready(target)
      make_ready(other)

      described_class.new(target).activate

      expect(target.reload.status).to eq('active')
      expect(other.reload.status).to eq('setup_pending')
      expect(other.onboarding_status).to eq('in_progress')
    end
  end

  describe 'failed activation does not mutate' do
    it 'leaves status and onboarding_status unchanged when the tenant is not ready' do
      profile = create(:bloomwire_business_profile, account: account,
                                                    status: 'setup_pending', onboarding_status: 'in_progress')

      result = described_class.new(profile).activate

      expect(result.success).to be(false)
      expect(profile.reload.status).to eq('setup_pending')
      expect(profile.onboarding_status).to eq('in_progress')
    end
  end

  describe 'no Chatwoot mutation' do
    it 'does not create or change inbox/channel/conversation/contact/message records' do
      profile = create(:bloomwire_business_profile, account: account,
                                                    status: 'setup_pending', onboarding_status: 'in_progress')
      make_ready(profile)
      create(:contact, account: account, name: 'Secret Contact')
      create(:message, account: account, content: 'Secret message body')

      snapshot = lambda do
        [Inbox.count, Channel::WebWidget.count, Conversation.count, Contact.count, Message.count]
      end
      before = snapshot.call

      described_class.new(profile).activate

      expect(snapshot.call).to eq(before)
    end
  end

  describe 'safe failure reasons (no data leakage)' do
    it 'returns only safe, non-identifying symbol reason codes' do
      profile = create(:bloomwire_business_profile, account: account,
                                                    status: 'setup_pending', onboarding_status: 'in_progress')

      result = described_class.new(profile).activate

      expect(result.error)
        .to be_in(%i[profile_not_found chatwoot_not_ready onboarding_steps_missing onboarding_incomplete])
    end
  end
end
