require 'rails_helper'

# Phase 15A.1: env-driven primary platform-owner setup. Must point to an existing dedicated SuperAdmin and
# must NEVER promote a normal/business/customer user (review blocker 1). Fail-safe with no writes otherwise.
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

  context 'when the configured email belongs to a normal business/customer user' do
    let!(:business_user) { create(:user, email: 'biz@customer.local') }

    it 'is refused (NotSuperAdminError), never promotes type, and creates no approval row' do
      expect do
        expect { described_class.call(email: 'biz@customer.local') }.to raise_error(described_class::NotSuperAdminError)
      end.not_to change(Bloomwire::PlatformAdmin, :count)

      expect(business_user.reload.type).to be_nil
      expect(Bloomwire::PlatformAdmin.exists?(user_id: business_user.id)).to be(false)
    end
  end

  it 'makes an existing dedicated SuperAdmin an active owner' do
    sa = create(:super_admin, :unapproved_platform_admin, email: 'owner@bloomwire.local')
    result = described_class.call(email: 'owner@bloomwire.local')

    expect(result[:role]).to eq('owner')
    expect(result[:active]).to be(true)
    expect(Bloomwire::PlatformAdmin.active_owners.exists?(user_id: sa.id)).to be(true)
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
