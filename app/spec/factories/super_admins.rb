FactoryBot.define do
  factory :super_admin do
    name { Faker::Name.name }
    email { "admin@#{SecureRandom.uuid}.com" }
    password { 'Password1!' }
    type { 'SuperAdmin' }
    confirmed_at { Time.zone.now }

    # Phase 15A (ADR-0007): a SuperAdmin must ALSO be an approved Bloomwire platform admin to use /super_admin
    # when Bloomwire Mode is ON. Default to approved so existing Mode-ON super-admin specs stay green; use the
    # :unapproved_platform_admin trait to test the boundary (identity without authorization).
    transient do
      bloomwire_platform_admin_approved { true }
    end

    trait :unapproved_platform_admin do
      bloomwire_platform_admin_approved { false }
    end

    after(:create) do |user, evaluator|
      Bloomwire::PlatformAdmin.grant!(user: user) if evaluator.bloomwire_platform_admin_approved
    end
  end
end
