require 'rails_helper'

# TEMPORARY (Phase 5 diagnostic) spec — remove with the instrumentation. Proves the flag-gated, DEV-only
# runtime-token debug logs ONLY allow-listed, secret-free fields (never the token/app secret/body), reports the
# management/messaging scope + target-WABA inclusion booleans, and is fully non-fatal. Fake values only.
RSpec.describe Bloomwire::WhatsappRuntimeTokenDebug do
  subject(:diagnostic) { described_class.new(client: client, token: token, selected_waba_id: selected_waba_id) }

  let(:client) { instance_double(Whatsapp::FacebookApiClient) }
  let(:token) { 'EXACT-RUNTIME-TOKEN' }
  let(:selected_waba_id) { '1029255689498274' }
  let(:app_secret_marker) { 'SUPER-SECRET-APP-SECRET' }

  let(:debug_payload) do
    {
      'data' => {
        'app_id' => '1010595458018764',
        'type' => 'USER',
        'application' => 'Bloomwire',
        'data_access_expires_at' => 1_790_000_000,
        'expires_at' => 1_783_470_000,
        'is_valid' => true,
        'scopes' => %w[whatsapp_business_management whatsapp_business_messaging public_profile],
        'granular_scopes' => [
          { 'scope' => 'whatsapp_business_management', 'target_ids' => ['1029255689498274'] },
          { 'scope' => 'whatsapp_business_messaging', 'target_ids' => %w[1029255689498274 555000111] }
        ],
        'user_id' => '61591901843869'
      }
    }
  end

  def captured_logs
    messages = []
    allow(Rails.logger).to receive(:warn) { |msg| messages << msg }
    yield
    messages.join("\n")
  end

  def logged_event(&)
    JSON.parse(captured_logs(&).sub('[BLOOMWIRE EMBEDDED SIGNUP] ', ''))
  end

  describe '.enabled?' do
    it 'is OFF by default' do
      allow(GlobalConfigService).to receive(:load).with(described_class::FLAG, false).and_return(false)
      expect(described_class.enabled?).to be(false)
    end

    it 'is ON when the flag is truthy' do
      allow(GlobalConfigService).to receive(:load).with(described_class::FLAG, false).and_return('true')
      expect(described_class.enabled?).to be(true)
    end

    it 'is hard-blocked on a production-labelled deployment even when the flag is on' do
      allow(GlobalConfigService).to receive(:load).with(described_class::FLAG, false).and_return('true')
      with_modified_env('BLOOMWIRE_ENV' => 'production') do
        expect(described_class.enabled?).to be(false)
      end
    end
  end

  describe '#log' do
    it 'introspects the EXACT exchanged runtime token' do
      expect(client).to receive(:debug_token).with('EXACT-RUNTIME-TOKEN').and_return(debug_payload)
      allow(Rails.logger).to receive(:warn)
      diagnostic.log
    end

    it 'logs the allow-listed identity/scope fields' do
      allow(client).to receive(:debug_token).and_return(debug_payload)
      event = logged_event { diagnostic.log }
      aggregate_failures do
        expect(event['event']).to eq('bloomwire.whatsapp.runtime_token_debug')
        expect(event['app_id']).to eq('1010595458018764')
        expect(event['token_type']).to eq('USER')
        expect(event['is_valid']).to be(true)
        expect(event['expires_at']).to eq(1_783_470_000)
        expect(event['data_access_expires_at']).to eq(1_790_000_000)
        expect(event['scopes']).to include('whatsapp_business_management', 'whatsapp_business_messaging')
        expect(event['granular_scopes'])
          .to include('scope' => 'whatsapp_business_management', 'target_ids' => ['1029255689498274'])
      end
    end

    it 'reports management/messaging presence and target-WABA inclusion as booleans' do
      allow(client).to receive(:debug_token).and_return(debug_payload)
      event = logged_event { diagnostic.log }
      aggregate_failures do
        expect(event['management_scope_present']).to be(true)
        expect(event['messaging_scope_present']).to be(true)
        expect(event['selected_waba_in_management_targets']).to be(true)
        expect(event['selected_waba_in_messaging_targets']).to be(true)
      end
    end

    it 'never writes the runtime token value to the log' do
      allow(client).to receive(:debug_token).and_return(debug_payload)
      expect(captured_logs { diagnostic.log }).not_to include('EXACT-RUNTIME-TOKEN')
    end

    context 'when the token lacks management scope and the target WABA' do
      let(:debug_payload) do
        {
          'data' => {
            'app_id' => '1010595458018764', 'type' => 'USER', 'is_valid' => true,
            'scopes' => %w[whatsapp_business_messaging public_profile],
            'granular_scopes' => [
              { 'scope' => 'whatsapp_business_messaging', 'target_ids' => ['555000111'] }
            ]
          }
        }
      end

      it 'reports the missing scope and missing target explicitly' do
        allow(client).to receive(:debug_token).and_return(debug_payload)
        event = logged_event { diagnostic.log }
        aggregate_failures do
          expect(event['management_scope_present']).to be(false)
          expect(event['selected_waba_in_management_targets']).to be(false)
          expect(event['messaging_scope_present']).to be(true)
          expect(event['selected_waba_in_messaging_targets']).to be(false)
        end
      end
    end

    context 'when debug_token fails' do
      it 'logs a safe failure event without exposing the token, app secret, or body' do
        allow(client).to receive(:debug_token)
          .and_raise(RuntimeError.new("Token validation failed: {\"access_token\":\"EXACT-RUNTIME-TOKEN\",\"x\":\"#{app_secret_marker}\"}"))
        raw = captured_logs { diagnostic.log }
        aggregate_failures do
          expect(raw).to include('bloomwire.whatsapp.runtime_token_debug')
          expect(raw).to include('"error":true')
          expect(raw).to include('RuntimeError')
          expect(raw).not_to include('EXACT-RUNTIME-TOKEN')
          expect(raw).not_to include(app_secret_marker)
        end
      end

      it 'never raises into the caller' do
        allow(client).to receive(:debug_token).and_raise(StandardError)
        expect { diagnostic.log }.not_to raise_error
      end
    end
  end
end
