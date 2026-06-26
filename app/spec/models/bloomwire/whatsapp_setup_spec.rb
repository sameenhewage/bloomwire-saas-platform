require 'rails_helper'

# Data-integrity rules for the Bloomwire WhatsApp Setup Mapping. The future global webhook router will TRUST
# this mapping, so cross-account / cross-channel mismatches and non-routeable "ready" rows must be rejected.
RSpec.describe Bloomwire::WhatsappSetup do
  let(:account) { create(:account) }
  let(:other_account) { create(:account) }

  def whatsapp_channel_for(acc)
    create(:channel_whatsapp, account: acc, provider: 'whatsapp_cloud', sync_templates: false,
                              validate_provider_config: false)
  end

  describe 'account / inbox / channel consistency' do
    it 'requires an account' do
      setup = described_class.new(setup_status: 'pending')
      expect(setup).not_to be_valid
      expect(setup.errors[:account]).to be_present
    end

    it 'rejects an inbox from another account' do
      other_inbox = create(:inbox, account: other_account)
      setup = described_class.new(account: account, inbox: other_inbox, setup_status: 'pending')
      expect(setup).not_to be_valid
      expect(setup.errors[:inbox_id]).to be_present
    end

    it 'rejects a whatsapp channel from another account' do
      other_channel = whatsapp_channel_for(other_account)
      setup = described_class.new(account: account, channel_whatsapp: other_channel, setup_status: 'pending')
      expect(setup).not_to be_valid
      expect(setup.errors[:channel_whatsapp_id]).to be_present
    end

    it 'rejects an inbox that does not belong to the selected channel (no mixed mappings)' do
      channel = whatsapp_channel_for(account)
      other_channel = whatsapp_channel_for(account)
      setup = described_class.new(account: account, inbox: other_channel.inbox, channel_whatsapp: channel,
                                  setup_status: 'pending')
      expect(setup).not_to be_valid
      expect(setup.errors[:inbox_id]).to be_present
    end

    it 'accepts a consistent account + inbox + channel mapping' do
      channel = whatsapp_channel_for(account)
      setup = described_class.new(account: account, inbox: channel.inbox, channel_whatsapp: channel,
                                  setup_status: 'configured')
      expect(setup).to be_valid
    end
  end

  describe 'phone_number_id uniqueness' do
    it 'rejects a duplicate phone_number_id' do
      create(:bloomwire_whatsapp_setup, account: account, phone_number_id: 'PNID-DUP')
      dup = described_class.new(account: other_account, phone_number_id: 'PNID-DUP', setup_status: 'pending')
      expect(dup).not_to be_valid
      expect(dup.errors[:phone_number_id]).to be_present
    end

    it 'allows multiple pending rows with a blank phone_number_id' do
      create(:bloomwire_whatsapp_setup, account: account, phone_number_id: nil)
      second = described_class.new(account: other_account, phone_number_id: nil, setup_status: 'pending')
      expect(second).to be_valid
    end
  end

  describe 'ready_for_webhook routeability' do
    let(:channel) { whatsapp_channel_for(account) }

    it 'rejects ready_for_webhook without a phone_number_id' do
      setup = described_class.new(account: account, inbox: channel.inbox, channel_whatsapp: channel,
                                  setup_status: 'ready_for_webhook', phone_number_id: nil)
      expect(setup).not_to be_valid
      expect(setup.errors[:phone_number_id]).to be_present
    end

    it 'rejects ready_for_webhook without an inbox_id' do
      setup = described_class.new(account: account, channel_whatsapp: channel,
                                  setup_status: 'ready_for_webhook', phone_number_id: 'PNID-1')
      expect(setup).not_to be_valid
      expect(setup.errors[:inbox_id]).to be_present
    end

    it 'rejects ready_for_webhook without a channel_whatsapp_id' do
      setup = described_class.new(account: account, inbox: channel.inbox,
                                  setup_status: 'ready_for_webhook', phone_number_id: 'PNID-1')
      expect(setup).not_to be_valid
      expect(setup.errors[:channel_whatsapp_id]).to be_present
    end

    it 'allows ready_for_webhook when account + inbox + channel + phone_number_id are all consistent' do
      setup = described_class.new(account: account, inbox: channel.inbox, channel_whatsapp: channel,
                                  setup_status: 'ready_for_webhook', phone_number_id: 'PNID-READY')
      expect(setup).to be_valid
    end
  end
end
