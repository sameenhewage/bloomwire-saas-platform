require 'rails_helper'

# Phase 15G.3 (Auth Go-Live Guardrails): admin edits of user records are audited with field NAMES only —
# never values. Auth-sensitive params that are submitted but stripped (15G.2) are recorded as blocked NAMES.
# Mode ON; fake values only; the audit must never contain a secret value.
RSpec.describe 'SuperAdmin Admin User Audit (Phase 15G.3)', type: :request do
  let(:super_admin) { create(:super_admin) }

  before do
    config = InstallationConfig.where(name: 'BLOOMWIRE_MODE_ENABLED').first_or_initialize
    config.value = true
    config.locked = false
    config.save!
    GlobalConfig.clear_cache
    sign_in(super_admin, scope: :super_admin)
  end

  it 'records one audit row for an allowed-field edit (changed field NAMES only)' do
    target = create(:user, name: 'Before')

    expect do
      patch "/super_admin/users/#{target.id}", params: { user: { name: 'After' } }
    end.to change(Bloomwire::AdminAuditLog, :count).by(1)

    log = Bloomwire::AdminAuditLog.recent.first
    expect(log.actor_id).to eq(super_admin.id)
    expect(log.target_user_id).to eq(target.id)
    expect(log.controller).to eq('super_admin/users')
    expect(log.action).to eq('update')
    expect(log.changed_fields).to include('name')
    expect(log.blocked_fields).to eq([])
  end

  it 'records attempted auth-sensitive params as blocked field NAMES only (not applied, not in changed)' do
    target = create(:user, password: 'OriginalPw1!')
    secret = 'Hacked0verwrite1!'

    patch "/super_admin/users/#{target.id}", params: { user: {
      display_name: 'Edited', password: secret, password_confirmation: secret, confirmed_at: '2020-01-01 00:00:00'
    } }

    log = Bloomwire::AdminAuditLog.recent.first
    expect(log.blocked_fields).to include('password', 'password_confirmation', 'confirmed_at')
    expect(log.changed_fields).to include('display_name')
    expect(log.changed_fields).not_to include('password', 'encrypted_password')
    # And the password was NOT applied (15G.2 still holds)
    expect(target.reload.valid_password?('OriginalPw1!')).to be(true)
  end

  it 'never stores any secret value (password or hash) in the audit row' do
    target = create(:user)
    secret = 'Sup3rSecretValue!xyz'

    patch "/super_admin/users/#{target.id}", params: { user: {
      display_name: 'X', password: secret, password_confirmation: secret
    } }

    log = Bloomwire::AdminAuditLog.recent.first
    serialized = log.attributes.to_json
    expect(serialized).not_to include(secret)                            # no submitted password value
    expect(serialized).not_to include(target.reload.encrypted_password)  # no stored hash value
    # only safe names are present
    expect(log.blocked_fields).to include('password')
  end
end
