require 'rails_helper'

# Structured, sanitized Graph API error. Proves the safe fields are extracted from a Meta error body and that the
# raw body / request secrets are never surfaced through the safe hash. No real secrets in fixtures.
RSpec.describe Whatsapp::GraphApiError do
  def response_double(body:, code: 400)
    instance_double(HTTParty::Response, body: body, code: code)
  end

  let(:meta_body) do
    { error: { message: '(#100) The parameter is not valid', type: 'OAuthException', code: 100,
               error_subcode: 2_388_004, is_transient: false, fbtrace_id: 'SAFE_TRACE_ID' } }.to_json
  end

  describe '.from_response' do
    subject(:error) { described_class.from_response('Phone registration failed', response_double(body: meta_body)) }

    it 'keeps the legacy message contract (context + raw body) so existing callers/specs are unchanged' do
      expect(error.message).to eq("Phone registration failed: #{meta_body}")
    end

    it 'extracts the allow-listed Meta error fields' do
      aggregate_failures do
        expect(error.http_status).to eq(400)
        expect(error.error_code).to eq(100)
        expect(error.error_subcode).to eq(2_388_004)
        expect(error.error_type).to eq('OAuthException')
        expect(error.is_transient).to be(false)
        expect(error.fbtrace_id).to eq('SAFE_TRACE_ID')
        expect(error.safe_message).to eq('(#100) The parameter is not valid')
      end
    end

    it 'is a StandardError subclass (so existing rescue StandardError paths still catch it)' do
      expect(error).to be_a(StandardError)
    end

    it 'degrades safely to nil fields (except status) when the body is not JSON' do
      err = described_class.from_response('Phone registration failed', response_double(body: 'not json', code: 500))
      aggregate_failures do
        expect(err.http_status).to eq(500)
        expect(err.error_code).to be_nil
        expect(err.error_type).to be_nil
        expect(err.safe_message).to be_nil
      end
    end

    it 'truncates an oversized Meta message so a huge body cannot bloat logs' do
      body = { error: { message: 'x' * 1000, code: 100 } }.to_json
      err = described_class.from_response('Phone registration failed', response_double(body: body))
      expect(err.safe_message.length).to be <= described_class::MAX_MESSAGE_LENGTH
    end
  end

  describe '#to_safe_h' do
    subject(:safe_hash) { described_class.from_response('Phone registration failed', response_double(body: meta_body)).to_safe_h }

    it 'exposes only the sanitized structured fields' do
      expect(safe_hash.keys).to contain_exactly(
        :http_status, :meta_error_code, :meta_error_subcode, :meta_error_type, :is_transient, :fbtrace_id, :meta_error_message
      )
    end

    it 'never includes the raw response body' do
      expect(safe_hash.to_json).not_to include(meta_body)
    end
  end
end
