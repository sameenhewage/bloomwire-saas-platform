require 'rails_helper'

# Acceptance + edge coverage for the Bloomwire WhatsApp setup decision authority.
#
# Phase 4.4-b-WA.2C — Dialog tenant deny (ADR 0005, Bloomwire owns external app/channel
# configuration). The policy reads the account's Bloomwire control-plane anchor:
# - Bloomwire-managed tenant (has a BloomwireBusinessProfile): WhatsApp setup is
#   platform-only, so every tenant principal (admins, agents, cross-tenant, nil) is denied.
#   The SuperAdmin platform path uses Bloomwire::ChannelSetup::Service, NOT this policy.
# - Plain Chatwoot account (no profile): UNCHANGED — the pre-existing account-administrator
#   gate still applies, so installs that do not use Bloomwire behave exactly as before.
RSpec.describe Bloomwire::ChannelControlPolicy do
  let(:account) { create(:account) }

  def policy_for(user, target_account = account)
    described_class.new(user: user, account: target_account)
  end

  describe '#can_setup_whatsapp?' do
    # SuperAdmin / platform WhatsApp setup does NOT go through this policy — it uses
    # Bloomwire::ChannelSetup::Service (SuperAdmin actor). This account-scoped policy is
    # only reachable via tenant controllers (which require AccountUser membership), so a
    # membership-less SuperAdmin is denied here rather than carrying a platform allowance.
    context 'when the user is a SuperAdmin without tenant membership' do
      let(:super_admin) { create(:super_admin) }

      it 'is denied (platform setup uses Bloomwire::ChannelSetup::Service, not this policy)' do
        expect(policy_for(super_admin).can_setup_whatsapp?).to be(false)
      end
    end

    context 'when the user is an account administrator of a plain Chatwoot tenant (no Bloomwire profile)' do
      let(:admin) { create(:user) }

      before { create(:account_user, account: account, user: admin, role: :administrator) }

      it 'is allowed (pre-existing admin gate, plain Chatwoot unchanged)' do
        expect(account.bloomwire_business_profile).to be_nil
        expect(policy_for(admin).can_setup_whatsapp?).to be(true)
      end
    end

    # The flip: once a tenant is Bloomwire-managed, external WhatsApp configuration is a
    # platform responsibility, so even the account administrator is denied here.
    context 'when the tenant is Bloomwire-managed (has a business profile)' do
      before { create(:bloomwire_business_profile, account: account) }

      it 'denies an account administrator (external WhatsApp setup is platform-only)' do
        admin = create(:user)
        create(:account_user, account: account, user: admin, role: :administrator)

        expect(policy_for(admin).can_setup_whatsapp?).to be(false)
      end

      it 'denies an agent' do
        agent = create(:user)
        create(:account_user, account: account, user: agent, role: :agent)

        expect(policy_for(agent).can_setup_whatsapp?).to be(false)
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
