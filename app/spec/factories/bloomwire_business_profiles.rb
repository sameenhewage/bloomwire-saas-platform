# frozen_string_literal: true

FactoryBot.define do
  factory :bloomwire_business_profile do
    account { association(:account, strategy: :create) }
    industry { 'Retail / E-commerce' }
    plan_name { 'Pro' }
    status { 'active' }
    onboarding_status { 'completed' }
  end
end
