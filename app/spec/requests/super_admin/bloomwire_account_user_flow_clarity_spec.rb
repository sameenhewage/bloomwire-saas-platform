require 'rails_helper'

# Phase 15B: clarity-only improvements to the SuperAdmin customer account-user flow. Business labels
# (Business Admin / Agent) and clearer copy when Bloomwire Mode is ON, with the underlying account_users.role
# DB values (administrator / agent) UNCHANGED. Mode OFF == stock Chatwoot.
RSpec.describe 'SuperAdmin account-user flow clarity (Phase 15B)', type: :request do
  let(:super_admin) { create(:super_admin) }

  def bloomwire_mode(value)
    config = InstallationConfig.where(name: 'BLOOMWIRE_MODE_ENABLED').first_or_initialize
    config.value = value
    config.locked = false
    config.save!
    GlobalConfig.clear_cache
  end

  before { GlobalConfig.clear_cache }

  describe 'AccountUserDashboard.bloomwire_role_collection' do
    it 'maps business labels to UNCHANGED db values in Mode ON' do
      bloomwire_mode(true)
      expect(AccountUserDashboard.bloomwire_role_collection).to eq([['Business Admin', 'administrator'], ['Agent', 'agent']])
    end

    it 'is the stock role keys in Mode OFF' do
      bloomwire_mode(false)
      expect(AccountUserDashboard.bloomwire_role_collection).to eq(AccountUser.roles.keys)
    end
  end

  describe 'user show account-assignment form (Mode ON)' do
    before do
      bloomwire_mode(true)
      sign_in(super_admin, scope: :super_admin)
    end

    it 'renders the clarified heading, intro, business role labels and role helper text' do
      get "/super_admin/users/#{create(:user).id}"

      expect(response).to have_http_status(:success)
      expect(response.body).to include('Assign customer account access')
      expect(response.body).to include('managed from')
      expect(response.body).to include('Business Admin')
      expect(response.body).to include('manage the selected customer account based on Chatwoot account permissions')
      expect(response.body).to include('handle conversations inside the selected customer account')
    end

    it 'keeps the unchanged db role values and does not reintroduce the raw Type field' do
      get "/super_admin/users/#{create(:user).id}"

      expect(response.body).to include('value="administrator"')
      expect(response.body).to include('value="agent"')
      doc = Nokogiri::HTML(response.body)
      expect(doc.css('dt.attribute-label').map { |l| l.text.squish }).not_to include('Type')
    end
  end

  describe 'user show account-assignment form (Mode OFF == stock)' do
    before do
      bloomwire_mode(false)
      sign_in(super_admin, scope: :super_admin)
    end

    it 'shows neither business labels nor the Bloomwire copy, but keeps the stock role values' do
      user = create(:user)
      get "/super_admin/users/#{user.id}"

      expect(response).to have_http_status(:success)
      expect(response.body).not_to include('Business Admin')
      expect(response.body).not_to include('Assign customer account access')
      expect(response.body).to include('value="administrator"')
    end
  end

  describe 'account assignment persists db role + Mode-ON flash wording' do
    before do
      bloomwire_mode(true)
      sign_in(super_admin, scope: :super_admin)
    end

    it 'saves administrator (db value) and flashes "Customer account access granted"' do
      account = create(:account)
      user = create(:user)
      post '/super_admin/account_users',
           params: { account_user: { account_id: account.id, user_id: user.id, role: 'administrator' } }

      expect(AccountUser.find_by(account_id: account.id, user_id: user.id).role).to eq('administrator')
      expect(flash[:notice]).to eq('Customer account access granted.')
    end

    it 'saves agent (db value)' do
      account = create(:account)
      user = create(:user)
      post '/super_admin/account_users',
           params: { account_user: { account_id: account.id, user_id: user.id, role: 'agent' } }

      expect(AccountUser.find_by(account_id: account.id, user_id: user.id).role).to eq('agent')
    end

    it 'flashes "Customer account access removed" on destroy' do
      account = create(:account)
      user = create(:user)
      au = AccountUser.create!(account: account, user: user, role: :agent)

      delete "/super_admin/account_users/#{au.id}"
      expect(flash[:notice]).to eq('Customer account access removed.')
    end
  end

  describe 'account assignment Mode OFF uses stock flash' do
    before do
      bloomwire_mode(false)
      sign_in(super_admin, scope: :super_admin)
    end

    it 'does not use Bloomwire wording' do
      account = create(:account)
      user = create(:user)
      post '/super_admin/account_users',
           params: { account_user: { account_id: account.id, user_id: user.id, role: 'agent' } }

      expect(flash[:notice]).not_to eq('Customer account access granted.')
    end
  end

  describe 'assigned customer user remains a normal user with no platform access' do
    it 'has users.type nil and cannot access /super_admin' do
      bloomwire_mode(true)
      account = create(:account)
      user = create(:user)
      AccountUser.create!(account: account, user: user, role: :administrator)

      expect(user.reload.type).to be_nil
      expect(Bloomwire::PlatformAdmin.approved?(user)).to be(false)

      # a normal/business user cannot authenticate into the SuperAdmin (STI-scoped) console
      get '/super_admin'
      expect(response).to have_http_status(:redirect)
    end
  end
end
