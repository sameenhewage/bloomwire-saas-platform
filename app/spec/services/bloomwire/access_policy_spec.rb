require 'rails_helper'

# Acceptance coverage for the Bloomwire permission/access foundation.
#
# Phase 4 — Slice 1: Permission Foundation / Access Policy.
# A backend, tenant-scoped policy that decides who may use Bloomwire tenant
# features. It reuses the existing Chatwoot AccountUser membership (core, NOT
# Enterprise custom_roles) and never reads or exposes Chatwoot
# conversation/message/contact data.
#
# Actions covered by this slice:
#   view_business_profile / view_onboarding_status / view_chatwoot_readiness
#   activate_tenant (platform-level control)
RSpec.describe Bloomwire::AccessPolicy do
  let(:account) { create(:account) }
  let(:profile) do
    create(:bloomwire_business_profile, account: account,
                                        status: 'active', onboarding_status: 'completed')
  end

  def policy_for(user, target = profile)
    described_class.new(user: user, profile: target)
  end

  def view_actions
    %i[view_business_profile view_onboarding_status view_chatwoot_readiness]
  end

  describe 'Super Admin (platform-level)' do
    let(:super_admin) { create(:super_admin) }

    it 'can access Bloomwire platform tenant controls (activate_tenant)' do
      expect(policy_for(super_admin).can?(:activate_tenant)).to be(true)
    end

    it 'can view all tenant metadata' do
      view_actions.each do |action|
        expect(policy_for(super_admin).can?(action)).to be(true), "expected super admin allowed #{action}"
      end
    end
  end

  describe 'tenant account admin of an active own tenant' do
    let(:admin) { create(:user) }

    before { create(:account_user, account: account, user: admin, role: :administrator) }

    it 'can view its own tenant metadata' do
      view_actions.each do |action|
        expect(policy_for(admin).can?(action)).to be(true), "expected own-tenant admin allowed #{action}"
      end
    end

    it 'cannot activate the tenant (platform-level action reserved)' do
      expect(policy_for(admin).can?(:activate_tenant)).to be(false)
    end
  end

  describe 'tenant account admin of a different tenant' do
    let(:other_admin) { create(:user) }
    let(:other_account) { create(:account) }

    before { create(:account_user, account: other_account, user: other_admin, role: :administrator) }

    it 'cannot view this tenant metadata (cross-tenant denied)' do
      expect(policy_for(other_admin).can?(:view_business_profile)).to be(false)
    end
  end

  describe 'non-member user' do
    let(:stranger) { create(:user) }

    it 'cannot view tenant metadata' do
      view_actions.each do |action|
        expect(policy_for(stranger).can?(action)).to be(false), "expected non-member denied #{action}"
      end
    end

    it 'cannot activate the tenant' do
      expect(policy_for(stranger).can?(:activate_tenant)).to be(false)
    end
  end
end
