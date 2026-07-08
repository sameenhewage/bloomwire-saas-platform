require 'rails_helper'

# TEMPORARY (Stage 1 controlled register-PIN test) spec — REMOVE together with the override once the one-attempt
# evidence is captured. Proves the DEV-only, EXACT-TARGET, ONE-SHOT Cloud API /register PIN override:
#   - returns the known WhatsAway source constant ONLY for the exact DEV target while armed, and consumes the arm
#     (one-shot) so a second attempt cannot reuse it;
#   - returns nil (so the caller keeps the existing random-PIN behavior) when disarmed, once the arm window has
#     expired (auto-timeout), for any other phone/WABA, and on any production-labelled deployment (hard block).
# Known/fake values only; never asserts on a real token/secret.
RSpec.describe Bloomwire::WhatsappRegistrationPinOverride do
  let(:target_waba) { described_class::TARGET_WABA_ID }
  let(:target_pnid) { described_class::TARGET_PHONE_NUMBER_ID }

  # Stub the (Redis-cached) flag read so gating tests do not depend on cache timing.
  def stub_flag(value)
    allow(GlobalConfigService).to receive(:load).with(described_class::FLAG, nil).and_return(value)
  end

  def armed_value
    5.minutes.from_now.iso8601
  end

  describe '.pin_for' do
    context 'when armed for the exact DEV target' do
      before do
        stub_flag(armed_value)
        allow(described_class).to receive(:consume!).and_return(true)
      end

      it 'returns the override constant 123456' do
        with_modified_env('BLOOMWIRE_ENV' => 'development') do
          expect(described_class.pin_for(waba_id: target_waba, phone_number_id: target_pnid)).to eq('123456')
        end
      end

      it 'consumes the arm so a second attempt cannot reuse it (one-shot)' do
        with_modified_env('BLOOMWIRE_ENV' => 'development') do
          described_class.pin_for(waba_id: target_waba, phone_number_id: target_pnid)
        end
        expect(described_class).to have_received(:consume!)
      end
    end

    context 'when disarmed (flag absent)' do
      it 'returns nil so the caller uses a random PIN' do
        stub_flag(nil)
        with_modified_env('BLOOMWIRE_ENV' => 'development') do
          expect(described_class.pin_for(waba_id: target_waba, phone_number_id: target_pnid)).to be_nil
        end
      end
    end

    context 'when the arm window has expired (auto-timeout)' do
      it 'returns nil even for the exact target' do
        stub_flag(1.second.ago.iso8601)
        with_modified_env('BLOOMWIRE_ENV' => 'development') do
          expect(described_class.pin_for(waba_id: target_waba, phone_number_id: target_pnid)).to be_nil
        end
      end
    end

    context 'with a different phone or WABA (armed)' do
      before { stub_flag(armed_value) }

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

    context 'when the deployment is production-labelled (armed, exact target)' do
      it 'never overrides' do
        stub_flag(armed_value)
        with_modified_env('BLOOMWIRE_ENV' => 'production') do
          expect(described_class.pin_for(waba_id: target_waba, phone_number_id: target_pnid)).to be_nil
        end
      end
    end
  end

  describe '.armed?' do
    it 'is armed while the stored expiry is in the future' do
      stub_flag(1.minute.from_now.iso8601)
      expect(described_class.armed?).to be(true)
    end

    it 'is not armed once the stored expiry has passed (auto-timeout)' do
      stub_flag(1.minute.ago.iso8601)
      expect(described_class.armed?).to be(false)
    end

    it 'is not armed for a non-timestamp value (a stray boolean toggle fails closed)' do
      stub_flag('true')
      expect(described_class.armed?).to be(false)
    end

    it 'is not armed when the flag is absent' do
      stub_flag(nil)
      expect(described_class.armed?).to be(false)
    end
  end

  describe '.arm! and .disarm!' do
    it 'arm! stores a future ISO8601 expiry in the flag' do
      described_class.arm!
      config = InstallationConfig.find_by(name: described_class::FLAG)
      aggregate_failures do
        expect(config).to be_present
        expect(Time.zone.parse(config.value)).to be > Time.current
      end
    end

    it 'disarm! removes the flag entirely' do
      described_class.arm!
      described_class.disarm!
      expect(InstallationConfig.find_by(name: described_class::FLAG)).to be_nil
    end
  end

  describe '.consume!' do
    it 'never raises into onboarding if the disarm write fails' do
      allow(described_class).to receive(:disarm!).and_raise(StandardError)
      expect { described_class.consume! }.not_to raise_error
    end
  end
end
