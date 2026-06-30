require 'rails_helper'

# Phase 16C: Ops-triggered business-owner activation. Sends Devise set-password (reset) instructions to a
# managed account's ADMINISTRATOR user(s) so a provisioned owner can set a password and sign in. Mirrors
# Bloomwire::PlatformAdminInviter#send_password_setup (best-effort, rescued). It must never create/change
# accounts/users/roles, never grant platform admin, and never expose the reset token. We assert behavior via
# Devise's `reset_password_sent_at` (set by `send_reset_password_instructions`), so the test does not depend on
# mailer/ActiveJob delivery mode and never reads a token.
RSpec.describe Bloomwire::BusinessOwnerActivator do
  let(:account) { create(:account) }
  let(:owner) { create(:user) }
  let(:agent) { create(:user) }

  before do
    create(:account_user, account: account, user: owner, role: 'administrator')
    create(:account_user, account: account, user: agent, role: 'agent')
  end

  describe '.call' do
    it 'sends set-password (reset) instructions to administrators only, never agents' do
      result = described_class.call(account: account)

      expect(owner.reload.reset_password_sent_at).to be_present
      expect(agent.reload.reset_password_sent_at).to be_nil
      expect(result.sent_count).to eq(1)
      expect(result.error).to be_nil
    end

    it 'creates/changes NO accounts, users, account_users, or platform-admin grants' do
      expect { described_class.call(account: account) }
        .to not_change(User, :count)
        .and not_change(Account, :count)
        .and not_change(AccountUser, :count)
        .and not_change(Bloomwire::PlatformAdmin, :count)
    end

    it 'returns :no_admin and sends nothing when the account has no administrator' do
      empty = create(:account)
      result = described_class.call(account: empty)

      expect(result.error).to eq(:no_admin)
      expect(result.sent_count).to eq(0)
    end

    it 'returns :no_admin for a nil account (no raise)' do
      expect(described_class.call(account: nil).error).to eq(:no_admin)
    end

    it 'rescues a delivery/SMTP failure (no raise) and reports :send_failed' do
      allow(account).to receive(:administrators).and_return([owner])
      allow(owner).to receive(:send_reset_password_instructions).and_raise(StandardError, 'smtp down')

      result = nil
      expect { result = described_class.call(account: account) }.not_to raise_error
      expect(result.error).to eq(:send_failed)
      expect(result.sent_count).to eq(0)
    end

    it 'never returns a reset token / password (result is sent_count + error only)' do
      result = described_class.call(account: account)
      expect(result.to_h.keys).to match_array(%i[sent_count error])
    end
  end
end
