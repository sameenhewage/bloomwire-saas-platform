# Phase 16C: Ops-triggered business-owner activation. Sends Devise set-password (reset) instructions to a
# managed account's ADMINISTRATOR user(s) so a provisioned business owner can set a password and sign in to the
# native inbox. Mirrors Bloomwire::PlatformAdminInviter#send_password_setup (best-effort, rescued).
#
# Guarantees (do not weaken):
# - Targets account ADMINISTRATORS only (never agents) via the native Account#administrators association.
# - Creates/changes NO accounts/users/account_users/roles and grants NO platform admin — it only enqueues a
#   reset-password email per administrator.
# - NEVER reads, returns, logs, or exposes the reset token/password (Devise stores the token; we touch only the
#   send call). The result carries a count + a safe error symbol — no secrets.
class Bloomwire::BusinessOwnerActivator
  # sent_count: number of administrators a reset email was enqueued for.
  # error: nil on success, :no_admin when the account has no administrator, :send_failed when every send failed.
  Result = Struct.new(:sent_count, :error, keyword_init: true)

  def self.call(account:)
    new(account: account).call
  end

  def initialize(account:)
    @account = account
  end

  def call
    admins = administrators
    return Result.new(sent_count: 0, error: :no_admin) if admins.empty?

    sent = admins.count { |user| send_instructions(user) }
    Result.new(sent_count: sent, error: sent.zero? ? :send_failed : nil)
  end

  private

  def administrators
    return [] if @account.blank?

    @account.administrators.to_a
  end

  # Best-effort: enqueue Devise reset/set-password instructions. A delivery/SMTP failure must NOT raise (mirrors
  # PlatformAdminInviter) so the Ops request never 500s. Returns true on success. The token is generated and
  # stored by Devise internally and is never read here.
  def send_instructions(user)
    user.send_reset_password_instructions
    true
  rescue StandardError => e
    Rails.logger.warn("[bloomwire] owner activation reset-password enqueue failed: #{e.class}")
    false
  end
end
