require 'rails_helper'

# WhatsWay-parity "Disconnect": deregister the number on Meta (NON-FATAL) + mark the setup `disconnected` while
# KEEPING the Channel/Inbox/Setup records so a later Embedded Signup reconnect reuses them. Meta is stubbed (no real
# Meta). Proves the EXACT number is deregistered with the stored token, records survive, a deregister failure still
# disconnects locally, no token is logged, and cross-account / non-WhatsApp are rejected. Fake values only.
RSpec.describe Bloomwire::WhatsappDisconnectService do
  let(:account) { create(:account) }
  let(:token) { 'FAKE-STORED-TOKEN' }
  let(:fb_client) { instance_double(Whatsapp::FacebookApiClient) }
  let(:channel) do
    Channel::Whatsapp.new(
      account: account, phone_number: '+15551230001', provider: 'whatsapp_cloud',
      provider_config: { 'phone_number_id' => 'PNID-1', 'business_account_id' => 'WABA-1',
                         'source' => 'bloomwire_managed', 'connection_mode' => 'standard' }
    ).tap do |channel_record|
      channel_record.save!(validate: false)
      channel_record.provider_config['api_key'] = token
      channel_record.save!(validate: false)
    end
  end
  let(:inbox) { Inbox.create!(account: account, name: 'Acme WhatsApp', channel: channel) }
  let(:setup) do
    Bloomwire::WhatsappSetup.create!(
      account: account, inbox: inbox, channel_whatsapp: channel, phone_number_id: 'PNID-1', waba_id: 'WABA-1',
      display_phone_number: '+15551230001', setup_status: Bloomwire::WhatsappSetup::ROUTEABLE_STATUS
    )
  end

  before do
    allow(Whatsapp::FacebookApiClient).to receive(:new).and_return(fb_client)
    allow(fb_client).to receive(:deregister_phone_number).and_return('success' => true)
  end

  def perform(target_account: account, target_inbox: inbox)
    described_class.new(account: target_account, inbox: target_inbox, actor: nil).perform
  end

  it 'deregisters the EXACT number on Meta and marks the setup disconnected, KEEPING all records' do
    setup
    result = perform
    aggregate_failures do
      expect(result).to be_success
      expect(fb_client).to have_received(:deregister_phone_number).with('PNID-1')
      expect(setup.reload.setup_status).to eq(Bloomwire::WhatsappSetup::DISCONNECTED_STATUS)
      expect(Channel::Whatsapp.exists?(channel.id)).to be(true)
      expect(Inbox.exists?(inbox.id)).to be(true)
      expect(Bloomwire::WhatsappSetup.exists?(setup.id)).to be(true)
    end
  end

  it 'uses the channel stored token to build the deregister client' do
    setup
    perform
    expect(Whatsapp::FacebookApiClient).to have_received(:new).with(token)
  end

  it 'is NON-FATAL when the Meta deregister raises: the inbox is still disconnected locally (WhatsWay parity)' do
    setup
    allow(fb_client).to receive(:deregister_phone_number).and_raise(StandardError, 'RAW meta 400')
    result = perform
    aggregate_failures do
      expect(result).to be_success
      expect(setup.reload.setup_status).to eq(Bloomwire::WhatsappSetup::DISCONNECTED_STATUS)
    end
  end

  it 'never logs the stored token when the deregister raises' do
    setup
    logs = []
    allow(Rails.logger).to receive(:warn) { |message| logs << message }
    allow(fb_client).to receive(:deregister_phone_number).and_raise(StandardError, "boom #{token}")
    perform
    aggregate_failures do
      expect(logs.join).to include('bloomwire.whatsapp.disconnect')
      expect(logs.join).not_to include(token)
    end
  end

  it 'is not_found for an inbox belonging to another account (no cross-account disconnect)' do
    setup
    result = perform(target_account: create(:account))
    aggregate_failures do
      expect(result.error).to eq(:not_found)
      expect(fb_client).not_to have_received(:deregister_phone_number)
    end
  end

  it 'is not_whatsapp for a non-WhatsApp inbox' do
    result = perform(target_inbox: create(:inbox, account: account))
    expect(result.error).to eq(:not_whatsapp)
  end
end
