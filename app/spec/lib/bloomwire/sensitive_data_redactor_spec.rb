require 'rails_helper'

# Bloomwire Phase 2C: centralized redactor for explicit log/error/debug output. When privacy hardening is
# ON (master AND-gated), sensitive token/secret values are replaced with [FILTERED]; OFF or master-OFF is a
# no-op (stock). Non-mutating. Fake tokens only.
RSpec.describe Bloomwire::SensitiveDataRedactor do
  before { GlobalConfig.clear_cache }

  def set_toggle(key, value)
    config = InstallationConfig.where(name: key).first_or_initialize
    config.value = value
    config.locked = false
    config.save!
    GlobalConfig.clear_cache
  end

  def enable_privacy_hardening
    set_toggle('BLOOMWIRE_MODE_ENABLED', true)
    set_toggle('BLOOMWIRE_PRIVACY_HARDENING', true)
  end

  describe '.redact' do
    context 'when privacy hardening is ON (master + privacy)' do
      before { enable_privacy_hardening }

      it 'replaces a sensitive value with [FILTERED]' do
        expect(described_class.redact({ 'access_token' => 'fake-tok-123' })['access_token']).to eq('[FILTERED]')
      end

      it 'redacts all known token-like keys' do
        input = {
          'access_token' => 'a', 'api_key' => 'b', 'app_secret' => 'c', 'client_secret' => 'd',
          'webhook_verify_token' => 'e', 'Authorization' => 'Bearer x', 'authorization' => 'Bearer y'
        }
        described_class.redact(input).each_value { |v| expect(v).to eq('[FILTERED]') }
      end

      it 'keeps non-sensitive keys intact' do
        out = described_class.redact({ 'phone_number_id' => 'PNID', 'name' => 'Acme', 'api_key' => 'secret' })
        expect(out['phone_number_id']).to eq('PNID')
        expect(out['name']).to eq('Acme')
        expect(out['api_key']).to eq('[FILTERED]')
      end

      it 'redacts nested hashes and arrays without mutating the original' do
        original = { 'outer' => { 'api_key' => 'fake', 'safe' => 'keep' }, 'list' => [{ 'access_token' => 'fake2' }] }
        out = described_class.redact(original)

        expect(out['outer']['api_key']).to eq('[FILTERED]')
        expect(out['outer']['safe']).to eq('keep')
        expect(out['list'][0]['access_token']).to eq('[FILTERED]')

        # original untouched
        expect(original['outer']['api_key']).to eq('fake')
        expect(original['list'][0]['access_token']).to eq('fake2')
      end
    end

    context 'when privacy hardening is OFF (stock)' do
      it 'returns the input unchanged' do
        input = { 'access_token' => 'fake-tok' }
        expect(described_class.redact(input)).to eq(input)
        expect(described_class.redact(input)['access_token']).to eq('fake-tok')
      end
    end

    context 'when privacy hardening is stored ON but master is OFF (AND-gate keeps it stock)' do
      before { set_toggle('BLOOMWIRE_PRIVACY_HARDENING', true) }

      it 'does not redact' do
        expect(described_class.redact({ 'api_key' => 'fake' })['api_key']).to eq('fake')
      end
    end
  end

  describe '.redact_response_body' do
    let(:body) { '{"error":{"message":"bad request","api_key":"fake-resp-key"}}' }
    let(:parsed) { { 'error' => { 'message' => 'bad request', 'api_key' => 'fake-resp-key' } } }
    let(:response) { instance_double(HTTParty::Response, body: body, parsed_response: parsed) }

    context 'when privacy hardening is OFF (stock)' do
      it 'returns the raw response body unchanged' do
        expect(described_class.redact_response_body(response)).to eq(body)
      end
    end

    context 'when privacy hardening is ON' do
      before { enable_privacy_hardening }

      it 'redacts sensitive keys from the parsed body and never emits the raw secret' do
        out = described_class.redact_response_body(response).to_s
        expect(out).not_to include('fake-resp-key')
        expect(out).to include('[FILTERED]')
        expect(out).to include('bad request')
      end
    end
  end
end
