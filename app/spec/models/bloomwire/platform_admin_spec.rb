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
end
