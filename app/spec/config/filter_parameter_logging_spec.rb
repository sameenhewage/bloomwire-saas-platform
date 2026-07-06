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

  # The anchored (exact-key) filters must NOT redact unrelated keys that merely contain "code" / "phone_number".
  it 'leaves unrelated keys visible (error_code / status_code / country_code / verified flags)' do
    filtered = filter.filter(
      'error_code' => 'phone_number_taken',
      'status_code' => 422,
      'country_code' => 'LK',
      'phone_number_verified' => true
    )
    aggregate_failures do
      expect(filtered['error_code']).to eq('phone_number_taken')
      expect(filtered['status_code']).to eq(422)
      expect(filtered['country_code']).to eq('LK')
      expect(filtered['phone_number_verified']).to be(true)
    end
  end
end
