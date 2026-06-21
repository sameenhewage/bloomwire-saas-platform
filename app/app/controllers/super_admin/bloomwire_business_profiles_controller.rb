class SuperAdmin::BloomwireBusinessProfilesController < SuperAdmin::ApplicationController
  # Administrate provides the index and show actions.
  # Routes are restricted to :index and :show, so this slice is list/show only.
  #
  # See https://administrate-prototype.herokuapp.com/customizing_controller_actions
  # for more information on customizing controller actions.

  # Preload onboarding steps so the onboarding progress column does not trigger
  # an N+1 query while rendering the list/show pages.
  def scoped_resource
    super.includes(:onboarding_steps)
  end
end
