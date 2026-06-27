# Phase 11B.3: guard that blocks business/customer account users (admins AND agents) from external
# provider/channel setup flows (Facebook page register/reauthorize, Twilio channel create, provider OAuth
# authorizations, Shopify connect) when Bloomwire provider-setup restriction is ON (BLOOMWIRE_MODE_ENABLED +
# BLOOMWIRE_RESTRICT_PROVIDER_SETUP). In managed mode these flows are owned by Bloomwire Ops/SuperAdmin, which
# operate via the separate /super_admin Devise surface (unaffected). OFF => stock Chatwoot.
#
# Wire it as the first controller before_action (it still runs after the inherited authenticate_user!, so
# unauthenticated callers keep getting 401). It then fires uniformly for any authenticated account user before
# the controller's own authorization — so endpoints that are only authentication-gated in stock (Facebook
# callbacks, Shopify auth) also block agents. Returns 403 with a non-secret message; reads/echoes no secrets,
# tokens, or provider ids.
module Bloomwire::RestrictsProviderSetup
  extend ActiveSupport::Concern

  private

  def restrict_provider_setup!
    return unless Bloomwire::Features.restrict_provider_setup?

    render_provider_setup_restricted
  end

  # Scoped, admin-gated variant for mixed controllers (e.g. inboxes) that also serve safe/core channels.
  # The including controller overrides `external_provider_channel_setup_request?` to mark ONLY the
  # external-credential channel create/update requests that must be blocked; web_widget/api/core paths and
  # WhatsApp (which keeps its own native guard) stay untouched. Agents remain on the controller's existing
  # policy (admin-only) — the business administrator is the locked-down actor here.
  def restrict_external_provider_channel_setup!
    return unless Bloomwire::Features.restrict_provider_setup?
    return unless @current_account_user&.administrator?
    return unless external_provider_channel_setup_request?

    render_provider_setup_restricted
  end

  # Default: not an external-credential channel setup request. Mixed controllers override this.
  def external_provider_channel_setup_request?
    false
  end

  # Admin-gated guard for mixed controllers whose specific WRITE actions are integration/provider connect,
  # scoped via `only:` at the call site (e.g. integration hooks create/update, Slack connect/update, WhatsApp
  # webhook re-registration). Blocks the business administrator on those actions; agents stay on the
  # controller's existing admin-only policy/auth path (unchanged). OFF => stock.
  def restrict_provider_setup_for_account_admin!
    return unless Bloomwire::Features.restrict_provider_setup?
    return unless @current_account_user&.administrator?

    render_provider_setup_restricted
  end

  # Scoped, admin-gated guard for DESTROYING an Ops-owned managed/provider inbox (Phase 11B.5B). The including
  # controller overrides `managed_provider_inbox_destroy?` to mark ONLY the channel types whose lifecycle is
  # Ops-owned in managed mode; self-service inboxes (web_widget/api) stay deletable and agents remain on the
  # controller's existing admin-only InboxPolicy#destroy? path. Short-circuits before any delete is enqueued.
  def restrict_managed_provider_inbox_destroy!
    return unless Bloomwire::Features.restrict_provider_setup?
    return unless @current_account_user&.administrator?
    return unless managed_provider_inbox_destroy?

    render_provider_setup_restricted
  end

  # Default: not a managed/provider inbox destroy. Mixed controllers (e.g. inboxes) override this.
  def managed_provider_inbox_destroy?
    false
  end

  def render_provider_setup_restricted
    render json: { error: I18n.t('bloomwire.provider_setup_restricted'), managed_by_ops: true }, status: :forbidden
  end
end
