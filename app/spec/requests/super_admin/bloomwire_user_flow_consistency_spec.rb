require 'rails_helper'

# Phase 15A.2: the SuperAdmin Users page is for normal/customer users + account assignment. When Bloomwire
# Mode is ON it must NOT create/change platform admins via the raw users.type field, and the index shows the
# real "Platform Access" instead of the misleading "Type" column. Mode OFF == stock Chatwoot.
RSpec.describe 'SuperAdmin Users flow consistency (Phase 15A.2)', type: :request do
  let(:super_admin) { create(:super_admin) }

  def bloomwire_mode(value)
    config = InstallationConfig.where(name: 'BLOOMWIRE_MODE_ENABLED').first_or_initialize
    config.value = value
    config.locked = false
    config.save!
    GlobalConfig.clear_cache
  end

  before { GlobalConfig.clear_cache }

  describe 'Users create/update with Bloomwire Mode ON' do
    before do
      bloomwire_mode(true)
      sign_in(super_admin, scope: :super_admin)
    end

    it 'ignores type=SuperAdmin on create — new user is a normal User (type nil)' do
      post '/super_admin/users', params: { user: {
        name: 'New Person', display_name: 'New Person', email: 'newp@example.com',
        password: 'Password1!', confirmed_at: Time.current, type: 'SuperAdmin'
      } }

      created = User.from_email('newp@example.com')
      expect(created).to be_present
      expect(created.type).to be_nil
      expect(SuperAdmin.exists?(id: created.id)).to be(false)
    end

    it 'cannot change a normal user type to SuperAdmin via update' do
      user = create(:user)
      patch "/super_admin/users/#{user.id}", params: { user: { type: 'SuperAdmin', display_name: 'X' } }
      expect(user.reload.type).to be_nil
    end

    it 'cannot change a platform admin user type away via update' do
      pa_user = create(:super_admin, :unapproved_platform_admin)
      patch "/super_admin/users/#{pa_user.id}", params: { user: { type: '', display_name: 'Y' } }
      expect(pa_user.reload.type).to eq('SuperAdmin')
    end
  end

  describe 'Users create with Bloomwire Mode OFF preserves stock behavior' do
    before do
      bloomwire_mode(false)
      sign_in(super_admin, scope: :super_admin)
    end

    it 'allows creating a SuperAdmin via the raw Users form (stock)' do
      post '/super_admin/users', params: { user: {
        name: 'Stock Admin', display_name: 'Stock Admin', email: 'stock@example.com',
        password: 'Password1!', confirmed_at: Time.current, type: 'SuperAdmin'
      } }
      expect(User.from_email('stock@example.com').type).to eq('SuperAdmin')
    end
  end

  describe 'Users index Platform Access column (Mode ON)' do
    before do
      bloomwire_mode(true)
      sign_in(super_admin, scope: :super_admin)
    end

    it 'shows the Platform Access header + computed labels, not the raw Type column' do
      create(:user, name: 'Normal Person')
      owner = create(:super_admin, :unapproved_platform_admin, name: 'Owner Person')
      Bloomwire::PlatformAdmin.grant!(user: owner, role: :owner)

      get '/super_admin/users'
      doc = Nokogiri::HTML(response.body)
      headers = doc.css('table thead th').map { |h| h.text.squish }

      expect(response).to have_http_status(:success)
      expect(headers).to include('Platform Access')
      expect(headers).not_to include('Type')
      expect(response.body).to include('No platform access')
      expect(response.body).to include('Owner')
    end
  end

  describe 'user detail (show) page clarity (Mode ON)' do
    before do
      bloomwire_mode(true)
      sign_in(super_admin, scope: :super_admin)
    end

    it 'shows Platform Access + account-assignment note and does not expose a raw Type editor' do
      owner = create(:super_admin, :unapproved_platform_admin, name: 'Owner Person')
      Bloomwire::PlatformAdmin.grant!(user: owner, role: :owner)

      get "/super_admin/users/#{owner.id}"
      doc = Nokogiri::HTML(response.body)
      labels = doc.css('dt.attribute-label').map { |l| l.text.squish }

      expect(response).to have_http_status(:success)
      expect(labels).to include('Platform Access')
      expect(labels).not_to include('Type')
      expect(response.body).to include('Owner')
      expect(response.body).to include('managed from Bloomwire')
      expect(response.body).to include('customer account access')
    end
  end

  describe 'account assignment from the user still works (Mode ON)' do
    before do
      bloomwire_mode(true)
      sign_in(super_admin, scope: :super_admin)
    end

    it 'creates an account_user (customer access) without granting platform access' do
      account = create(:account)
      user = create(:user)

      expect do
        post '/super_admin/account_users',
             params: { account_user: { account_id: account.id, user_id: user.id, role: 'administrator' } }
      end.to change(AccountUser, :count).by(1)

      expect(AccountUser.find_by(account_id: account.id, user_id: user.id).role).to eq('administrator')
      expect(Bloomwire::PlatformAdmin.approved?(user)).to be(false)
    end
  end
end
