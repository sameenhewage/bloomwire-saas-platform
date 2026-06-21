require 'administrate/base_dashboard'

class BloomwireBusinessProfileDashboard < Administrate::BaseDashboard
  # ATTRIBUTE_TYPES
  # a hash that describes the type of each of the model's fields.
  ATTRIBUTE_TYPES = {
    id: Field::Number,
    account: Field::BelongsTo,
    industry: Field::String,
    plan_name: Field::String,
    status: Field::Select.with_options(collection: BloomwireBusinessProfile::STATUSES),
    onboarding_status: Field::Select.with_options(collection: BloomwireBusinessProfile::ONBOARDING_STATUSES),
    onboarding_progress: Field::String.with_options(searchable: false, truncate: 120),
    chatwoot_readiness: Field::String.with_options(searchable: false),
    created_at: Field::DateTime,
    updated_at: Field::DateTime
  }.freeze

  # COLLECTION_ATTRIBUTES
  # an array of attributes that will be displayed on the model's index page.
  COLLECTION_ATTRIBUTES = %i[
    id
    account
    industry
    plan_name
    status
    onboarding_status
    onboarding_progress
    chatwoot_readiness
    created_at
  ].freeze

  # SHOW_PAGE_ATTRIBUTES
  # an array of attributes that will be displayed on the model's show page.
  SHOW_PAGE_ATTRIBUTES = %i[
    id
    account
    industry
    plan_name
    status
    onboarding_status
    onboarding_progress
    chatwoot_readiness
    created_at
    updated_at
  ].freeze

  # FORM_ATTRIBUTES
  # Empty for now: this slice is list/show only, no create/edit/delete UI.
  FORM_ATTRIBUTES = [].freeze

  COLLECTION_FILTERS = {}.freeze

  # Overwrite this method to customize how business profiles are displayed
  # across all pages of the admin dashboard.
  def display_resource(profile)
    profile.account&.name.presence || "Business ##{profile.id}"
  end
end
