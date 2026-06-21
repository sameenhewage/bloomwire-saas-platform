require 'rails_helper'

RSpec.describe ChatwootHub do
  describe 'ChatwootHub.outbound_disabled?' do
    it 'is true when BLOOMWIRE_DISABLE_CHATWOOT_HUB is set true' do
      with_modified_env BLOOMWIRE_DISABLE_CHATWOOT_HUB: 'true' do
        expect(described_class.outbound_disabled?).to be(true)
      end
    end

    it 'is false when BLOOMWIRE_DISABLE_CHATWOOT_HUB is set false' do
      with_modified_env BLOOMWIRE_DISABLE_CHATWOOT_HUB: 'false' do
        expect(described_class.outbound_disabled?).to be(false)
      end
    end

    it 'defaults to isolated in production when unset' do
      allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new('production'))
      expect(described_class.outbound_disabled?).to be(true)
    end

    it 'defaults to enabled outside production when unset' do
      allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new('development'))
      expect(described_class.outbound_disabled?).to be(false)
    end
  end

  describe 'Internal::CheckNewVersionsJob' do
    before { allow(Rails.env).to receive(:production?).and_return(true) }

    context 'when hub isolation is enabled' do
      it 'does not call ChatwootHub.sync_with_hub' do
        with_modified_env BLOOMWIRE_DISABLE_CHATWOOT_HUB: 'true' do
          allow(described_class).to receive(:sync_with_hub)
          Internal::CheckNewVersionsJob.perform_now
          expect(described_class).not_to have_received(:sync_with_hub)
        end
      end

      it 'does not write the pricing plan from the hub response' do
        with_modified_env BLOOMWIRE_DISABLE_CHATWOOT_HUB: 'true' do
          allow(described_class).to receive(:sync_with_hub).and_return({ 'plan' => 'enterprise', 'plan_quantity' => 5 })
          Internal::CheckNewVersionsJob.perform_now
          expect(InstallationConfig.find_by(name: 'INSTALLATION_PRICING_PLAN')).to be_nil
        end
      end
    end

    context 'when hub isolation is disabled' do
      it 'calls ChatwootHub.sync_with_hub' do
        with_modified_env BLOOMWIRE_DISABLE_CHATWOOT_HUB: 'false' do
          allow(described_class).to receive(:sync_with_hub).and_return({ 'version' => '1.2.3' })
          Internal::CheckNewVersionsJob.perform_now
          expect(described_class).to have_received(:sync_with_hub)
        end
      end
    end
  end

  describe 'ChatwootHub.emit_event' do
    it 'does not POST when hub isolation is enabled' do
      with_modified_env BLOOMWIRE_DISABLE_CHATWOOT_HUB: 'true' do
        allow(RestClient).to receive(:post)
        described_class.emit_event('sample_event', { 'key' => 'value' })
        expect(RestClient).not_to have_received(:post)
      end
    end

    it 'POSTs when hub isolation is disabled' do
      with_modified_env BLOOMWIRE_DISABLE_CHATWOOT_HUB: 'false' do
        allow(RestClient).to receive(:post)
        described_class.emit_event('sample_event', { 'key' => 'value' })
        expect(RestClient).to have_received(:post).with(described_class.events_url, anything, anything)
      end
    end
  end

  describe 'ChatwootHub.send_push' do
    let(:fcm_options) { { token: 'sample-token' } }

    it 'does not POST when hub isolation is enabled' do
      with_modified_env BLOOMWIRE_DISABLE_CHATWOOT_HUB: 'true' do
        allow(RestClient).to receive(:post)
        described_class.send_push(fcm_options)
        expect(RestClient).not_to have_received(:post)
      end
    end

    it 'POSTs when the push relay is explicitly approved despite isolation' do
      with_modified_env BLOOMWIRE_DISABLE_CHATWOOT_HUB: 'true', BLOOMWIRE_ALLOW_CHATWOOT_HUB_PUSH: 'true' do
        allow(RestClient).to receive(:post)
        described_class.send_push(fcm_options)
        expect(RestClient).to have_received(:post).with(described_class.push_notification_url, anything, anything)
      end
    end
  end
end
