require 'rails_helper'

# Guards the request-log parameter filtering for managed WhatsApp onboarding: the Meta authorization code and the
# WhatsApp identifiers/phone must never appear in request-parameter logs.
RSpec.describe 'filter_parameter_logging (managed WhatsApp onboarding)' do # rubocop:disable RSpec/DescribeClass
  let(:filter) { ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters) }

  it 'redacts the Meta auth code and WhatsApp identifiers/phone to [FILTERED]' do
    filtered = filter.filter(
      'code' => 'META-AUTH-CODE-SECRET',
      'auth_code' => 'META-AUTH-CODE-SECRET',
      'access_token' => 'META-ACCESS-TOKEN',
      'business_id' => 'BIZ-SECRET',
      'waba_id' => 'WABA-SECRET',
      'phone_number_id' => '1555000111',
      'display_phone_number' => '+15551230001',
      'phone_number' => '+15551230001'
    )

    aggregate_failures do
      %w[code auth_code access_token business_id waba_id phone_number_id display_phone_number phone_number].each do |key|
        expect(filtered[key]).to eq('[FILTERED]'), "#{key} was not filtered"
      end
      # No raw sensitive value survives anywhere in the filtered hash.
      joined = filtered.values.map(&:to_s).join(' ')
      expect(joined).not_to include('META-AUTH-CODE-SECRET')
      expect(joined).not_to include('META-ACCESS-TOKEN')
      expect(joined).not_to include('WABA-SECRET')
      expect(joined).not_to include('+15551230001')
    end
  end

  it 'preserves website_token (the intentional token-filter exception is not broken)' do
    filtered = filter.filter('website_token' => 'PUBLIC-WIDGET-TOKEN')
    expect(filtered['website_token']).to eq('PUBLIC-WIDGET-TOKEN')
  end
end
