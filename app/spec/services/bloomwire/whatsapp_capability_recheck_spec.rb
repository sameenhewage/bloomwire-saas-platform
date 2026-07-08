require 'rails_helper'

# Phase 5 (resume): idempotent re-verification of outbound capability for an EXISTING Action-Required managed
# WhatsApp setup. Meta client stubbed (no real Meta). Proves: when the owner has since granted the task the SAME
# setup is promoted action_required -> ready_for_webhook (same Channel/Inbox/Setup ids, no duplicate, no second
# inbox, no /register); still-missing/unverifiable stays non-routeable with a refreshed sanitized reason; the
# grant path is NEVER exercised (verify-only); the stored channel token is used. Fake values only.
RSpec.describe Bloomwire::WhatsappCapabilityRecheck do
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
      display_phone_number: '+15551230001', setup_status: Bloomwire::WhatsappSetup::ACTION_REQUIRED_STATUS,
      status_reason: 'outbound_messaging_permission_required'
    )
  end

  before do
    allow(Whatsapp::FacebookApiClient).to receive(:new).and_return(fb_client)
    allow(fb_client).to receive(:token_actor_id).and_return('ACTOR-1')
    allow(fb_client).to receive(:token_actor_type).and_return('SYSTEM_USER')
    allow(fb_client).to receive(:waba_user_tasks).and_return(%w[VIEW_TEMPLATES])
    allow(fb_client).to receive(:assign_waba_user_tasks)
    allow(fb_client).to receive(:register_phone_number)
    allow(fb_client).to receive(:subscribe_app_to_waba)
    allow(fb_client).to receive(:subscribed_to_waba?).and_return(true)
  end

  def perform
    described_class.new(setup: setup).perform
  end

  describe 'the owner has since granted the task (verified capable)' do
    before { allow(fb_client).to receive(:waba_user_tasks).and_return(%w[MANAGE]) }

    it 'promotes the SAME setup to ready_for_webhook, clears the reason, and reads the stored token' do
      result = perform
      setup.reload
      aggregate_failures do
        expect(result).to be_success
        expect(result.ready?).to be(true)
        expect(setup.setup_status).to eq(Bloomwire::WhatsappSetup::ROUTEABLE_STATUS)
        expect(setup.status_reason).to be_nil
        expect(Whatsapp::FacebookApiClient).to have_received(:new).with(token)
      end
    end

    # BLOCKER 2: onboarding never subscribed this Action-Required inbox, so recheck must subscribe the EXACT WABA
    # and VERIFY it took effect BEFORE promoting (enable inbound at the same moment outbound becomes ready).
    it 'subscribes the EXACT WABA and verifies the subscription before promoting to ready' do
      perform
      aggregate_failures do
        expect(fb_client).to have_received(:subscribe_app_to_waba).with('WABA-1')
        expect(fb_client).to have_received(:subscribed_to_waba?).with('WABA-1')
      end
    end

    it 'stays action_required (SAME records, NOT promoted) when the subscription cannot be confirmed' do
      allow(fb_client).to receive(:subscribed_to_waba?).and_return(false)
      result = perform
      setup.reload
      aggregate_failures do
        expect(result.action_required?).to be(true)
        expect(setup.setup_status).to eq(Bloomwire::WhatsappSetup::ACTION_REQUIRED_STATUS)
        expect(setup.status_reason).to eq('outbound_messaging_activation_incomplete')
        expect(setup.channel_whatsapp_id).to eq(channel.id)
        expect(setup.inbox_id).to eq(inbox.id)
      end
    end

    it 'keeps the SAME Channel/Inbox/Setup ids and creates no duplicate records' do
      original = setup # force creation before counting
      before_counts = [Channel::Whatsapp.count, Inbox.count, Bloomwire::WhatsappSetup.count]
      result = perform
      aggregate_failures do
        expect(result.setup.id).to eq(original.id)
        expect(result.setup.inbox_id).to eq(inbox.id)
        expect(result.setup.channel_whatsapp_id).to eq(channel.id)
        expect([Channel::Whatsapp.count, Inbox.count, Bloomwire::WhatsappSetup.count]).to eq(before_counts)
      end
    end

    it 'never re-registers the number and never attempts a grant (verify-only)' do
      perform
      aggregate_failures do
        expect(fb_client).not_to have_received(:register_phone_number)
        expect(fb_client).not_to have_received(:assign_waba_user_tasks)
      end
    end
  end

  describe 'the task is still missing (verified_missing)' do
    it 'stays action_required (non-routeable), keeps the sanitized reason, and never grants' do
      result = perform
      setup.reload
      aggregate_failures do
        expect(result.action_required?).to be(true)
        expect(setup.setup_status).to eq(Bloomwire::WhatsappSetup::ACTION_REQUIRED_STATUS)
        expect(setup.status_reason).to eq('outbound_messaging_permission_required')
        expect(fb_client).not_to have_received(:assign_waba_user_tasks)
        expect(fb_client).not_to have_received(:subscribe_app_to_waba)
      end
    end
  end

  describe 'the task cannot be verified (lookup raised)' do
    before { allow(fb_client).to receive(:waba_user_tasks).and_raise(StandardError, 'RAW meta 500') }

    it 'stays action_required (never a false ready) with the unverifiable reason and no grant' do
      result = perform
      setup.reload
      aggregate_failures do
        expect(result.action_required?).to be(true)
        expect(setup.setup_status).to eq(Bloomwire::WhatsappSetup::ACTION_REQUIRED_STATUS)
        expect(setup.status_reason).to eq('outbound_messaging_permission_unverifiable')
        expect(fb_client).not_to have_received(:assign_waba_user_tasks)
        expect(fb_client).not_to have_received(:subscribe_app_to_waba)
      end
    end
  end

  describe 'idempotency + guards' do
    it 'is a safe no-op success when the setup is already routeable (no Meta call)' do
      setup.update!(setup_status: Bloomwire::WhatsappSetup::ROUTEABLE_STATUS, status_reason: nil)
      result = perform
      aggregate_failures do
        expect(result.ready?).to be(true)
        expect(Whatsapp::FacebookApiClient).not_to have_received(:new)
      end
    end

    it 'returns :not_found for a nil setup' do
      expect(described_class.new(setup: nil).perform.error).to eq(:not_found)
    end
  end
end
