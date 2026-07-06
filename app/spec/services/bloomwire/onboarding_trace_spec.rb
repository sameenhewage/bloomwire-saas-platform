require 'rails_helper'

# The onboarding trace writes ONE sanitized structured-JSON line to the app log. It must never emit a sensitive
# value, never accept an unknown event, and never raise (tracing can't break onboarding).
RSpec.describe Bloomwire::OnboardingTrace do
  let(:allowed_payload_keys) do
    %w[
      tag onboarding_attempt_id account_id actor_user_id mode event result elapsed_ms http_status error_code
      source build_sha ts
    ]
  end

  def capture_log
    logged = nil
    allow(Rails.logger).to receive(:info) { |msg| logged = msg }
    yield
    logged
  end

  def parse(line)
    JSON.parse(line.sub("#{described_class::LOG_TAG} ", ''))
  end

  it 'writes one sanitized structured line for an allow-listed event' do
    line = capture_log do
      described_class.emit(attempt_id: 'att-abc-123456', account_id: 7, actor_id: 9,
                           event: 'onboarding_started', source: 'browser', result: 'started', elapsed_ms: 12)
    end

    expect(line).to start_with(described_class::LOG_TAG)
    payload = parse(line)
    expect(payload).to include(
      'onboarding_attempt_id' => 'att-abc-123456', 'account_id' => 7, 'actor_user_id' => 9,
      'mode' => 'coexistence', 'event' => 'onboarding_started', 'source' => 'browser',
      'result' => 'started', 'elapsed_ms' => 12
    )
  end

  it 'emits only allow-listed payload keys (no arbitrary keys can appear)' do
    line = capture_log do
      described_class.emit(attempt_id: 'att-abc-123456', account_id: 7, actor_id: 9,
                           event: 'create_request_failed', source: 'controller', http_status: 422, error_code: 'http_422')
    end
    expect(parse(line).keys - allowed_payload_keys).to be_empty
  end

  it 'rejects an unknown/arbitrary event and logs nothing' do
    expect(Rails.logger).not_to receive(:info)
    expect(described_class.emit(event: 'evil_event', source: 'browser', attempt_id: 'att-abc-123456')).to be(false)
  end

  it 'rejects an unknown source' do
    expect(described_class.emit(event: 'onboarding_started', source: 'hacker', attempt_id: 'att-abc-123456')).to be(false)
  end

  it 'never emits a sensitive value even if one is passed in the fields hash' do
    line = capture_log do
      described_class.emit(
        attempt_id: 'att-abc-123456', account_id: 7, actor_id: 9, event: 'onboarding_started', source: 'browser',
        code: 'SECRET-AUTH-CODE', access_token: 'SECRET-TOKEN', phone_number_id: '15551230001',
        waba_id: 'WABA-SECRET', business_id: 'BIZ-SECRET'
      )
    end
    aggregate_failures do
      expect(line).not_to include('SECRET-AUTH-CODE')
      expect(line).not_to include('SECRET-TOKEN')
      expect(line).not_to include('15551230001')
      expect(line).not_to include('WABA-SECRET')
      expect(line).not_to include('BIZ-SECRET')
    end
  end

  it 'sanitizes an out-of-range http_status and a malformed error_code' do
    line = capture_log do
      described_class.emit(attempt_id: 'att-abc-123456', account_id: 1, actor_id: 1, event: 'create_request_failed',
                           source: 'controller', http_status: 9999, error_code: 'BAD CODE ;; with spaces')
    end
    payload = parse(line)
    expect(payload).not_to have_key('http_status') # out of range -> dropped
    expect(payload['error_code']).to eq('invalid_code')
  end

  it 'drops a malformed attempt id rather than logging it verbatim' do
    line = capture_log do
      described_class.emit(attempt_id: 'bad id with spaces!!', account_id: 1, actor_id: 1,
                           event: 'onboarding_started', source: 'browser')
    end
    expect(parse(line)).not_to have_key('onboarding_attempt_id')
  end

  it 'never raises even if the logger itself fails' do
    allow(Rails.logger).to receive(:info).and_raise(StandardError, 'log down')
    allow(Rails.logger).to receive(:warn)
    expect do
      described_class.emit(attempt_id: 'att-abc-123456', account_id: 1, actor_id: 1,
                           event: 'onboarding_started', source: 'browser')
    end.not_to raise_error
  end
end
