require 'rails_helper'

# Phase 15A.1: owner-only create+grant-by-email invite flow.
RSpec.describe Bloomwire::PlatformAdminInviter do
  let!(:owner) do
    sa = create(:super_admin, :unapproved_platform_admin)
    Bloomwire::PlatformAdmin.grant!(user: sa, role: :owner)
    sa
  end

  def invite(email:, actor: owner, name: 'New Admin', role: 'admin', reason: 'expansion')
    described_class.call(actor: actor, email: email, name: name, role: role, reason: reason)
  end

  it 'refuses a non-owner actor' do
    non_owner = create(:super_admin, :unapproved_platform_admin)
    Bloomwire::PlatformAdmin.grant!(user: non_owner, role: :admin)
    expect { invite(actor: non_owner, email: 'x@bloomwire.local') }.to raise_error(described_class::NotAuthorizedError)
  end

  it 'requires name, email, role and reason' do
    expect { invite(email: 'x@bloomwire.local', reason: '') }.to raise_error(described_class::InvalidInputError)
  end

  it 'creates a new SuperAdmin + active approval and exposes no raw password' do
    result = nil
    expect { result = invite(email: 'fresh@bloomwire.local', role: 'admin') }.to change(SuperAdmin, :count).by(1)

    user = User.from_email('fresh@bloomwire.local')
    expect(user.type).to eq('SuperAdmin')
    expect(user.encrypted_password).to be_present
    expect(Bloomwire::PlatformAdmin.active.exists?(user_id: user.id)).to be(true)
    expect(result).to include(created_user: true)
    expect(result.to_s).not_to match(/password/i)
  end

  it 'grants an existing SuperAdmin without creating a new user (and sets role)' do
    existing = create(:super_admin, :unapproved_platform_admin, email: 'existing@bloomwire.local')
    expect { invite(email: 'existing@bloomwire.local', role: 'support') }.not_to change(SuperAdmin, :count)
    expect(Bloomwire::PlatformAdmin.active.find_by(user_id: existing.id).role).to eq('support')
  end

  it 'reactivates a previously revoked SuperAdmin via the grant flow' do
    revoked = create(:super_admin, :unapproved_platform_admin, email: 'revoked@bloomwire.local')
    Bloomwire::PlatformAdmin.create!(user: revoked, role: :admin, enabled: false, revoked_at: Time.current)
    invite(email: 'revoked@bloomwire.local', role: 'admin')
    expect(Bloomwire::PlatformAdmin.active.exists?(user_id: revoked.id)).to be(true)
  end

  it 'refuses an existing business/customer user (no conversion, no approval row)' do
    biz = create(:user, email: 'biz@customer.local')
    expect { invite(email: 'biz@customer.local') }.to raise_error(described_class::BusinessUserError)
    expect(biz.reload.type).to be_nil
    expect(Bloomwire::PlatformAdmin.exists?(user_id: biz.id)).to be(false)
  end

  it 'refuses to demote the last active owner via the grant flow' do
    expect { invite(email: owner.email, role: 'admin') }.to raise_error(described_class::Error)
    expect(Bloomwire::PlatformAdmin.active_owners.exists?(user_id: owner.id)).to be(true)
  end
end
