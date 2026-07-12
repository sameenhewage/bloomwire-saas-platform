require 'rails_helper'

# Managed WhatsApp "Disconnect": require the preserved account/inbox/channel/phone-aligned Setup before any Meta
# call. Standard deregisters the exact number with the stored token and marks that same Setup `disconnected` only
# after Meta verifies DISCONNECTED; any missing/misaligned mapping or provider failure leaves all records unchanged.
# Coexistence remains phone-offboarded and locally unchanged until authoritative webhook proof. Meta is stubbed.
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
    allow(fb_client).to receive(:phone_number_status).and_return('CONNECTED', 'DISCONNECTED')
    allow(fb_client).to receive(:deregister_phone_number).and_return('success' => true)
  end

  def perform(target_account: account, target_inbox: inbox)
    described_class.new(account: target_account, inbox: target_inbox, actor: nil).perform
  end

  it 'fails closed before any Meta call when the preserved Setup is missing' do
    inbox
    counts_before = [Inbox.count, Channel::Whatsapp.count, Bloomwire::WhatsappSetup.count]
    expect(Whatsapp::FacebookApiClient).not_to receive(:new)

    result = perform

    aggregate_failures do
      expect(result).not_to be_success
      expect(result.error).to eq(:not_found)
      expect(result.setup).to be_nil
      expect([Inbox.count, Channel::Whatsapp.count, Bloomwire::WhatsappSetup.count]).to eq(counts_before)
      expect(fb_client).not_to have_received(:phone_number_status)
      expect(fb_client).not_to have_received(:deregister_phone_number)
    end
  end

  it 'fails closed before any Meta call when the Setup is linked to a different inbox and channel' do
    setup
    other_channel = Channel::Whatsapp.new(
      account: account, phone_number: '+15551230002', provider: 'whatsapp_cloud',
      provider_config: { 'phone_number_id' => 'PNID-2', 'source' => 'bloomwire_managed' }
    )
    other_channel.save!(validate: false)
    other_inbox = Inbox.create!(account: account, name: 'Other WhatsApp', channel: other_channel)
    setup.inbox_id = other_inbox.id
    setup.channel_whatsapp_id = other_channel.id
    setup.save!(validate: false)
    state_before = [setup.reload.attributes, Inbox.count, Channel::Whatsapp.count, Bloomwire::WhatsappSetup.count]
    expect(Whatsapp::FacebookApiClient).not_to receive(:new)

    result = perform

    aggregate_failures do
      expect(result.error).to eq(:not_found)
      expect(result).not_to be_success
      expect(fb_client).not_to have_received(:phone_number_status)
      expect(fb_client).not_to have_received(:deregister_phone_number)
      expect([setup.reload.attributes, Inbox.count, Channel::Whatsapp.count, Bloomwire::WhatsappSetup.count]).to eq(state_before)
    end
  end

  it 'fails closed before any Meta call when the Setup belongs to a different account' do
    setup
    setup.account_id = create(:account).id
    setup.save!(validate: false)
    state_before = [setup.reload.attributes, Inbox.count, Channel::Whatsapp.count, Bloomwire::WhatsappSetup.count]
    expect(Whatsapp::FacebookApiClient).not_to receive(:new)

    result = perform

    aggregate_failures do
      expect(result.error).to eq(:not_found)
      expect(result).not_to be_success
      expect(fb_client).not_to have_received(:phone_number_status)
      expect(fb_client).not_to have_received(:deregister_phone_number)
      expect([setup.reload.attributes, Inbox.count, Channel::Whatsapp.count, Bloomwire::WhatsappSetup.count]).to eq(state_before)
    end
  end

  it 'deregisters the exact aligned Standard number, verifies DISCONNECTED, and reuses the same records' do
    record_ids = [inbox.id, channel.id, setup.id]
    counts_before = [Inbox.count, Channel::Whatsapp.count, Bloomwire::WhatsappSetup.count]

    result = perform

    aggregate_failures do
      expect(result).to be_success
      expect(result.setup.id).to eq(setup.id)
      expect(Whatsapp::FacebookApiClient).to have_received(:new).with(token)
      expect(fb_client).to have_received(:phone_number_status).with('PNID-1').twice
      expect(fb_client).to have_received(:deregister_phone_number).with('PNID-1').once
      expect(setup.reload.setup_status).to eq(Bloomwire::WhatsappSetup::DISCONNECTED_STATUS)
      expect([inbox.reload.id, channel.reload.id, setup.reload.id]).to eq(record_ids)
      expect([Inbox.count, Channel::Whatsapp.count, Bloomwire::WhatsappSetup.count]).to eq(counts_before)
    end
  end

  it 'reconciles an already-DISCONNECTED Standard number without a duplicate deregister call' do
    setup
    allow(fb_client).to receive(:phone_number_status).and_return('DISCONNECTED')
    result = perform
    aggregate_failures do
      expect(result).to be_success
      expect(fb_client).not_to have_received(:deregister_phone_number)
      expect(setup.reload.setup_status).to eq(Bloomwire::WhatsappSetup::DISCONNECTED_STATUS)
    end
  end

  it 'uses the channel stored token to build the deregister client' do
    setup
    perform
    expect(Whatsapp::FacebookApiClient).to have_received(:new).with(token)
  end

  it 'returns disconnect_unverified and leaves Standard setup state unchanged when deregister raises' do
    setup
    allow(fb_client).to receive(:deregister_phone_number).and_raise(StandardError, 'RAW meta 400')
    result = perform
    aggregate_failures do
      expect(result.error).to eq(:disconnect_unverified)
      expect(setup.reload.setup_status).to eq(Bloomwire::WhatsappSetup::ROUTEABLE_STATUS)
    end
  end

  it 'returns disconnect_unverified and leaves Standard setup state unchanged when Meta still reports CONNECTED' do
    setup
    allow(fb_client).to receive(:phone_number_status).and_return('CONNECTED')
    result = perform
    aggregate_failures do
      expect(result.error).to eq(:disconnect_unverified)
      expect(setup.reload.setup_status).to eq(Bloomwire::WhatsappSetup::ROUTEABLE_STATUS)
    end
  end

  it 'returns mobile_action_required for Coexistence without calling Meta or changing preserved records' do
    record_ids = [inbox.id, channel.id, setup.id]
    counts_before = [Inbox.count, Channel::Whatsapp.count, Bloomwire::WhatsappSetup.count]
    channel.provider_config['connection_mode'] = 'coexistence'
    channel.save!(validate: false)

    result = perform

    aggregate_failures do
      expect(result.error).to eq(:mobile_action_required)
      expect(result.setup).to eq(setup)
      expect(Whatsapp::FacebookApiClient).not_to have_received(:new)
      expect(fb_client).not_to have_received(:phone_number_status)
      expect(fb_client).not_to have_received(:deregister_phone_number)
      expect(setup.reload.setup_status).to eq(Bloomwire::WhatsappSetup::ROUTEABLE_STATUS)
      expect([inbox.reload.id, channel.reload.id, setup.reload.id]).to eq(record_ids)
      expect([Inbox.count, Channel::Whatsapp.count, Bloomwire::WhatsappSetup.count]).to eq(counts_before)
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
      expect(fb_client).not_to have_received(:phone_number_status)
    end
  end

  it 'is not_whatsapp for a non-WhatsApp inbox' do
    result = perform(target_inbox: create(:inbox, account: account))
    expect(result.error).to eq(:not_whatsapp)
  end
end
