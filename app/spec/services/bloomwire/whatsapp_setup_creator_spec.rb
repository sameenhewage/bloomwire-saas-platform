require 'rails_helper'

# Phase 17C.1: creates/updates the NON-SECRET Bloomwire::WhatsappSetup router mapping for an already-existing
# customer WhatsApp channel + inbox. It accepts only non-secret routing identifiers, creates no
# account/user/inbox/channel, stores no secret, and makes no Meta call. Fake values only.
RSpec.describe Bloomwire::WhatsappSetupCreator do
  let(:account) { create(:account) }
  # An aligned whatsapp_cloud channel (+ its own inbox): phone_number == "+<display>", provider_config
  # phone_number_id set — so the global router can resolve the resulting ready_for_webhook mapping.
  let(:channel) do
    bw_aligned_whatsapp_channel(account: account, phone_number_id: 'PNID-C1-1', display_phone_number: '15551230001')
  end
  let(:inbox) { channel.inbox }

  def call(**overrides)
    described_class.call(account: account, inbox: inbox, channel_whatsapp: channel,
                         phone_number_id: 'PNID-C1-1', waba_id: 'WABA-C1-1',
                         display_phone_number: '15551230001', **overrides)
  end

  describe 'creating the mapping' do
    it 'creates exactly one mapping' do
      expect { call }.to change(Bloomwire::WhatsappSetup, :count).by(1)
    end

    it 'writes the correct non-secret identifiers and ready_for_webhook status' do
      setup = call.setup
      aggregate_failures do
        expect(setup.account_id).to eq(account.id)
        expect(setup.inbox_id).to eq(inbox.id)
        expect(setup.channel_whatsapp_id).to eq(channel.id)
        expect(setup.phone_number_id).to eq('PNID-C1-1')
        expect(setup.waba_id).to eq('WABA-C1-1')
        expect(setup.display_phone_number).to eq('15551230001')
        expect(setup.setup_status).to eq('ready_for_webhook')
      end
    end

    it 'lets the global router resolve the created mapping (handoff-safe)' do
      setup = call.setup
      payload = bw_inbound_text_payload(phone_number_id: 'PNID-C1-1', display_phone_number: '15551230001')
      aggregate_failures do
        expect(Bloomwire::Webhooks::WhatsappRouter.resolve(payload)&.id).to eq(setup.id)
        expect(Bloomwire::Webhooks::WhatsappRouter.resolve_handoff_safe_setup(payload)&.id).to eq(setup.id)
      end
    end
  end

  describe 'idempotency' do
    it 'is idempotent for the same channel_whatsapp_id (no duplicate)' do
      call
      expect { call }.not_to change(Bloomwire::WhatsappSetup, :count)
    end

    it 'updates the existing mapping in place when re-run with new non-secret values' do
      first = call.setup
      result = call(waba_id: 'WABA-UPDATED')
      aggregate_failures do
        expect(result).to be_success
        expect(result.setup.id).to eq(first.id)
        expect(result.setup.waba_id).to eq('WABA-UPDATED')
      end
    end
  end

  describe 'validation / safety (fail closed with safe symbol errors)' do
    it 'rejects a missing phone_number_id and creates nothing' do
      result = call(phone_number_id: '')
      aggregate_failures do
        expect(result).not_to be_success
        expect(result.error).to eq(:missing_phone_number_id)
        expect(Bloomwire::WhatsappSetup.count).to eq(0)
      end
    end

    it 'rejects a cross-account inbox/channel (account mismatch)' do
      expect(call(account: create(:account)).error).to eq(:account_mismatch)
    end

    it 'rejects an inbox that does not own the given channel' do
      other = bw_aligned_whatsapp_channel(account: account, phone_number_id: 'PNID-OTHER',
                                          display_phone_number: '15551239999')
      expect(call(inbox: other.inbox).error).to eq(:channel_inbox_mismatch)
    end

    it 'fails closed when the phone_number_id is already claimed by a different channel' do
      call
      other = bw_aligned_whatsapp_channel(account: account, phone_number_id: 'PNID-C1-1',
                                          display_phone_number: '15551235555')
      result = described_class.call(account: account, inbox: other.inbox, channel_whatsapp: other,
                                    phone_number_id: 'PNID-C1-1', display_phone_number: '15551235555')
      expect(result.error).to eq(:phone_number_id_conflict)
    end
  end

  # Phase 17C.1 review (Blocker 2): a ready_for_webhook mapping must be handoff-safe for the global router.
  describe 'router handoff-safety' do
    it 'rejects a non-Cloud (whatsapp_cloud) provider and creates no ready mapping' do
      channel.update_column(:provider, 'default') # rubocop:disable Rails/SkipsModelValidations
      aggregate_failures do
        expect(call.error).to eq(:unsupported_provider)
        expect(Bloomwire::WhatsappSetup.ready_for_webhook.count).to eq(0)
      end
    end

    it 'rejects a channel whose provider_config phone_number_id does not match' do
      result = call(phone_number_id: 'PNID-DIFFERENT')
      aggregate_failures do
        expect(result.error).to eq(:phone_number_id_mismatch)
        expect(Bloomwire::WhatsappSetup.ready_for_webhook.count).to eq(0)
      end
    end

    it 'rejects a channel whose phone_number does not match the display number' do
      result = call(display_phone_number: '15559999999')
      aggregate_failures do
        expect(result.error).to eq(:display_phone_number_mismatch)
        expect(Bloomwire::WhatsappSetup.ready_for_webhook.count).to eq(0)
      end
    end

    it 'creates the mapping and the global router resolves it when the channel is aligned' do
      setup = call.setup
      payload = bw_inbound_text_payload(phone_number_id: 'PNID-C1-1', display_phone_number: '15551230001')
      aggregate_failures do
        expect(setup.setup_status).to eq('ready_for_webhook')
        expect(Bloomwire::Webhooks::WhatsappRouter.resolve_handoff_safe_setup(payload)&.id).to eq(setup.id)
      end
    end
  end

  describe 'no-secret boundary' do
    it 'does not accept an api_key argument' do
      expect do
        described_class.call(account: account, inbox: inbox, channel_whatsapp: channel,
                             phone_number_id: 'PNID-C1-1', api_key: 'FAKE-SECRET')
      end.to raise_error(ArgumentError)
    end

    it 'does not accept a provider_config argument' do
      expect do
        described_class.call(account: account, inbox: inbox, channel_whatsapp: channel,
                             phone_number_id: 'PNID-C1-1', provider_config: { api_key: 'x' })
      end.to raise_error(ArgumentError)
    end

    it 'stores no secret on the mapping and never mutates the channel provider_config' do
      before_config = channel.reload.provider_config.to_h
      setup = call.setup
      aggregate_failures do
        expect(setup.attributes.keys.grep(/api_key|token|secret|password/i)).to be_empty
        expect(channel.reload.provider_config.to_h).to eq(before_config)
      end
    end
  end
end
