require 'rails_helper'

# Phase 16C: Ops/SuperAdmin "Send activation email" on the WhatsApp setup detail page. Sends Devise
# set-password (reset) instructions to the setup account's ADMINISTRATOR(s) so a provisioned owner can sign in.
# Asserts behavior via Devise `reset_password_sent_at` (no token read), plus authorization, master-OFF
# availability, a safe audit entry, no platform-admin grant, no data mutation, and no secret in the response.
RSpec.describe 'SuperAdmin Bloomwire owner activation', type: :request do
  let(:platform_admin) { create(:super_admin) }                              # approved platform admin (default)
  let(:non_platform_admin) { create(:super_admin, :unapproved_platform_admin) } # identity but NOT authorized
  let(:account) { create(:account) }
  let(:owner) { create(:user) }
  let(:agent) { create(:user) }
  let(:setup) { create(:bloomwire_whatsapp_setup, account: account) }

  def enable_bloomwire_mode!(value: true)
    config = InstallationConfig.where(name: 'BLOOMWIRE_MODE_ENABLED').first_or_initialize
    config.value = value
    config.locked = false
    config.save!
    GlobalConfig.clear_cache
  end

  def activation_path(target = setup)
    "/super_admin/bloomwire_whatsapp_setups/#{target.id}/send_owner_activation"
  end

  before do
    create(:account_user, account: account, user: owner, role: 'administrator')
    create(:account_user, account: account, user: agent, role: 'agent')
    enable_bloomwire_mode!
  end

  describe 'POST send_owner_activation as a platform admin' do
    before { sign_in(platform_admin, scope: :super_admin) }

    it 'sends set-password instructions to the administrator only (never the agent), with a success flash' do
      post activation_path

      expect(response).to redirect_to(super_admin_bloomwire_whatsapp_setup_path(setup))
      expect(flash[:notice]).to match(/activation email sent/i)
      expect(owner.reload.reset_password_sent_at).to be_present
      expect(agent.reload.reset_password_sent_at).to be_nil
    end

    it 'creates NO platform-admin grant, NO new users/account_users, and does NOT change the owner role' do
      expect { post activation_path }
        .to not_change(Bloomwire::PlatformAdmin, :count)
        .and not_change(User, :count)
        .and not_change(AccountUser, :count)

      expect(AccountUser.find_by(account: account, user: owner).role).to eq('administrator')
    end

    it 'writes a safe audit entry — action name only, no auth-sensitive field names' do
      expect { post activation_path }.to change(Bloomwire::AdminAuditLog, :count).by(1)

      log = Bloomwire::AdminAuditLog.order(:id).last
      expect(log.action).to eq('send_owner_activation')
      expect(log.actor_id).to eq(platform_admin.id)
      expect(log.changed_fields + log.blocked_fields)
        .not_to include('password', 'encrypted_password', 'reset_password_token')
    end

    it 'never exposes a reset token / password in the response' do
      post activation_path
      follow_redirect!
      expect(response.body).not_to match(/reset_password_token|encrypted_password|password=/i)
    end

    it 'shows a safe error (no 500) when every send fails' do
      allow(Bloomwire::BusinessOwnerActivator).to receive(:call)
        .and_return(Bloomwire::BusinessOwnerActivator::Result.new(sent_count: 0, error: :send_failed))

      post activation_path
      expect(response).to redirect_to(super_admin_bloomwire_whatsapp_setup_path(setup))
      expect(flash[:error]).to match(/could not send/i)
    end

    it 'shows a safe message and sends nothing when the account has no administrator' do
      no_admin_setup = create(:bloomwire_whatsapp_setup, account: create(:account))
      post activation_path(no_admin_setup)
      expect(flash[:error]).to match(/no business administrator/i)
    end
  end

  describe 'authorization + availability' do
    it 'blocks a non-platform-admin SuperAdmin and sends nothing' do
      sign_in(non_platform_admin, scope: :super_admin)
      post activation_path

      expect(owner.reload.reset_password_sent_at).to be_nil
      expect(response).not_to redirect_to(super_admin_bloomwire_whatsapp_setup_path(setup))
    end

    it 'is unavailable (redirects to root) when Bloomwire mode is OFF' do
      enable_bloomwire_mode!(value: false)
      sign_in(platform_admin, scope: :super_admin)
      post activation_path

      expect(owner.reload.reset_password_sent_at).to be_nil
      expect(response).to redirect_to(super_admin_root_path)
    end

    it 'requires authentication' do
      post activation_path
      expect(owner.reload.reset_password_sent_at).to be_nil
      expect(response).to have_http_status(:redirect)
    end
  end
end
