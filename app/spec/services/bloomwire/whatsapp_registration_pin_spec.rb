require 'rails_helper'

# Resolves the Cloud API /register two-step-verification PIN for a WhatsApp number so an EXISTING number (one that
# already carries a Meta 2SV PIN) is re-registered with its KNOWN pin instead of a fresh random one Meta rejects
# with #133005. Priority: stored (encrypted, reconnect) > configured (server env, per phone_number_id) > generated.
# The PIN is a secret: resolved server-side only, never logged, never returned. Fake values only.
RSpec.describe Bloomwire::WhatsappRegistrationPin do
  subject(:resolution) { described_class.new(account: account, phone_number_id: phone_number_id).resolve }

  let(:account) { create(:account) }
  let(:phone_number_id) { 'PNID-EXISTING' }
  let(:existing_pins_env) { 'BLOOMWIRE_WHATSAPP_EXISTING_REGISTRATION_PINS' }

  describe 'stored encrypted PIN (reconnect reuse)' do
    before do
      setup = create(:bloomwire_whatsapp_setup, :ready_for_webhook, account: account,
                                                                    aligned_phone_number_id: phone_number_id)
      channel = setup.channel_whatsapp
      channel.update!(provider_config: channel.provider_config.merge('verification_pin' => '135790'))
    end

    it 'reuses the stored PIN, marks it known, and never generates a random one' do
      expect(SecureRandom).not_to receive(:random_number)
      aggregate_failures do
        expect(resolution.pin).to eq('135790')
        expect(resolution.source).to eq(:stored)
        expect(resolution).to be_known
      end
    end

    it 'takes priority over a configured env PIN for the same number' do
      with_modified_env(existing_pins_env => { phone_number_id => '999999' }.to_json) do
        expect(described_class.new(account: account, phone_number_id: phone_number_id).resolve.pin).to eq('135790')
      end
    end
  end

  describe 'securely-configured existing PIN (server env, scoped per phone_number_id)' do
    it 'uses the configured PIN for this phone_number_id and marks it known' do
      with_modified_env(existing_pins_env => { 'PNID-EXISTING' => '654321' }.to_json) do
        res = described_class.new(account: account, phone_number_id: 'PNID-EXISTING').resolve
        aggregate_failures do
          expect(res.pin).to eq('654321')
          expect(res.source).to eq(:configured)
          expect(res).to be_known
        end
      end
    end

    it 'does NOT apply a configured PIN to a phone_number_id absent from the map (isolation)' do
      with_modified_env(existing_pins_env => { 'OTHER-PNID' => '654321' }.to_json) do
        res = described_class.new(account: account, phone_number_id: 'PNID-EXISTING').resolve
        aggregate_failures do
          expect(res.pin).not_to eq('654321')
          expect(res.source).to eq(:generated)
        end
      end
    end

    it 'falls back to a generated PIN when the env JSON is malformed (never raises)' do
      with_modified_env(existing_pins_env => 'not-json') do
        expect(described_class.new(account: account, phone_number_id: 'PNID-EXISTING').resolve.source).to eq(:generated)
      end
    end
  end

  describe 'generated PIN (genuinely new number, no known PIN)' do
    it 'generates a fresh random 6-digit PIN and marks it NOT known (so the caller can fail closed on #133005)' do
      aggregate_failures do
        expect(resolution.pin).to match(/\A\d{6}\z/)
        expect(resolution.source).to eq(:generated)
        expect(resolution).not_to be_known
      end
    end
  end
end
