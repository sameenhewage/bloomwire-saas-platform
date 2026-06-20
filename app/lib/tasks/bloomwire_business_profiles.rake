namespace :bloomwire do
  namespace :business_profiles do
    desc 'Backfill a BloomwireBusinessProfile for every account missing one (idempotent)'
    task backfill: :environment do
      result = Bloomwire::BusinessProfileBackfill.new.perform
      Rails.logger.info(
        "[bloomwire:business_profiles:backfill] created=#{result.created} " \
        "skipped=#{result.skipped} total=#{result.total}"
      )
      puts 'Bloomwire business profile backfill complete: ' \
           "created=#{result.created} skipped=#{result.skipped} total=#{result.total}"
    end
  end
end
