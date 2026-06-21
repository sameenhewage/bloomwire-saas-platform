# frozen_string_literal: true

FactoryBot.define do
  factory :bloomwire_onboarding_step do
    bloomwire_business_profile
    sequence(:step_key) { |n| "step_#{n}" }
    status { 'pending' }
    position { 0 }
  end
end
