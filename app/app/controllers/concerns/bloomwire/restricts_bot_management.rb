# Phase 11B.7D: guard that blocks business/customer account users (admins AND agents) from bot management
# when Bloomwire bot-management restriction is ON (BLOOMWIRE_MODE_ENABLED + BLOOMWIRE_RESTRICT_BOT_MANAGEMENT).
# In managed mode bots are owned by Bloomwire Ops/SuperAdmin (separate /super_admin surface, unaffected).
#
# It is NOT admin-gated on purpose: the agent-bot list/show responses expose access_token / secret / bot_config
# (and the inbox agent_bot read renders the same partial), so agents must be blocked too — not just admins.
# Wire it after the controller's own authorization, scoped via `only:` at the call site. Returns 403 with a
# non-secret message; reads/echoes no tokens, secrets, or bot config. OFF => stock Chatwoot.
module Bloomwire::RestrictsBotManagement
  extend ActiveSupport::Concern

  private

  def restrict_bot_management!
    return unless Bloomwire::Features.restrict_bot_management?

    render_bot_management_restricted
  end

  def render_bot_management_restricted
    render json: { error: I18n.t('bloomwire.bot_management_restricted'), managed_by_ops: true }, status: :forbidden
  end
end
