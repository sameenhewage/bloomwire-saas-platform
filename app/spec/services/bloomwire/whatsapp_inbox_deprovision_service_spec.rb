require 'rails_helper'

# Permanent removal of a managed WhatsApp inbox and ALL its Bloomwire-owned data — no orphans, no shared-Contact
# loss, no Meta call, idempotent.
RSpec.describe Bloomwire::WhatsappInboxDeprovisionService do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }

  # A managed WhatsApp inbox: whatsapp_cloud channel with source 'bloomwire_managed' (+ its inbox) and an aligned,
  # routeable Bloomwire::WhatsappSetup. Fake routing identifiers only.
  def managed_inbox(on: account, phone_number: '+15551230001', phone_number_id: 'PNID-1', waba_id: 'WABA-1')
    channel = create(:channel_whatsapp, account: on, provider: 'whatsapp_cloud', phone_number: phone_number,
                                        sync_templates: false, validate_provider_config: false)
    channel.provider_config = {
      'source' => 'bloomwire_managed', 'phone_number_id' => phone_number_id,
      'business_account_id' => waba_id, 'api_key' => 'FAKE-KEY'
    }
    channel.save!(validate: false)
    inbox = channel.inbox
    setup = create(:bloomwire_whatsapp_setup, account: on, inbox: inbox, channel_whatsapp: channel,
                                              phone_number_id: phone_number_id, waba_id: waba_id,
                                              display_phone_number: phone_number, setup_status: 'ready_for_webhook')
    [inbox, channel, setup]
  end

  def deprovision(inbox, acting_account: account)
    described_class.new(account: acting_account, inbox: inbox, actor: admin).perform
  end

  describe 'authorization / preconditions' do
    it 'refuses a cross-account inbox (:not_found) and deletes nothing' do
      other = create(:account)
      inbox, = managed_inbox(on: other)
      result = deprovision(inbox, acting_account: account)
      expect(result.error).to eq(:not_found)
      expect(Inbox.exists?(inbox.id)).to be(true)
    end

    it 'refuses a non-WhatsApp inbox (:not_whatsapp)' do
      web = create(:inbox, account: account) # web widget channel
      expect(deprovision(web).error).to eq(:not_whatsapp)
      expect(Inbox.exists?(web.id)).to be(true)
    end

    it 'refuses a non-managed (embedded_signup) WhatsApp channel (:not_managed) — Meta-owned lifecycle' do
      channel = create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud',
                                          sync_templates: false, validate_provider_config: false)
      channel.provider_config = channel.provider_config.merge('source' => 'embedded_signup')
      channel.save!(validate: false)
      expect(deprovision(channel.inbox).error).to eq(:not_managed)
      expect(Inbox.exists?(channel.inbox.id)).to be(true)
    end
  end

  describe 'successful deprovision' do
    it 'destroys the Inbox, Channel::Whatsapp and Bloomwire::WhatsappSetup with no orphans' do
      inbox, channel, setup = managed_inbox
      expect(deprovision(inbox)).to be_success
      aggregate_failures do
        expect(Inbox.exists?(inbox.id)).to be(false)
        expect(Channel::Whatsapp.exists?(channel.id)).to be(false)
        expect(Bloomwire::WhatsappSetup.exists?(setup.id)).to be(false)
      end
    end

    it 'deletes the inbox conversations, messages and contact-inbox mappings' do
      inbox, = managed_inbox
      contact = create(:contact, account: account)
      contact_inbox = create(:contact_inbox, contact: contact, inbox: inbox)
      conversation = create(:conversation, account: account, inbox: inbox, contact: contact,
                                           contact_inbox: contact_inbox)
      create(:message, account: account, inbox: inbox, conversation: conversation)

      deprovision(inbox)

      aggregate_failures do
        expect(Conversation.exists?(conversation.id)).to be(false)
        expect(Message.where(conversation_id: conversation.id).count).to eq(0)
        expect(ContactInbox.exists?(contact_inbox.id)).to be(false)
      end
    end

    it 'PRESERVES the shared Contact record (only the ContactInbox join is removed)' do
      inbox, = managed_inbox
      contact = create(:contact, account: account)
      create(:contact_inbox, contact: contact, inbox: inbox)
      # The same contact also messages via another (unrelated) inbox — must survive.
      other_inbox = create(:inbox, account: account)
      create(:contact_inbox, contact: contact, inbox: other_inbox)

      deprovision(inbox)

      aggregate_failures do
        expect(Contact.exists?(contact.id)).to be(true)
        expect(ContactInbox.where(contact_id: contact.id, inbox_id: other_inbox.id).count).to eq(1)
      end
    end

    it 'leaves unrelated inboxes and their data untouched' do
      inbox, = managed_inbox(phone_number: '+15551230001', phone_number_id: 'PNID-1')
      keep_inbox, keep_channel, keep_setup = managed_inbox(phone_number: '+15559990000', phone_number_id: 'PNID-2')
      keep_conversation = create(:conversation, account: account, inbox: keep_inbox)

      deprovision(inbox)

      aggregate_failures do
        expect(Inbox.exists?(keep_inbox.id)).to be(true)
        expect(Channel::Whatsapp.exists?(keep_channel.id)).to be(true)
        expect(Bloomwire::WhatsappSetup.exists?(keep_setup.id)).to be(true)
        expect(Conversation.exists?(keep_conversation.id)).to be(true)
      end
    end
  end

  describe 'routing safety' do
    it 'stops the global webhook router from resolving the number once removed' do
      inbox, _channel, setup = managed_inbox(phone_number_id: 'PNID-ROUTE')
      payload = { 'entry' => [{ 'changes' => [{ 'value' => { 'metadata' => { 'phone_number_id' => 'PNID-ROUTE' } } }] }] }
      expect(Bloomwire::Webhooks::WhatsappRouter.resolve(payload)&.id).to eq(setup.id)

      deprovision(inbox)

      expect(Bloomwire::Webhooks::WhatsappRouter.resolve(payload)).to be_nil
    end
  end

  describe 'Meta boundary' do
    it 'makes NO Meta call (managed-source channels skip the webhook teardown)' do
      inbox, = managed_inbox
      expect(Whatsapp::FacebookApiClient).not_to receive(:new)
      deprovision(inbox)
    end
  end

  describe 'idempotency + local duplicate guard' do
    it 'is idempotent: after removal the inbox is gone and a repeat (nil inbox) is a safe :not_found no-op' do
      inbox, = managed_inbox
      expect(deprovision(inbox)).to be_success
      expect(Inbox.find_by(id: inbox.id)).to be_nil
      # The controller re-fetches by id; after deletion that is nil. A repeat with nil is a safe no-op.
      repeat = described_class.new(account: account, inbox: Inbox.find_by(id: inbox.id), actor: admin).perform
      expect(repeat.error).to eq(:not_found)
    end

    it 'frees the number: the local phone_number_taken guard no longer matches after removal' do
      inbox, = managed_inbox(phone_number: '+15551230001')
      expect(Bloomwire::WhatsappPhoneAvailability.status_for('+15551230001')).to eq('already_connected')
      deprovision(inbox)
      expect(Bloomwire::WhatsappPhoneAvailability.status_for('+15551230001')).to eq('available')
    end
  end
end
