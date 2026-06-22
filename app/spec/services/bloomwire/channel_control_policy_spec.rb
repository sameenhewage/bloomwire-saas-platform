require 'rails_helper'

# Acceptance + edge coverage for the Bloomwire WhatsApp setup decision authority.
#
# Phase 4.4-b-WA — Slice 1 (behavior-neutral seam). The policy currently mirrors the
# pre-existing "account administrator" rule, plus SuperAdmin/platform. It is
# intentionally PROFILE-AGNOSTIC in this slice: it must NOT depend on a
# BloomwireBusinessProfile yet, so tenants without a profile keep working exactly as
# before. A later slice may add a tenant capability flag and flip the default.
RSpec.describe Bloomwire::ChannelControlPolicy do
  let(:account) { create(:account) }

  def policy_for(user, target_account = account)
    described_class.new(user: user, account: target_account)
  end

  describe '#can_setup_whatsapp?' do
    # SuperAdmin / platform WhatsApp setup is intentionally FUTURE WORK in this slice.
    # These account-scoped controllers require AccountUser membership before the policy
    # is reachable, so the policy matches that reachable behavior: a membership-less
    # SuperAdmin is denied rather than carrying a misleading platform allowance.
    context 'when the user is a SuperAdmin without tenant membership' do
      let(:super_admin) { create(:super_admin) }

      it 'is denied (no AccountUser membership; platform setup is future work)' do
        expect(policy_for(super_admin).can_setup_whatsapp?).to be(false)
      end
    end

    context 'when the user is an account administrator of the tenant' do
      let(:admin) { create(:user) }

      before { create(:account_user, account: account, user: admin, role: :administrator) }

      it 'is allowed' do
        expect(policy_for(admin).can_setup_whatsapp?).to be(true)
      end

      it 'is allowed even when the tenant has no Bloomwire business profile (profile-agnostic in this slice)' do
        expect(account.bloomwire_business_profile).to be_nil
        expect(policy_for(admin).can_setup_whatsapp?).to be(true)
      end
    end

    context 'when the user is an agent of the tenant' do
      let(:agent) { create(:user) }

      before { create(:account_user, account: account, user: agent, role: :agent) }

      it 'is denied' do
        expect(policy_for(agent).can_setup_whatsapp?).to be(false)
      end
    end

    context 'when the user is an administrator of a different tenant' do
      let(:other_account) { create(:account) }
      let(:other_admin) { create(:user) }

      before { create(:account_user, account: other_account, user: other_admin, role: :administrator) }

      it 'is denied (cross-tenant)' do
        expect(policy_for(other_admin).can_setup_whatsapp?).to be(false)
      end
    end

    context 'with nil inputs (safe deny)' do
      let(:admin) { create(:user) }

      before { create(:account_user, account: account, user: admin, role: :administrator) }

      it 'denies a nil user' do
        expect(policy_for(nil).can_setup_whatsapp?).to be(false)
      end

      it 'denies a nil account' do
        expect(policy_for(admin, nil).can_setup_whatsapp?).to be(false)
      end
    end
  end
end
