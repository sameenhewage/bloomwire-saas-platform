require 'rails_helper'

# TEMPORARY (Stage 1 controlled register-PIN test) spec — REMOVE together with the override once the one-attempt
# evidence is captured. Proves the DEV-only, flag-gated, EXACT-TARGET Cloud API /register PIN override:
#   - returns the known WhatsAway source constant ONLY for the exact DEV target WABA + phone_number_id with the
#     explicit InstallationConfig flag ON, and
#   - returns nil (so the caller keeps the existing random-PIN behavior) for a disabled flag, any other
#     phone/WABA, and any production-labelled deployment (hard block).
# Known/fake values only; never asserts on a real token/secret.
RSpec.describe Bloomwire::WhatsappRegistrationPinOverride do
  let(:target_waba) { described_class::TARGET_WABA_ID }
  let(:target_pnid) { described_class::TARGET_PHONE_NUMBER_ID }

  def stub_flag(value)
    allow(GlobalConfigService).to receive(:load).with(described_class::FLAG, false).and_return(value)
  end

  describe '.pin_for' do
    context 'when it is the exact DEV target with the flag enabled' do
      it 'returns the override constant 123456' do
        stub_flag('true')
        with_modified_env('BLOOMWIRE_ENV' => 'development') do
          expect(described_class.pin_for(waba_id: target_waba, phone_number_id: target_pnid)).to eq('123456')
        end
      end
    end

    context 'when the flag is disabled (default)' do
      it 'returns nil so the caller uses a random PIN' do
        stub_flag(false)
        with_modified_env('BLOOMWIRE_ENV' => 'development') do
          expect(described_class.pin_for(waba_id: target_waba, phone_number_id: target_pnid)).to be_nil
        end
      end
    end

    context 'with a different phone or WABA (flag on)' do
      before { stub_flag('true') }

      it 'does not override a different phone_number_id' do
        with_modified_env('BLOOMWIRE_ENV' => 'development') do
          expect(described_class.pin_for(waba_id: target_waba, phone_number_id: '100000000000000')).to be_nil
        end
      end

      it 'does not override a different WABA' do
        with_modified_env('BLOOMWIRE_ENV' => 'development') do
          expect(described_class.pin_for(waba_id: '200000000000000', phone_number_id: target_pnid)).to be_nil
        end
      end
    end

    context 'when the deployment is production-labelled (flag on, exact target)' do
      it 'never overrides even for the exact target with the flag on' do
        stub_flag('true')
        with_modified_env('BLOOMWIRE_ENV' => 'production') do
          expect(described_class.pin_for(waba_id: target_waba, phone_number_id: target_pnid)).to be_nil
        end
      end
    end
  end
end
