require 'rails_helper'

# Phase 17B: the read-only global WhatsApp config summary. Global secrets are reported present?/missing ONLY —
# their values are never read or returned. The Meta App ID is a public identifier and may be shown. Fake values.
RSpec.describe Bloomwire::GlobalWhatsappConfig do
  def stub_features(master:, router:, privacy: true)
    allow(Bloomwire::Features).to receive(:master_enabled?).and_return(master)
    allow(Bloomwire::Features).to receive(:enabled?).with(:global_webhook_router).and_return(router)
    allow(Bloomwire::Features).to receive(:raw_enabled?).with(:privacy_hardening).and_return(privacy)
  end

  def stub_config(values)
    allow(GlobalConfigService).to receive(:load).and_call_original
    values.each { |k, v| allow(GlobalConfigService).to receive(:load).with(k, nil).and_return(v) }
  end

  describe '#result' do
    context 'when fully configured' do
      before do
        stub_features(master: true, router: true)
        stub_config(
          'WHATSAPP_APP_SECRET' => 'FAKE-APP-SECRET-VALUE',
          'BLOOMWIRE_WHATSAPP_GLOBAL_VERIFY_TOKEN' => 'FAKE-VERIFY-TOKEN-VALUE',
          'BLOOMWIRE_WHATSAPP_PUBLIC_CALLBACK_HOST' => 'chat.example.com',
          'WHATSAPP_APP_ID' => '1234567890',
          'WHATSAPP_CONFIGURATION_ID' => 'CONFIG-ID-1'
        )
      end

      it 'reports secrets as present WITHOUT returning their values' do
        r = described_class.new.result
        expect(r[:app_secret_present]).to be(true)
        expect(r[:verify_token_present]).to be(true)
        expect(r.to_json).not_to include('FAKE-APP-SECRET-VALUE')
        expect(r.to_json).not_to include('FAKE-VERIFY-TOKEN-VALUE')
      end

      it 'builds the callback URL, shows the public App ID, and is platform-ready' do
        r = described_class.new.result
        expect(r[:callback_url]).to eq('https://chat.example.com/bloomwire/webhooks/whatsapp')
        expect(r[:app_id]).to eq('1234567890')
        expect(r[:configuration_id_present]).to be(true)
        expect(r[:router_enabled]).to be(true)
        expect(r[:platform_ready]).to be(true)
        expect(r[:blockers]).to be_empty
      end
    end

    context 'when secrets / host are missing' do
      before do
        stub_features(master: true, router: true)
        stub_config(
          'WHATSAPP_APP_SECRET' => nil,
          'BLOOMWIRE_WHATSAPP_GLOBAL_VERIFY_TOKEN' => nil,
          'BLOOMWIRE_WHATSAPP_PUBLIC_CALLBACK_HOST' => nil,
          'WHATSAPP_APP_ID' => nil
        )
      end

      it 'reports missing (presence false), names blockers, and is not ready' do
        r = described_class.new.result
        expect(r[:app_secret_present]).to be(false)
        expect(r[:verify_token_present]).to be(false)
        expect(r[:callback_url]).to be_nil
        expect(r[:app_id]).to be_nil
        expect(r[:platform_ready]).to be(false)
        expect(r[:blockers]).to include(a_string_matching(/WHATSAPP_APP_ID/),
                                        a_string_matching(/WHATSAPP_APP_SECRET/),
                                        a_string_matching(/GLOBAL_VERIFY_TOKEN/),
                                        a_string_matching(/PUBLIC_CALLBACK_HOST/))
      end
    end

    context 'when only WHATSAPP_APP_ID is missing (Embedded Signup prerequisite)' do
      before do
        stub_features(master: true, router: true)
        stub_config(
          'WHATSAPP_APP_SECRET' => 'FAKE-APP-SECRET-VALUE',
          'BLOOMWIRE_WHATSAPP_GLOBAL_VERIFY_TOKEN' => 'FAKE-VERIFY-TOKEN-VALUE',
          'BLOOMWIRE_WHATSAPP_PUBLIC_CALLBACK_HOST' => 'chat.example.com',
          'WHATSAPP_APP_ID' => nil
        )
      end

      it 'still reports app_id_present and lists it as a blocker, and is not platform-ready' do
        r = described_class.new.result
        expect(r[:app_id_present]).to be(false)
        expect(r[:app_id]).to be_nil
        expect(r[:blockers]).to include(a_string_matching(/WHATSAPP_APP_ID is missing/))
        expect(r[:platform_ready]).to be(false)
      end
    end

    context 'when only WHATSAPP_CONFIGURATION_ID is missing (Embedded Signup prerequisite, Phase 17C.1)' do
      before do
        stub_features(master: true, router: true)
        stub_config(
          'WHATSAPP_APP_SECRET' => 'FAKE-APP-SECRET-VALUE',
          'BLOOMWIRE_WHATSAPP_GLOBAL_VERIFY_TOKEN' => 'FAKE-VERIFY-TOKEN-VALUE',
          'BLOOMWIRE_WHATSAPP_PUBLIC_CALLBACK_HOST' => 'chat.example.com',
          'WHATSAPP_APP_ID' => '1234567890',
          'WHATSAPP_CONFIGURATION_ID' => nil
        )
      end

      it 'reports configuration_id_present false, names it a blocker, and is not platform-ready' do
        r = described_class.new.result
        expect(r[:configuration_id_present]).to be(false)
        expect(r[:blockers]).to include(a_string_matching(/WHATSAPP_CONFIGURATION_ID is missing/))
        expect(r[:platform_ready]).to be(false)
      end
    end

    context 'when WHATSAPP_CONFIGURATION_ID is present' do
      it 'does not add a configuration-id blocker (presence-only, value not required in result)' do
        stub_features(master: true, router: true)
        stub_config('WHATSAPP_CONFIGURATION_ID' => 'CONFIG-ID-9')
        r = described_class.new.result
        expect(r[:configuration_id_present]).to be(true)
        expect(r[:blockers]).not_to include(a_string_matching(/WHATSAPP_CONFIGURATION_ID/))
      end
    end

    context 'when the router toggle is off' do
      it 'flags the router as a blocker' do
        stub_features(master: true, router: false)
        stub_config('BLOOMWIRE_WHATSAPP_PUBLIC_CALLBACK_HOST' => 'chat.example.com', 'WHATSAPP_APP_ID' => 'z',
                    'WHATSAPP_CONFIGURATION_ID' => 'c',
                    'WHATSAPP_APP_SECRET' => 'x', 'BLOOMWIRE_WHATSAPP_GLOBAL_VERIFY_TOKEN' => 'y')
        r = described_class.new.result
        expect(r[:router_enabled]).to be(false)
        expect(r[:blockers]).to include(a_string_matching(/router is OFF/i))
      end
    end

    it 'counts only ready_for_webhook setups as connected inboxes' do
      account = create(:account)
      create(:bloomwire_whatsapp_setup, account: account, setup_status: 'pending')
      create(:bloomwire_whatsapp_setup, :ready_for_webhook, account: account)
      expect(described_class.new.result[:connected_inbox_count]).to eq(1)
    end

    it 'never tracks last webhook received in PR B' do
      expect(described_class.new.result[:last_webhook_received]).to be_nil
    end
  end
end
