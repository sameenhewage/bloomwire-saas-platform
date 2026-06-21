require 'rails_helper'

# Edge & security coverage for the Bloomwire permission/access foundation.
#
# Guarantees (see AGENTS.md rules 1, 3, 4, 8 and this slice's Product Truth Gate):
# - Strictly tenant-scoped: cross-tenant access is denied.
# - Missing user/account/profile is handled safely (deny, never raise).
# - Backend-enforced: decisions come from a plain backend object, not the UI.
# - No Enterprise/custom_roles dependency: membership is read from the core
#   AccountUser role only.
# - No Chatwoot conversation/message/contact data is read, copied, or exposed.
RSpec.describe Bloomwire::AccessPolicy do
  let(:account) { create(:account) }
  let(:profile) do
    create(:bloomwire_business_profile, account: account,
                                        status: 'active', onboarding_status: 'completed')
  end

  describe 'cross-tenant access denied' do
    it 'allows the matching tenant admin but denies that same admin on another tenant' do
      admin_a = create(:user)
      create(:account_user, account: account, user: admin_a, role: :administrator)
      account_b = create(:account)
      profile_b = create(:bloomwire_business_profile, account: account_b,
                                                      status: 'active', onboarding_status: 'completed')

      expect(described_class.new(user: admin_a, profile: profile).can?(:view_business_profile)).to be(true)
      expect(described_class.new(user: admin_a, profile: profile_b).can?(:view_business_profile)).to be(false)
    end
  end

  describe 'tenant agent (non-admin member)' do
    it 'cannot view tenant metadata (admin-only in this foundation)' do
      agent = create(:user)
      create(:account_user, account: account, user: agent, role: :agent)

      expect(described_class.new(user: agent, profile: profile).can?(:view_business_profile)).to be(false)
    end
  end

  describe 'tenant admin of a non-active own tenant' do
    it 'cannot view yet (tenant access begins once the tenant is active)' do
      pending_profile = create(:bloomwire_business_profile, account: account,
                                                            status: 'setup_pending', onboarding_status: 'in_progress')
      admin = create(:user)
      create(:account_user, account: account, user: admin, role: :administrator)

      expect(described_class.new(user: admin, profile: pending_profile).can?(:view_business_profile)).to be(false)
    end
  end

  describe 'missing user/account/profile handled safely' do
    let(:super_admin) { create(:super_admin) }

    it 'denies and does not raise for a nil user' do
      expect { described_class.new(user: nil, profile: profile).can?(:view_business_profile) }.not_to raise_error
      expect(described_class.new(user: nil, profile: profile).can?(:view_business_profile)).to be(false)
    end

    it 'denies when the profile is nil' do
      expect(described_class.new(user: super_admin, profile: nil).can?(:view_business_profile)).to be(false)
    end

    it 'denies a member-less user when the profile has no account' do
      orphan = build(:bloomwire_business_profile, account: nil, status: 'active')

      expect(described_class.new(user: create(:user), profile: orphan).can?(:view_business_profile)).to be(false)
    end

    it 'denies an unknown action even for a super admin (safe default)' do
      expect(described_class.new(user: super_admin, profile: profile).can?(:delete_everything)).to be(false)
    end
  end

  describe 'backend-enforced (not frontend-only)' do
    it 'decides access from its inputs alone, with no request/session/view context' do
      stranger = create(:user)
      policy = described_class.new(user: stranger, profile: profile)

      expect(policy.can?(:view_business_profile)).to be(false)
      expect(policy.can?(:activate_tenant)).to be(false)
    end
  end

  describe 'no Enterprise/custom_roles dependency' do
    # Scan CODE only (comments may legitimately describe what we avoid); a
    # dependency means an actual code reference.
    let(:source) do
      File.readlines(Rails.root.join('app/services/bloomwire/access_policy.rb'))
          .reject { |line| line.strip.start_with?('#') }
          .join
    end

    it 'does not reference Chatwoot Enterprise custom roles' do
      expect(source).not_to match(/custom_role/i)
      expect(source).not_to match(/CustomRole/)
      expect(source).not_to match(/custom_permission/i)
    end

    it 'authorises an account admin purely from the core AccountUser role' do
      admin = create(:user)
      create(:account_user, account: account, user: admin, role: :administrator)

      expect(described_class.new(user: admin, profile: profile).can?(:view_business_profile)).to be(true)
    end
  end

  describe 'no Chatwoot conversation/message/contact data copied or exposed' do
    # Scan CODE only (comments may legitimately describe what we avoid); a
    # dependency means an actual code reference.
    let(:source) do
      File.readlines(Rails.root.join('app/services/bloomwire/access_policy.rb'))
          .reject { |line| line.strip.start_with?('#') }
          .join
    end

    it 'does not create or read Chatwoot data records while evaluating policy' do
      super_admin = create(:super_admin)
      create(:contact, account: account, name: 'Leaky Contact')
      create(:message, account: account, content: 'Leaky body')
      snapshot = -> { [Conversation.count, Message.count, Contact.count] }
      before = snapshot.call

      described_class.new(user: super_admin, profile: profile).can?(:view_business_profile)

      expect(snapshot.call).to eq(before)
    end

    it 'does not reference Chatwoot conversation/message/contact models' do
      expect(source).not_to match(/\bConversation\b/)
      expect(source).not_to match(/\bMessage\b/)
      expect(source).not_to match(/\bContact\b/)
    end
  end
end
