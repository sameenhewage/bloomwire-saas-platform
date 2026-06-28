require 'rails_helper'

# Phase 15A (ADR-0007): /super_admin requires BOTH a SuperAdmin session AND an approved Bloomwire platform
# admin when Bloomwire Mode is ON. Mode OFF => stock Chatwoot (SuperAdmin alone). Fake values only; no secrets.
RSpec.describe 'Bloomwire Platform Admin Boundary', type: :request do
  let(:approved_admin) { create(:super_admin) }                               # SuperAdmin + active approval (factory default)
  let(:unapproved_admin) { create(:super_admin, :unapproved_platform_admin) } # SuperAdmin identity, NO approval

  let(:account) { create(:account) }
  let(:business_admin) { create(:user, password: 'Password1!', account: account, role: :administrator) }
  let(:business_agent) { create(:user, password: 'Password1!', account: account, role: :agent) }

  def set_toggle(key, value)
    config = InstallationConfig.where(name: key).first_or_initialize
    config.value = value
    config.locked = false
    config.save!
    GlobalConfig.clear_cache
  end

  def bloomwire_mode(value)
    set_toggle('BLOOMWIRE_MODE_ENABLED', value)
  end

  before { GlobalConfig.clear_cache }

  describe 'console access when Bloomwire Mode is ON' do
    before { bloomwire_mode(true) }

    it 'blocks a business account administrator (no :super_admin scope)' do
      sign_in(business_admin, scope: :user)
      get '/super_admin/bloomwire_config'
      expect(response).to have_http_status(:redirect)
      expect(response.redirect_url).to include('/super_admin/sign_in')
    end

    it 'blocks a business agent (no :super_admin scope)' do
      sign_in(business_agent, scope: :user)
      get '/super_admin/bloomwire_config'
      expect(response).to have_http_status(:redirect)
      expect(response.redirect_url).to include('/super_admin/sign_in')
    end

    it 'blocks an accidental SuperAdmin that has no platform approval' do
      sign_in(unapproved_admin, scope: :super_admin)
      get '/super_admin/bloomwire_config'
      expect(response).to have_http_status(:redirect)
      expect(response.redirect_url).to include('/super_admin/sign_in')
    end

    it 'blocks an unapproved SuperAdmin on every direct /super_admin URL' do
      sign_in(unapproved_admin, scope: :super_admin)
      ['/super_admin', '/super_admin/users', '/super_admin/accounts', '/super_admin/bloomwire_config'].each do |path|
        get path
        expect(response).to have_http_status(:redirect), "expected #{path} to be blocked"
      end
    end

    it 'allows an approved Bloomwire platform admin' do
      sign_in(approved_admin, scope: :super_admin)
      get '/super_admin/bloomwire_config'
      expect(response).to have_http_status(:success)
    end

    it 'allows access via a bootstrap-allowlisted email when the table is empty' do
      admin = create(:super_admin, :unapproved_platform_admin)
      with_modified_env BLOOMWIRE_BOOTSTRAP_PLATFORM_ADMIN_EMAILS: admin.email do
        sign_in(admin, scope: :super_admin)
        get '/super_admin/bloomwire_config'
        expect(response).to have_http_status(:success)
      end
    end

    it 'leaks no secrets in the denial redirect target' do
      sign_in(unapproved_admin, scope: :super_admin)
      get '/super_admin/users'
      follow_redirect!
      expect(response.body).not_to match(/api_key|access_token|provider_config|verify_token|app_secret|Bearer\s/i)
    end
  end

  describe 'console access when Bloomwire Mode is OFF (stock Chatwoot)' do
    before { bloomwire_mode(false) }

    it 'allows any SuperAdmin without a platform approval' do
      sign_in(unapproved_admin, scope: :super_admin)
      get '/super_admin/users'
      expect(response).to have_http_status(:success)
    end
  end

  describe 'login path (sessions#create)' do
    it 'fails for tenant user credentials (STI-scoped lookup)' do
      bloomwire_mode(true)
      post '/super_admin/sign_in', params: { super_admin: { email: business_admin.email, password: 'Password1!' } }
      expect(response).to have_http_status(:redirect)
      expect(response.redirect_url).to include('/super_admin/sign_in')
    end

    it 'refuses login for an unapproved SuperAdmin when Mode ON (no session established)' do
      bloomwire_mode(true)
      post '/super_admin/sign_in', params: { super_admin: { email: unapproved_admin.email, password: 'Password1!' } }
      expect(response).to have_http_status(:redirect)
      expect(response.redirect_url).to include('/super_admin/sign_in')

      get '/super_admin/users'
      expect(response).to have_http_status(:redirect)
    end

    it 'signs in an approved platform admin when Mode ON' do
      bloomwire_mode(true)
      post '/super_admin/sign_in', params: { super_admin: { email: approved_admin.email, password: 'Password1!' } }
      expect(response).to redirect_to(super_admin_users_path)
    end
  end

  describe 'Sidekiq / monitoring mount' do
    it 'is not reachable for an unapproved SuperAdmin when Mode ON' do
      bloomwire_mode(true)
      sign_in(unapproved_admin, scope: :super_admin)
      get '/monitoring/sidekiq'
      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'crafted params cannot escalate a customer/business user' do
    it 'drops users.type on a tenant profile update' do
      user = create(:user, account: account, role: :administrator)
      put '/api/v1/profile',
          params: { profile: { display_name: 'Hacker', type: 'SuperAdmin' } },
          headers: user.create_new_auth_token, as: :json
      expect(response).to have_http_status(:success)

      user.reload
      expect(user.type).to be_nil
      expect(SuperAdmin.exists?(id: user.id)).to be(false)
      expect(Bloomwire::PlatformAdmin.approved?(user)).to be(false)
    end

    it 'a SuperAdmin minted via the Users page has NO platform access without an approval row' do
      bloomwire_mode(true)
      sign_in(approved_admin, scope: :super_admin)
      expect do
        post '/super_admin/users',
             params: { user: { name: 'Ops Two', email: "ops2-#{SecureRandom.hex(4)}@bloomwire.local",
                               password: 'Password1!', type: 'SuperAdmin' } }
      end.to change(SuperAdmin, :count).by(1)

      minted = SuperAdmin.order(:id).last
      expect(Bloomwire::PlatformAdmin.approved?(minted)).to be(false)
    end
  end

  describe 'S3 provisioned users remain normal Users with no platform access' do
    it 'creates the owner and agent as type=nil and not platform admins' do
      result = Bloomwire::CustomerProvisioningService.new(
        account_name: 'Aroma Flora',
        owner_email: "owner-#{SecureRandom.hex(4)}@example.com",
        owner_name: 'Flora Owner',
        agent_emails: "agent-#{SecureRandom.hex(4)}@example.com",
        display_phone_number: '15551239999',
        phone_number_id: "PNID-#{SecureRandom.hex(4)}",
        business_account_id: "WABA-#{SecureRandom.hex(4)}"
      ).perform

      [result[:owner], *result[:agents]].each do |user|
        expect(user.type).to be_nil
        expect(SuperAdmin.exists?(id: user.id)).to be(false)
        expect(Bloomwire::PlatformAdmin.approved?(user)).to be(false)
      end
    end
  end
end
