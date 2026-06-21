namespace :bloomwire do
  namespace :onboarding do
    desc 'Ensure default onboarding steps for one account: rake bloomwire:onboarding:ensure[ACCOUNT_ID]'
    task :ensure, [:account_id] => :environment do |_task, args|
      result = run_tracker(args[:account_id], :ensure_steps)
      report('ensured', result)
    end

    desc 'Advance onboarding by one step for one account: rake bloomwire:onboarding:advance[ACCOUNT_ID]'
    task :advance, [:account_id] => :environment do |_task, args|
      result = run_tracker(args[:account_id], :advance)
      report('advanced', result)
    end

    def run_tracker(account_id, action)
      abort('Usage: rake bloomwire:onboarding:<ensure|advance>[ACCOUNT_ID]') if account_id.blank?

      Bloomwire::OnboardingStepTracker.new(account_id: account_id).public_send(action)
    end

    def report(verb, result)
      abort("Bloomwire onboarding step tracking failed: #{result.error}") unless result.success

      puts "Bloomwire onboarding #{verb}: " \
           "completed=#{result.completed_steps}/#{result.total_steps} " \
           "current=#{result.current_step || 'none'} " \
           "all_completed=#{result.all_completed} changed=#{result.changed}"
    end
  end
end
