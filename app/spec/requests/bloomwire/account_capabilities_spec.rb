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
                                         canRegisterProviderWebhook canCreateInbox canManageBots
                                         canAccessIntegrations canSelfServeManagedWhatsapp
                                         canAccessCategoryAdmin canRemoveInbox
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

    it 'reports canAccessIntegrations=false for a business admin (11B.7E)' do
      expect(caps_for(administrator)['canAccessIntegrations']).to be(false)
    end

    it 'reports canAccessIntegrations=false for an agent (11B.7E)' do
      expect(caps_for(agent)['canAccessIntegrations']).to be(false)
    end
  end

  describe 'when Bloomwire is OFF (stock) — canCreateInbox' do
    it 'reports canCreateInbox=true for a business admin' do
      expect(caps_for(administrator)['canCreateInbox']).to be(true)
    end

    it 'reports canAccessIntegrations=true for a business admin' do
      expect(caps_for(administrator)['canAccessIntegrations']).to be(true)
    end
  end

  describe 'when Bloomwire bot-management restriction is ON (11B.7D)' do
    before do
      set_toggle('BLOOMWIRE_MODE_ENABLED', true)
      set_toggle('BLOOMWIRE_RESTRICT_BOT_MANAGEMENT', true)
    end

    it 'reports canManageBots=false for a business admin' do
      expect(caps_for(administrator)['canManageBots']).to be(false)
    end

    it 'reports canManageBots=false for an agent' do
      expect(caps_for(agent)['canManageBots']).to be(false)
    end
  end

  describe 'when Bloomwire is OFF (stock) — canManageBots' do
    it 'reports canManageBots=true for a business admin' do
      expect(caps_for(administrator)['canManageBots']).to be(true)
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

  # Phase 17C.1 — managed self-serve WhatsApp onboarding (Embedded Signup first). Gated on the explicit
  # managed_whatsapp_onboarding feature (master-gated + privacy-dependent) AND native WhatsApp being restricted.
  describe 'canSelfServeManagedWhatsapp' do
    # Full managed-mode: Bloomwire ON + privacy ON + native restricted + managed onboarding ON.
    def enable_managed_onboarding
      set_toggle('BLOOMWIRE_MODE_ENABLED', true)
      set_toggle('BLOOMWIRE_PRIVACY_HARDENING', true)
      set_toggle('BLOOMWIRE_RESTRICT_NATIVE_WHATSAPP_SETUP', true)
      set_toggle('BLOOMWIRE_MANAGED_WHATSAPP_ONBOARDING', true)
    end

    context 'when native is restricted AND the managed onboarding feature is ON (privacy ON)' do
      before { enable_managed_onboarding }

      it 'is true for a business administrator' do
        expect(caps_for(administrator)['canSelfServeManagedWhatsapp']).to be(true)
      end

      it 'is false for an agent' do
        expect(caps_for(agent)['canSelfServeManagedWhatsapp']).to be(false)
      end

      it 'does not weaken canManageNativeWhatsappSetup or canCreateInbox' do
        caps = caps_for(administrator)
        aggregate_failures do
          expect(caps['canManageNativeWhatsappSetup']).to be(false) # native stays restricted (managed)
          expect(caps['canCreateInbox']).to be(true)                # provider setup not restricted here
        end
      end
    end

    context 'when native is restricted but the managed onboarding feature is OFF' do
      before do
        set_toggle('BLOOMWIRE_MODE_ENABLED', true)
        set_toggle('BLOOMWIRE_PRIVACY_HARDENING', true)
        set_toggle('BLOOMWIRE_RESTRICT_NATIVE_WHATSAPP_SETUP', true)
        # BLOOMWIRE_MANAGED_WHATSAPP_ONBOARDING stays OFF
      end

      it 'is false for an administrator (self-serve feature not enabled)' do
        expect(caps_for(administrator)['canSelfServeManagedWhatsapp']).to be(false)
      end
    end

    context 'when managed onboarding is ON but privacy hardening is OFF (privacy-dependent feature)' do
      before do
        set_toggle('BLOOMWIRE_MODE_ENABLED', true)
        set_toggle('BLOOMWIRE_RESTRICT_NATIVE_WHATSAPP_SETUP', true)
        set_toggle('BLOOMWIRE_MANAGED_WHATSAPP_ONBOARDING', true)
        # BLOOMWIRE_PRIVACY_HARDENING stays OFF => enabled?(:managed_whatsapp_onboarding) is false
      end

      it 'is false for an administrator (managed onboarding is inert without privacy hardening)' do
        expect(caps_for(administrator)['canSelfServeManagedWhatsapp']).to be(false)
      end
    end

    context 'when managed onboarding is ON but native WhatsApp is NOT restricted' do
      before do
        set_toggle('BLOOMWIRE_MODE_ENABLED', true)
        set_toggle('BLOOMWIRE_PRIVACY_HARDENING', true)
        set_toggle('BLOOMWIRE_MANAGED_WHATSAPP_ONBOARDING', true)
        # BLOOMWIRE_RESTRICT_NATIVE_WHATSAPP_SETUP stays OFF
      end

      it 'is false for an administrator (they use the native flow instead)' do
        expect(caps_for(administrator)['canSelfServeManagedWhatsapp']).to be(false)
      end

      it 'keeps canManageNativeWhatsappSetup true for the admin (native not weakened)' do
        expect(caps_for(administrator)['canManageNativeWhatsappSetup']).to be(true)
      end
    end

    context 'when Bloomwire is OFF (stock)' do
      it 'is false for an administrator and leaves native/inbox capabilities at stock (true)' do
        caps = caps_for(administrator)
        aggregate_failures do
          expect(caps['canSelfServeManagedWhatsapp']).to be(false)
          expect(caps['canManageNativeWhatsappSetup']).to be(true)
          expect(caps['canCreateInbox']).to be(true)
        end
      end
    end
  end

  # Phase 17F.1 — administrator-only, READ-ONLY "Categories & Inboxes" overview. Opt-in: master-gated
  # BLOOMWIRE_CATEGORY_ADMIN_UI (NOT privacy-dependent) AND the requester must be an administrator.
  describe 'canAccessCategoryAdmin' do
    context 'when Bloomwire mode + the category admin UI feature are ON' do
      before do
        set_toggle('BLOOMWIRE_MODE_ENABLED', true)
        set_toggle('BLOOMWIRE_CATEGORY_ADMIN_UI', true)
      end

      it 'is true for a business administrator' do
        expect(caps_for(administrator)['canAccessCategoryAdmin']).to be(true)
      end

      it 'is false for an agent' do
        expect(caps_for(agent)['canAccessCategoryAdmin']).to be(false)
      end
    end

    context 'when Bloomwire mode is ON but the category admin UI feature is OFF' do
      before { set_toggle('BLOOMWIRE_MODE_ENABLED', true) }

      it 'is false for an administrator (stock — no overview)' do
        expect(caps_for(administrator)['canAccessCategoryAdmin']).to be(false)
      end
    end

    context 'when Bloomwire is OFF (stock)' do
      it 'is false for an administrator' do
        expect(caps_for(administrator)['canAccessCategoryAdmin']).to be(false)
      end
    end
  end

  # Universal "Remove inbox": an administrator may delete ANY of their own inboxes from the inbox Settings page
  # whenever Bloomwire mode is ON (the former managed/provider destroy restriction is lifted; WhatsApp deletes are
  # Meta-safe). OFF == stock (the inbox-list delete remains the path). Agents are always false.
  describe 'canRemoveInbox' do
    context 'when Bloomwire mode is ON' do
      before { set_toggle('BLOOMWIRE_MODE_ENABLED', true) }

      it 'is true for a business administrator' do
        expect(caps_for(administrator)['canRemoveInbox']).to be(true)
      end

      it 'is false for an agent' do
        expect(caps_for(agent)['canRemoveInbox']).to be(false)
      end
    end

    context 'when Bloomwire is OFF (stock)' do
      it 'is false for an administrator (stock — the inbox-list delete is the path)' do
        expect(caps_for(administrator)['canRemoveInbox']).to be(false)
      end
    end
  end
end
