FactoryBot.define do
  factory :bloomwire_platform_admin, class: 'Bloomwire::PlatformAdmin' do
    association :user, factory: :super_admin, bloomwire_platform_admin_approved: false
    role { :admin }
    enabled { true }
    approved_at { Time.current }

    trait :disabled do
      enabled { false }
    end

    trait :revoked do
      revoked_at { Time.current }
    end
  end
end
