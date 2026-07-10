## we had instances where after copy pasting the schedule block,
## the dev forgets to changes the schedule key,
## this would break some of the scheduled jobs with out explicit errors
require 'rails_helper'

RSpec.context 'with valid schedule.yml' do
  let(:file) { Rails.root.join('config/schedule.yml') }

  it 'does not have duplicates' do
    schedule_keys = []
    invalid_line_starts = [' ', '#', "\n"]
    # couldn't figure out a proper solution with yaml.parse
    # so the rudementary solution is to read the file and parse it
    # check for duplicates in the array
    File.open(file).each do |f|
      f.each_line do |line|
        next if invalid_line_starts.include?(line[0])

        schedule_keys << line.split(':')[0]
      end
    end
    # ensure that no duplicates exist
    expect(schedule_keys.count).to eq(schedule_keys.uniq.count)
  end

  it 'registers the WhatsApp onboarding recovery sweep exactly once' do
    schedule = YAML.safe_load_file(file)
    recovery_entries = schedule.values.select do |entry|
      entry['class'] == 'Bloomwire::WhatsappOnboardingSweepJob'
    end

    expect(recovery_entries).to contain_exactly(
      include('cron' => '*/1 * * * *', 'queue' => 'scheduled_jobs')
    )
  end
end
