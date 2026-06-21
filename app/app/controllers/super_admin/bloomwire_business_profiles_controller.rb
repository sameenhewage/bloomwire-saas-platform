class SuperAdmin::BloomwireBusinessProfilesController < SuperAdmin::ApplicationController
  # Administrate provides the index and show actions.
  # Routes are restricted to :index and :show, so this slice is list/show only.
  #
  # See https://administrate-prototype.herokuapp.com/customizing_controller_actions
  # for more information on customizing controller actions.

  # Preload onboarding steps and each account's inboxes so the onboarding progress
  # and Chatwoot readiness columns do not trigger N+1 queries while rendering the
  # list/show pages.
  def scoped_resource
    super.includes(:onboarding_steps, account: :inboxes)
  end
end
