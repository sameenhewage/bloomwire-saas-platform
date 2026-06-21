class SuperAdmin::BloomwireBusinessProfilesController < SuperAdmin::ApplicationController
  # Administrate provides the index and show actions; `activate` is a custom
  # member action — the manual tenant activation gate.
  #
  # See https://administrate-prototype.herokuapp.com/customizing_controller_actions
  # for more information on customizing controller actions.

  # Safe, non-identifying messages for a blocked activation (no raw ids/data).
  ACTIVATION_FAILURE_MESSAGES = {
    profile_not_found: 'Cannot activate: this business has no Bloomwire profile.',
    chatwoot_not_ready: 'Cannot activate: Chatwoot setup is not ready.',
    onboarding_steps_missing: 'Cannot activate: onboarding steps are missing.',
    onboarding_incomplete: 'Cannot activate: onboarding is not complete.'
  }.freeze

  ACTIVATION_NOT_AUTHORIZED = 'Not authorized to activate this tenant.'.freeze

  # Preload onboarding steps and each account's inboxes so the onboarding progress
  # and Chatwoot readiness columns do not trigger N+1 queries while rendering the
  # list/show pages.
  def scoped_resource
    super.includes(:onboarding_steps, account: :inboxes)
  end

  # Manually activate a tenant. Access is backend-enforced by
  # Bloomwire::AccessPolicy (activate_tenant is a platform-level control), and the
  # transition itself is enforced by Bloomwire::TenantActivation: it only succeeds
  # when the tenant is actually ready, and a blocked gate mutates nothing and
  # surfaces a safe reason. It never creates/configures Chatwoot
  # inboxes/channels/webhooks or touches Chatwoot data.
  def activate
    unless Bloomwire::AccessPolicy.new(user: current_super_admin, profile: requested_resource).can?(:activate_tenant)
      return redirect_to [namespace, requested_resource], alert: ACTIVATION_NOT_AUTHORIZED
    end

    result = Bloomwire::TenantActivation.new(requested_resource).activate
    redirect_to [namespace, requested_resource], **activation_flash(result)
  end

  private

  def activation_flash(result)
    return { alert: ACTIVATION_FAILURE_MESSAGES.fetch(result.error) } unless result.success

    { notice: result.already_active ? 'Tenant is already active.' : 'Tenant activated.' }
  end
end
