require 'rails_helper'

# Phase 15A (ADR-0007): approval source of truth for the Bloomwire platform-admin boundary.
RSpec.describe Bloomwire::PlatformAdmin, type: :model do
  describe '.approved?' do
    it 'is false for a nil user' do
      expect(described_class.approved?(nil)).to be(false)
    end

    it 'is false when the user has no approval row' do
      expect(described_class.approved?(create(:user))).to be(false)
    end

    it 'is true with an active approval row' do
      user = create(:user)
      described_class.create!(user: user, enabled: true)
      expect(described_class.approved?(user)).to be(true)
    end

    it 'is false when the row is disabled' do
      user = create(:user)
      described_class.create!(user: user, enabled: false)
      expect(described_class.approved?(user)).to be(false)
    end

    it 'is false when the row is revoked' do
      user = create(:user)
      described_class.create!(user: user, enabled: true, revoked_at: Time.current)
      expect(described_class.approved?(user)).to be(false)
    end

    it 'is true for a bootstrap-allowlisted email (case-insensitive, trimmed) with an empty table' do
      user = create(:user, email: 'ops@bloomwire.local')
      with_modified_env BLOOMWIRE_BOOTSTRAP_PLATFORM_ADMIN_EMAILS: '  OPS@Bloomwire.Local , other@x.com ' do
        expect(described_class.approved?(user)).to be(true)
      end
    end

    it 'is false for an email not on the bootstrap list when no row exists' do
      user = create(:user, email: 'nope@bloomwire.local')
      with_modified_env BLOOMWIRE_BOOTSTRAP_PLATFORM_ADMIN_EMAILS: 'ops@bloomwire.local' do
        expect(described_class.approved?(user)).to be(false)
      end
    end
  end

  describe '.grant! / .revoke!' do
    let(:user) { create(:user) }

    it 'grant! creates an active, approved row' do
      record = described_class.grant!(user: user, role: :owner, reason: 'launch')
      expect(record).to be_persisted
      expect(record.enabled).to be(true)
      expect(record.revoked_at).to be_nil
      expect(record.approved_at).to be_present
      expect(record.role).to eq('owner')
      expect(described_class.approved?(user)).to be(true)
    end

    it 'grant! reactivates a revoked row without duplicating (one row per user)' do
      described_class.grant!(user: user)
      described_class.revoke!(user: user)
      expect(described_class.approved?(user)).to be(false)

      described_class.grant!(user: user)
      expect(described_class.approved?(user)).to be(true)
      expect(described_class.where(user_id: user.id).count).to eq(1)
    end

    it 'revoke! disables and timestamps the row' do
      described_class.grant!(user: user)
      record = described_class.revoke!(user: user, reason: 'offboard')
      expect(record.enabled).to be(false)
      expect(record.revoked_at).to be_present
      expect(described_class.approved?(user)).to be(false)
    end

    it 'revoke! is a no-op (returns nil) when there is no row' do
      expect(described_class.revoke!(user: user)).to be_nil
    end
  end

  describe 'validations' do
    it 'enforces one approval row per user' do
      user = create(:user)
      described_class.create!(user: user)
      expect(described_class.new(user: user)).not_to be_valid
    end
  end

  # --- Phase 15A.1: ownership invariants ---

  describe 'ownership + last-owner protection' do
    def owner_row(user = create(:user))
      described_class.create!(user: user, role: :owner, enabled: true)
    end

    it 'last_active_owner? is true for the only active owner' do
      expect(owner_row.last_active_owner?).to be(true)
    end

    it 'last_active_owner? is false when a second active owner exists' do
      first = owner_row
      owner_row
      expect(first.last_active_owner?).to be(false)
    end

    it 'last_active_owner? is false for a non-owner row' do
      record = described_class.create!(user: create(:user), role: :admin, enabled: true)
      expect(record.last_active_owner?).to be(false)
    end

    it 'soft_revoke! refuses to revoke the last active owner' do
      record = owner_row
      expect { record.soft_revoke! }.to raise_error(described_class::LastOwnerError)
      expect(record.reload.active?).to be(true)
    end

    it 'soft_revoke! allows revoking an owner when another active owner remains' do
      first = owner_row
      owner_row
      expect { first.soft_revoke! }.not_to raise_error
      expect(first.reload.active?).to be(false)
    end

    it 'soft_revoke! soft-revokes an admin (keeps the row, flips inactive)' do
      record = described_class.create!(user: create(:user), role: :admin, enabled: true)
      record.soft_revoke!(reason: 'offboard')
      expect(record).to be_persisted
      expect(record.active?).to be(false)
      expect(record.revoked_at).to be_present
    end

    it 'reactivate! re-enables a revoked row with the new role + reason' do
      record = described_class.create!(user: create(:user), role: :admin, enabled: false, revoked_at: Time.current)
      record.reactivate!(role: :support, reason: 'rejoin')
      expect(record.active?).to be(true)
      expect(record.role).to eq('support')
      expect(record.reason).to eq('rejoin')
    end

    it 'class revoke!(user:) refuses the last active owner' do
      record = owner_row
      expect { described_class.revoke!(user: record.user) }.to raise_error(described_class::LastOwnerError)
    end
  end
end
