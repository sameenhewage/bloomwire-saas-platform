require 'rails_helper'

# Phase 15A.1: owner-only Platform Admin management console. Mode ON; fake values only; no secrets.
RSpec.describe 'SuperAdmin Bloomwire Platform Admins', type: :request do
  let(:owner) do
    sa = create(:super_admin, :unapproved_platform_admin)
    Bloomwire::PlatformAdmin.grant!(user: sa, role: :owner)
    sa
  end
  # create(:super_admin) auto-grants an *admin* approval row -> approved for /super_admin, but NOT an owner.
  let(:non_owner_admin) { create(:super_admin) }

  let(:account) { create(:account) }
  let(:business_admin) { create(:user, password: 'Password1!', account: account, role: :administrator) }

  before do
    config = InstallationConfig.where(name: 'BLOOMWIRE_MODE_ENABLED').first_or_initialize
    config.value = true
    config.locked = false
    config.save!
    GlobalConfig.clear_cache
  end

  describe 'GET index (owner-only)' do
    it 'allows the platform owner' do
      sign_in(owner, scope: :super_admin)
      get '/super_admin/bloomwire_platform_admins'
      expect(response).to have_http_status(:success)
    end

    it 'bounces a non-owner platform admin' do
      sign_in(non_owner_admin, scope: :super_admin)
      get '/super_admin/bloomwire_platform_admins'
      expect(response).to have_http_status(:redirect)
    end

    it 'blocks a business account user (no :super_admin scope)' do
      sign_in(business_admin, scope: :user)
      get '/super_admin/bloomwire_platform_admins'
      expect(response).to have_http_status(:redirect)
      expect(response.redirect_url).to include('/super_admin/sign_in')
    end
  end

  describe 'POST create (invite/grant by email)' do
    it 'lets the owner create + grant a brand-new SuperAdmin' do
      sign_in(owner, scope: :super_admin)
      expect do
        post '/super_admin/bloomwire_platform_admins',
             params: { platform_admin: { name: 'Ops Two', email: 'ops2@bloomwire.local', role: 'admin', reason: 'new hire' } }
      end.to change(SuperAdmin, :count).by(1)
      user = User.from_email('ops2@bloomwire.local')
      expect(Bloomwire::PlatformAdmin.active.exists?(user_id: user.id)).to be(true)
    end

    it 'refuses a business/customer email (no conversion, no row)' do
      sign_in(owner, scope: :super_admin)
      post '/super_admin/bloomwire_platform_admins',
           params: { platform_admin: { name: 'X', email: business_admin.email, role: 'admin', reason: 'try' } }
      expect(business_admin.reload.type).to be_nil
      expect(Bloomwire::PlatformAdmin.exists?(user_id: business_admin.id)).to be(false)
    end

    it 'bounces a non-owner trying to create' do
      sign_in(non_owner_admin, scope: :super_admin)
      expect do
        post '/super_admin/bloomwire_platform_admins',
             params: { platform_admin: { name: 'X', email: 'x@bloomwire.local', role: 'admin', reason: 'try' } }
      end.not_to change(SuperAdmin, :count)
      expect(response).to have_http_status(:redirect)
    end
  end

  describe 'PATCH revoke (soft, last-owner protected)' do
    it 'soft-revokes a non-owner admin' do
      target = create(:super_admin) # has an active admin approval row
      target_row = Bloomwire::PlatformAdmin.find_by(user_id: target.id)
      sign_in(owner, scope: :super_admin)

      patch "/super_admin/bloomwire_platform_admins/#{target_row.id}/revoke"
      expect(target_row.reload.active?).to be(false)
    end

    it 'blocks revoking the last active owner' do
      owner_row = Bloomwire::PlatformAdmin.find_by(user_id: owner.id)
      sign_in(owner, scope: :super_admin)

      patch "/super_admin/bloomwire_platform_admins/#{owner_row.id}/revoke"
      expect(owner_row.reload.active?).to be(true)
    end
  end

  describe 'PATCH reactivate' do
    it 'reactivates a revoked row' do
      target = create(:super_admin, :unapproved_platform_admin)
      row = Bloomwire::PlatformAdmin.create!(user: target, role: :admin, enabled: false, revoked_at: Time.current)
      sign_in(owner, scope: :super_admin)

      patch "/super_admin/bloomwire_platform_admins/#{row.id}/reactivate"
      expect(row.reload.active?).to be(true)
    end
  end

  # Phase 15A.2: index rendering — role-change control for active non-last-owner rows + visible identity status.
  describe 'GET index (Phase 15A.2 controls)' do
    it 'renders a role-change select for an active non-owner and flags an inconsistent row as Needs repair' do
      admin = create(:super_admin) # active admin row via factory
      mismatched = create(:user)   # type nil -> identity inconsistent
      Bloomwire::PlatformAdmin.create!(user: mismatched, role: :support, enabled: true)
      sign_in(owner, scope: :super_admin)

      get '/super_admin/bloomwire_platform_admins'

      expect(response).to have_http_status(:success)
      admin_row = Bloomwire::PlatformAdmin.find_by(user_id: admin.id)
      expect(response.body).to include("bloomwire_platform_admins/#{admin_row.id}/change_role")
      expect(response.body).to include('Update role')
      expect(response.body).to include('Needs repair')
    end
  end

  # Phase 15A.2: owner-only role change.
  describe 'PATCH change_role' do
    it 'lets the owner change an admin to support' do
      target = create(:super_admin) # factory grants an active admin row
      row = Bloomwire::PlatformAdmin.find_by(user_id: target.id)
      sign_in(owner, scope: :super_admin)

      patch "/super_admin/bloomwire_platform_admins/#{row.id}/change_role", params: { role: 'support' }
      expect(row.reload.role).to eq('support')
    end

    it 'lets the owner promote an admin to owner' do
      target = create(:super_admin)
      row = Bloomwire::PlatformAdmin.find_by(user_id: target.id)
      sign_in(owner, scope: :super_admin)

      patch "/super_admin/bloomwire_platform_admins/#{row.id}/change_role", params: { role: 'owner' }
      expect(row.reload.role).to eq('owner')
    end

    it 'blocks demoting the last active owner' do
      owner_row = Bloomwire::PlatformAdmin.find_by(user_id: owner.id)
      sign_in(owner, scope: :super_admin)

      patch "/super_admin/bloomwire_platform_admins/#{owner_row.id}/change_role", params: { role: 'admin' }
      expect(owner_row.reload.role).to eq('owner')
    end

    it 'bounces a non-owner platform admin' do
      target = create(:super_admin)
      row = Bloomwire::PlatformAdmin.find_by(user_id: target.id)
      sign_in(non_owner_admin, scope: :super_admin)

      patch "/super_admin/bloomwire_platform_admins/#{row.id}/change_role", params: { role: 'support' }
      expect(response).to have_http_status(:redirect)
      expect(row.reload.role).to eq('admin')
    end
  end
end
