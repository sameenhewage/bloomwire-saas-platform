require 'rails_helper'

# Phase 15A.1: env-driven primary platform-owner setup (no hardcoded email, fail-safe).
RSpec.describe Bloomwire::EnsurePlatformOwnerService do
  it 'raises MissingEmailError when no owner email is configured' do
    with_modified_env BLOOMWIRE_PLATFORM_OWNER_EMAIL: nil do
      expect { described_class.call }.to raise_error(described_class::MissingEmailError)
    end
  end

  it 'raises UserNotFoundError (and creates nothing) when the user does not exist' do
    expect do
      expect { described_class.call(email: 'ghost@bloomwire.local') }.to raise_error(described_class::UserNotFoundError)
    end.not_to change(Bloomwire::PlatformAdmin, :count)
  end

  it 'makes an existing SuperAdmin an active owner (no promotion needed)' do
    sa = create(:super_admin, :unapproved_platform_admin, email: 'owner@bloomwire.local')
    result = described_class.call(email: 'owner@bloomwire.local')

    expect(result[:role]).to eq('owner')
    expect(result[:active]).to be(true)
    expect(result[:promoted_to_super_admin]).to be(false)
    expect(Bloomwire::PlatformAdmin.active_owners.exists?(user_id: sa.id)).to be(true)
  end

  it 'promotes a non-SuperAdmin user to SuperAdmin and makes them the owner' do
    user = create(:user, email: 'newowner@bloomwire.local')
    expect(user.type).to be_nil

    result = described_class.call(email: 'newowner@bloomwire.local')

    expect(result[:promoted_to_super_admin]).to be(true)
    expect(user.reload.type).to eq('SuperAdmin')
    expect(Bloomwire::PlatformAdmin.active_owners.exists?(user_id: user.id)).to be(true)
  end

  it 'is idempotent (re-running does not duplicate the row)' do
    create(:super_admin, :unapproved_platform_admin, email: 'owner2@bloomwire.local')
    described_class.call(email: 'owner2@bloomwire.local')

    expect { described_class.call(email: 'owner2@bloomwire.local') }.not_to change(Bloomwire::PlatformAdmin, :count)
  end

  it 'reads BLOOMWIRE_PLATFORM_OWNER_EMAIL from the environment' do
    create(:super_admin, :unapproved_platform_admin, email: 'envowner@bloomwire.local')
    with_modified_env BLOOMWIRE_PLATFORM_OWNER_EMAIL: 'EnvOwner@Bloomwire.local' do
      expect(described_class.call[:role]).to eq('owner')
    end
  end
end
