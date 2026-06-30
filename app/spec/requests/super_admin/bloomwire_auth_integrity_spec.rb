require 'rails_helper'

# Phase 15G.2 (Auth Integrity Hardening): the generic SuperAdmin Users edit flow and the platform-admin
# permission flows must NEVER mutate auth-sensitive user fields (encrypted_password / type / confirmed_at).
# Password changes happen ONLY via the Devise reset flow. Mode ON; fake values only; no secrets/hashes printed.
RSpec.describe 'SuperAdmin Auth Integrity (Phase 15G.2)', type: :request do
  # create(:super_admin) auto-grants an *admin* approval row -> approved for /super_admin (but NOT an owner).
  let(:super_admin) { create(:super_admin) }
  let(:owner) do
    sa = create(:super_admin, :unapproved_platform_admin)
    Bloomwire::PlatformAdmin.grant!(user: sa, role: :owner)
    sa
  end

  # Compare only a SHA-256 fingerprint of the stored hash (never print the hash itself).
  def pw_fingerprint(user)
    Digest::SHA256.hexdigest(user.reload.encrypted_password.to_s)
  end

  before do
    config = InstallationConfig.where(name: 'BLOOMWIRE_MODE_ENABLED').first_or_initialize
    config.value = true
    config.locked = false
    config.save!
    GlobalConfig.clear_cache
  end

  describe 'generic Users edit cannot change the password hash' do
    before { sign_in(super_admin, scope: :super_admin) }

    it 'edits an allowed field (name) and leaves encrypted_password unchanged' do
      target = create(:user, name: 'Before Name', password: 'OriginalPw1!')
      fp = pw_fingerprint(target)

      patch "/super_admin/users/#{target.id}", params: { user: { name: 'After Name' } }

      expect(target.reload.name).to eq('After Name')  # allowed field still updates
      expect(pw_fingerprint(target)).to eq(fp)        # hash unchanged
    end

    it 'IGNORES a forcibly-submitted password/password_confirmation on update' do
      target = create(:user, password: 'OriginalPw1!')
      fp = pw_fingerprint(target)

      patch "/super_admin/users/#{target.id}", params: { user: {
        display_name: 'Edited', password: 'Hacked0verwrite1!', password_confirmation: 'Hacked0verwrite1!'
      } }

      expect(target.reload.display_name).to eq('Edited')                  # allowed field still updates
      expect(pw_fingerprint(target)).to eq(fp)                            # password NOT applied
      expect(target.valid_password?('OriginalPw1!')).to be(true)         # original still works
      expect(target.valid_password?('Hacked0verwrite1!')).to be(false)   # injected password rejected
    end

    it 'does not render a password field on the edit form' do
      target = create(:user)
      get "/super_admin/users/#{target.id}/edit"
      expect(response).to have_http_status(:success)
      doc = Nokogiri::HTML(response.body)
      expect(doc.css('input[type="password"]')).to be_empty
      expect(doc.css('input[name="user[password]"]')).to be_empty
    end

    it 'cannot set confirmed_at via the generic update' do
      target = create(:user)
      patch "/super_admin/users/#{target.id}", params: { user: { display_name: 'Z', confirmed_at: '2020-01-01 00:00:00' } }
      target.reload
      expect(target.display_name).to eq('Z')               # allowed field still updates
      expect(target.confirmed_at&.year).not_to eq(2020)    # injected confirmed_at NOT applied
    end
  end

  describe 'platform-admin permission flows do not touch user auth fields' do
    it 'grant! / soft_revoke! / reactivate! leave encrypted_password, type, confirmed_at unchanged' do
      user = create(:super_admin, :unapproved_platform_admin)
      fp = pw_fingerprint(user)
      type = user.type
      confirmed = user.confirmed_at

      record = Bloomwire::PlatformAdmin.grant!(user: user, role: :admin)
      record.soft_revoke!
      record.reactivate!(role: :admin)

      expect(pw_fingerprint(user)).to eq(fp)
      expect(user.reload.type).to eq(type)
      expect(user.confirmed_at).to eq(confirmed)
    end

    it 'the inviter existing-SuperAdmin flow does not change encrypted_password' do
      existing = create(:super_admin, :unapproved_platform_admin)
      fp = pw_fingerprint(existing)

      result = Bloomwire::PlatformAdminInviter.call(
        actor: owner, email: existing.email, name: existing.name.presence || 'Existing',
        role: 'admin', reason: 'regrant existing'
      )

      expect(result[:created_user]).to be(false)   # existing user -> grant-only path
      expect(pw_fingerprint(existing)).to eq(fp)
    end
  end

  describe 'account role assignment does not touch user auth fields' do
    before { sign_in(super_admin, scope: :super_admin) }

    it 'assigning an account role leaves encrypted_password, type, confirmed_at unchanged' do
      account = create(:account)
      user = create(:user, password: 'OriginalPw1!')
      fp = pw_fingerprint(user)
      type = user.type
      confirmed = user.confirmed_at

      expect do
        post '/super_admin/account_users',
             params: { account_user: { account_id: account.id, user_id: user.id, role: 'administrator' } }
      end.to change(AccountUser, :count).by(1)

      expect(pw_fingerprint(user)).to eq(fp)
      expect(user.reload.type).to eq(type)
      expect(user.confirmed_at).to eq(confirmed)
    end
  end

  describe 'non-owner access behavior unchanged' do
    it 'an approved (non-owner) platform admin can still use the generic Users page' do
      sign_in(super_admin, scope: :super_admin)
      get '/super_admin/users'
      expect(response).to have_http_status(:success)
    end

    it 'a non-owner is still redirected from owner-only Platform Admin management' do
      sign_in(super_admin, scope: :super_admin)
      get '/super_admin/bloomwire_platform_admins'
      expect(response).to have_http_status(:redirect)
    end
  end
end
