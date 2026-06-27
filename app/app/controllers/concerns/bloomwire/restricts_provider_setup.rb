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

    render json: { error: I18n.t('bloomwire.provider_setup_restricted'), managed_by_ops: true }, status: :forbidden
  end
end
