namespace :bloomwire do
  namespace :tenant_setup do
    desc 'Initialize Bloomwire tenant setup for one account: rake bloomwire:tenant_setup:initialize[ACCOUNT_ID]'
    task :initialize, [:account_id] => :environment do |_task, args|
      account_id = args[:account_id]
      abort('Usage: rake bloomwire:tenant_setup:initialize[ACCOUNT_ID]') if account_id.blank?

      result = Bloomwire::TenantSetupInitializer.new(account_id: account_id).perform

      if result.success
        puts 'Bloomwire tenant setup initialized: ' \
             "profile_created=#{result.profile_created} " \
             "previous=#{result.previous_onboarding_status} " \
             "current=#{result.current_onboarding_status} changed=#{result.changed}"
      else
        abort("Bloomwire tenant setup failed: #{result.error}")
      end
    end
  end
end
