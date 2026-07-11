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
    allow(fb_client).to receive(:phone_number_status).and_return('CONNECTED', 'DISCONNECTED')
    allow(fb_client).to receive(:deregister_phone_number).and_return('success' => true)
  end

  def perform(target_account: account, target_inbox: inbox)
    described_class.new(account: target_account, inbox: target_inbox, actor: nil).perform
  end

  it 'deregisters the exact Standard number, verifies DISCONNECTED, then marks the setup disconnected and keeps records' do
    setup
    result = perform
    aggregate_failures do
      expect(result).to be_success
      expect(fb_client).to have_received(:phone_number_status).with('PNID-1').twice
      expect(fb_client).to have_received(:deregister_phone_number).with('PNID-1')
      expect(setup.reload.setup_status).to eq(Bloomwire::WhatsappSetup::DISCONNECTED_STATUS)
      expect(Channel::Whatsapp.exists?(channel.id)).to be(true)
      expect(Inbox.exists?(inbox.id)).to be(true)
      expect(Bloomwire::WhatsappSetup.exists?(setup.id)).to be(true)
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

  it 'returns mobile_action_required for Coexistence without calling Meta or changing setup state' do
    setup
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

  # Coexistence offboarding reconciliation — the SINGLE authoritative owner. There is no account_update /
  # PARTNER_REMOVED webhook handler in the pipeline (the global router resolves only by the message payload's
  # phone_number_id; an account_update payload is WABA-keyed and is dropped before the events job, which has no
  # account_update branch). So this explicit recheck is the ONE place a preserved Coexistence setup is marked
  # `disconnected`, and ONLY after authoritative Meta proof that the number is no longer a connected CLOUD_API
  # coexistence number for the stored token. Never a /deregister; never a false local disconnect. Meta is stubbed.
  describe '#recheck' do
    def recheck(target_account: account, target_inbox: inbox)
      described_class.new(account: target_account, inbox: target_inbox, actor: nil).recheck
    end

    before do
      channel.provider_config['connection_mode'] = 'coexistence'
      channel.save!(validate: false)
      allow(fb_client).to receive(:coexistence_onboarded?)
    end

    it 'marks the preserved setup disconnected only after Meta proof it is no longer coexistence-connected (no /deregister)' do
      setup
      allow(fb_client).to receive(:coexistence_onboarded?).with('PNID-1').and_return(false)
      result = recheck
      aggregate_failures do
        expect(result).to be_success
        expect(fb_client).to have_received(:coexistence_onboarded?).with('PNID-1')
        expect(fb_client).not_to have_received(:deregister_phone_number)
        expect(setup.reload.setup_status).to eq(Bloomwire::WhatsappSetup::DISCONNECTED_STATUS)
        expect(Channel::Whatsapp.exists?(channel.id)).to be(true)
        expect(Inbox.exists?(inbox.id)).to be(true)
        expect(Bloomwire::WhatsappSetup.exists?(setup.id)).to be(true)
      end
    end

    it 'returns still_connected and leaves state unchanged while Meta still reports the number coexistence-connected' do
      setup
      allow(fb_client).to receive(:coexistence_onboarded?).and_return(true)
      result = recheck
      aggregate_failures do
        expect(result.error).to eq(:still_connected)
        expect(fb_client).not_to have_received(:deregister_phone_number)
        expect(setup.reload.setup_status).to eq(Bloomwire::WhatsappSetup::ROUTEABLE_STATUS)
      end
    end

    it 'returns recheck_unverified and leaves state unchanged when the Meta read raises (never a false disconnect)' do
      setup
      allow(fb_client).to receive(:coexistence_onboarded?).and_raise(StandardError, 'boom')
      result = recheck
      aggregate_failures do
        expect(result.error).to eq(:recheck_unverified)
        expect(setup.reload.setup_status).to eq(Bloomwire::WhatsappSetup::ROUTEABLE_STATUS)
      end
    end

    it 'never logs the stored token when the Meta read raises' do
      setup
      logs = []
      allow(Rails.logger).to receive(:warn) { |message| logs << message }
      allow(fb_client).to receive(:coexistence_onboarded?).and_raise(StandardError, "boom #{token}")
      recheck
      expect(logs.join).not_to include(token)
    end

    it 'returns not_coexistence for a Standard number and makes no Meta call' do
      setup
      channel.provider_config['connection_mode'] = 'standard'
      channel.save!(validate: false)
      result = recheck
      aggregate_failures do
        expect(result.error).to eq(:not_coexistence)
        expect(fb_client).not_to have_received(:coexistence_onboarded?)
        expect(setup.reload.setup_status).to eq(Bloomwire::WhatsappSetup::ROUTEABLE_STATUS)
      end
    end

    it 'is not_found for an inbox belonging to another account (no cross-account reconcile)' do
      setup
      result = recheck(target_account: create(:account))
      expect(result.error).to eq(:not_found)
    end
  end
end
