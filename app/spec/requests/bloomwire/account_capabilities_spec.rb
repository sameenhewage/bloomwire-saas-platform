require 'rails_helper'

# Phase 11B.6B: the account payload (GET /api/v1/accounts/:id) exposes a non-secret, server-derived
# `bloomwire_capabilities` map (camelCase boolean DTO) so the dashboard can hide controls that the backend
# already blocks. It NEVER exposes raw BLOOMWIRE_* toggle names/values — only derived capability booleans,
# computed from the master-gated Bloomwire::Features + the requesting account_user's role. OFF == stock
# (everything true for an administrator).
RSpec.describe 'Bloomwire account capabilities payload', type: :request do
  let(:account) { create(:account) }
  let!(:administrator) { create(:user, account: account, role: :administrator) }
  let!(:agent) { create(:user, account: account, role: :agent) }

  def set_toggle(key, value)
    config = InstallationConfig.where(name: key).first_or_initialize
    config.value = value
    config.locked = false
    config.save!
    GlobalConfig.clear_cache
  end

  def caps_for(user)
    get "/api/v1/accounts/#{account.id}", headers: user.create_new_auth_token, as: :json
    response.parsed_body['bloomwire_capabilities']
  end

  before { GlobalConfig.clear_cache }

  describe 'payload shape' do
    it 'includes bloomwire_capabilities with the derived capability booleans' do
      caps = caps_for(administrator)
      expect(caps).to be_a(Hash)
      expect(caps.keys).to match_array(%w[
                                         canManageAccountControlPlane canManageProviderSetup
                                         canManageNativeWhatsappSetup canDeleteManagedProviderInbox
                                         canRegisterProviderWebhook canCreateInbox
                                       ])
      expect(caps.values).to all(be_in([true, false]))
    end

    it 'never exposes raw BLOOMWIRE_* toggle names or values' do
      set_toggle('BLOOMWIRE_MODE_ENABLED', true)
      set_toggle('BLOOMWIRE_RESTRICT_ACCOUNT_ADMIN', true)
      get "/api/v1/accounts/#{account.id}", headers: administrator.create_new_auth_token, as: :json
      expect(response.body).not_to include('BLOOMWIRE_')
      expect(response.parsed_body['bloomwire_capabilities'].keys).to all(start_with('can'))
    end
  end

  describe 'when Bloomwire account-admin restriction is ON' do
    before do
      set_toggle('BLOOMWIRE_MODE_ENABLED', true)
      set_toggle('BLOOMWIRE_RESTRICT_ACCOUNT_ADMIN', true)
    end

    it 'reports canManageAccountControlPlane=false for a business admin' do
      expect(caps_for(administrator)['canManageAccountControlPlane']).to be(false)
    end
  end

  describe 'when Bloomwire provider-setup restriction is ON (11B.7C)' do
    before do
      set_toggle('BLOOMWIRE_MODE_ENABLED', true)
      set_toggle('BLOOMWIRE_RESTRICT_PROVIDER_SETUP', true)
    end

    it 'reports canCreateInbox=false for a business admin' do
      expect(caps_for(administrator)['canCreateInbox']).to be(false)
    end

    it 'reports canCreateInbox=false for an agent' do
      expect(caps_for(agent)['canCreateInbox']).to be(false)
    end
  end

  describe 'when Bloomwire is OFF (stock) — canCreateInbox' do
    it 'reports canCreateInbox=true for a business admin' do
      expect(caps_for(administrator)['canCreateInbox']).to be(true)
    end
  end

  describe 'when Bloomwire is OFF (stock)' do
    it 'reports canManageAccountControlPlane=true for a business admin' do
      expect(caps_for(administrator)['canManageAccountControlPlane']).to be(true)
    end

    it 'reports canManageAccountControlPlane=true when master is ON but the restrict toggle is OFF' do
      set_toggle('BLOOMWIRE_MODE_ENABLED', true) # master only; restrict toggle stays OFF
      expect(caps_for(administrator)['canManageAccountControlPlane']).to be(true)
    end
  end

  describe 'agent role' do
    it 'reports account-control capability false for an agent (regardless of toggle)' do
      expect(caps_for(agent)['canManageAccountControlPlane']).to be(false)
    end
  end
end
