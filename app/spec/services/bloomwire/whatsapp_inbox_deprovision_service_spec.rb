require 'rails_helper'

# Two-phase managed WhatsApp inbox removal: a short synchronous #prepare (authorize/verify, block routing, enqueue)
# and an async, retry-safe, idempotent .purge! (heavy deletion, no orphans, no shared-Contact loss, no Meta call).
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

  def service(inbox, acting_account: account)
    described_class.new(account: acting_account, inbox: inbox, actor: admin)
  end

  def purge(inbox)
    described_class.purge!(account_id: account.id, inbox_id: inbox.id, actor_id: admin.id)
  end

  describe '#prepare (sync request path)' do
    it 'refuses a cross-account inbox (:not_found), blocks nothing, enqueues nothing' do
      other = create(:account)
      inbox, = managed_inbox(on: other)
      expect do
        expect(service(inbox, acting_account: account).prepare.error).to eq(:not_found)
      end.not_to have_enqueued_job(Bloomwire::WhatsappInboxDeprovisionJob)
      expect(Inbox.exists?(inbox.id)).to be(true)
    end

    it 'refuses a non-WhatsApp inbox (:not_whatsapp)' do
      web = create(:inbox, account: account)
      expect(service(web).prepare.error).to eq(:not_whatsapp)
    end

    it 'refuses a non-managed (embedded_signup) WhatsApp channel (:not_managed)' do
      channel = create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud',
                                          sync_templates: false, validate_provider_config: false)
      channel.provider_config = channel.provider_config.merge('source' => 'embedded_signup')
      channel.save!(validate: false)
      expect(service(channel.inbox).prepare.error).to eq(:not_managed)
    end

    it 'blocks routing and enqueues the deletion job WITHOUT doing the heavy delete in-request' do
      inbox, _channel, setup = managed_inbox
      expect do
        expect(service(inbox).prepare).to be_success
      end.to have_enqueued_job(Bloomwire::WhatsappInboxDeprovisionJob)
        .with(account_id: account.id, inbox_id: inbox.id, actor_id: admin.id)

      # Routing is blocked immediately; the inbox itself still exists until the job runs.
      expect(setup.reload.setup_status).to eq('blocked')
      expect(Inbox.exists?(inbox.id)).to be(true)
    end

    it 'emits a sanitized removal_started audit event on a successful prepare' do
      inbox, channel, = managed_inbox
      allow(Rails.logger).to receive(:info)
      service(inbox).prepare
      expect(Rails.logger).to have_received(:info)
        .with("[BLOOMWIRE WA DEPROVISION] removal_started account=#{account.id} inbox=#{inbox.id} " \
              "channel=#{channel.id} actor=#{admin.id}")
    end

    describe 'enqueue acceptance (findings 2 & 3)' do
      # A `perform_later` that returns false (a halted enqueue callback) is a confirmed failure. (finding 3) it also
      # emits a sanitized removal_failed audit.
      it 'returns :enqueue_failed, RESTORES prior routing, and audits removal_failed when perform_later returns false' do
        inbox, _channel, setup = managed_inbox
        allow(Rails.logger).to receive(:warn)
        allow(Bloomwire::WhatsappInboxDeprovisionJob).to receive(:perform_later).and_return(false)

        expect(service(inbox).prepare.error).to eq(:enqueue_failed)
        expect(setup.reload.setup_status).to eq('ready_for_webhook') # deterministic: routing restored
        expect(Inbox.exists?(inbox.id)).to be(true)
        expect(Rails.logger).to have_received(:warn).with(/removal_failed .*reason=enqueue_not_accepted/)
      end

      # A returned job that was not accepted by the adapter (successfully_enqueued? == false) is also a failure.
      it 'returns :enqueue_failed when the job was not successfully enqueued' do
        inbox, _channel, setup = managed_inbox
        unenqueued = Bloomwire::WhatsappInboxDeprovisionJob.new
        allow(unenqueued).to receive(:successfully_enqueued?).and_return(false)
        allow(Bloomwire::WhatsappInboxDeprovisionJob).to receive(:perform_later).and_return(unenqueued)

        expect(service(inbox).prepare.error).to eq(:enqueue_failed)
        expect(setup.reload.setup_status).to eq('ready_for_webhook')
      end

      # A RAISED enqueue (adapter/broker down) is a confirmed failure, not a 202; the audit carries the error class.
      it 'returns :enqueue_failed, restores routing, and audits the error class when perform_later raises' do
        inbox, _channel, setup = managed_inbox
        allow(Rails.logger).to receive(:warn)
        allow(Bloomwire::WhatsappInboxDeprovisionJob).to receive(:perform_later).and_raise(StandardError, 'broker down')

        expect(service(inbox).prepare.error).to eq(:enqueue_failed)
        expect(setup.reload.setup_status).to eq('ready_for_webhook')
        expect(Rails.logger).to have_received(:warn).with(/removal_failed .*reason=StandardError/)
      end

      it 'allows a successful manual retry after an enqueue failure' do
        inbox, _channel, setup = managed_inbox
        allow(Bloomwire::WhatsappInboxDeprovisionJob).to receive(:perform_later).and_return(false)
        expect(service(inbox).prepare.error).to eq(:enqueue_failed)

        allow(Bloomwire::WhatsappInboxDeprovisionJob).to receive(:perform_later).and_call_original
        expect do
          expect(service(inbox).prepare).to be_success
        end.to have_enqueued_job(Bloomwire::WhatsappInboxDeprovisionJob)
        expect(setup.reload.setup_status).to eq('blocked')
      end

      # (finding 2) once an accepted removal has blocked routing, a LATER request whose enqueue fails must NOT
      # restore/reopen routing. The block/enqueue/restore decision is serialized per setup row (with_lock) and the
      # prior status is read UNDER the lock, so the failed request sees 'blocked' and its restore is a no-op.
      it 'a failed enqueue cannot reopen routing blocked by another accepted removal' do
        inbox, _channel, setup = managed_inbox

        # Request A: accepted -> routing blocked.
        expect(service(inbox).prepare).to be_success
        expect(setup.reload.setup_status).to eq('blocked')

        # Request B (later): its enqueue fails.
        allow(Bloomwire::WhatsappInboxDeprovisionJob).to receive(:perform_later).and_return(false)
        expect(service(inbox).prepare.error).to eq(:enqueue_failed)

        # Invariant: routing stays blocked (B did not reopen A's accepted block).
        expect(setup.reload.setup_status).to eq('blocked')
      end

      it 'serializes the block/enqueue/restore decision with a row lock on the setup' do
        inbox, _channel, setup = managed_inbox
        locked = Bloomwire::WhatsappSetup.find(setup.id)
        allow(Bloomwire::WhatsappSetup).to receive(:find_by).and_call_original
        allow(Bloomwire::WhatsappSetup).to receive(:find_by)
          .with(channel_whatsapp_id: setup.channel_whatsapp_id).and_return(locked)
        allow(locked).to receive(:with_lock).and_call_original

        service(inbox).prepare
        expect(locked).to have_received(:with_lock)
      end
    end
  end

  describe '.purge! (async deletion)' do
    it 'destroys the Inbox, Channel::Whatsapp and Bloomwire::WhatsappSetup with no orphans' do
      inbox, channel, setup = managed_inbox
      purge(inbox)
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

      purge(inbox)

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
      other_inbox = create(:inbox, account: account)
      create(:contact_inbox, contact: contact, inbox: other_inbox)

      purge(inbox)

      aggregate_failures do
        expect(Contact.exists?(contact.id)).to be(true)
        expect(ContactInbox.where(contact_id: contact.id, inbox_id: other_inbox.id).count).to eq(1)
      end
    end

    it 'leaves unrelated inboxes and their data untouched' do
      inbox, = managed_inbox(phone_number: '+15551230001', phone_number_id: 'PNID-1')
      keep_inbox, keep_channel, keep_setup = managed_inbox(phone_number: '+15559990000', phone_number_id: 'PNID-2')
      keep_conversation = create(:conversation, account: account, inbox: keep_inbox)

      purge(inbox)

      aggregate_failures do
        expect(Inbox.exists?(keep_inbox.id)).to be(true)
        expect(Channel::Whatsapp.exists?(keep_channel.id)).to be(true)
        expect(Bloomwire::WhatsappSetup.exists?(keep_setup.id)).to be(true)
        expect(Conversation.exists?(keep_conversation.id)).to be(true)
      end
    end

    it 'stops the global webhook router from resolving the number once removed' do
      inbox, _channel, setup = managed_inbox(phone_number_id: 'PNID-ROUTE')
      payload = { 'entry' => [{ 'changes' => [{ 'value' => { 'metadata' => { 'phone_number_id' => 'PNID-ROUTE' } } }] }] }
      expect(Bloomwire::Webhooks::WhatsappRouter.resolve(payload)&.id).to eq(setup.id)

      purge(inbox)

      expect(Bloomwire::Webhooks::WhatsappRouter.resolve(payload)).to be_nil
    end

    it 'makes NO Meta call (managed-source channels skip the webhook teardown)' do
      inbox, = managed_inbox
      expect(Whatsapp::FacebookApiClient).not_to receive(:new)
      purge(inbox)
    end

    it 'frees the number: the local phone_number_taken guard no longer matches after removal' do
      inbox, = managed_inbox(phone_number: '+15551230001')
      expect(Bloomwire::WhatsappPhoneAvailability.status_for('+15551230001')).to eq('already_connected')
      purge(inbox)
      expect(Bloomwire::WhatsappPhoneAvailability.status_for('+15551230001')).to eq('available')
    end
  end

  describe 'concurrency / repeats / retries' do
    it 'is idempotent: a second .purge! after the inbox is gone is a safe no-op' do
      inbox, = managed_inbox
      purge(inbox)
      expect(Inbox.find_by(id: inbox.id)).to be_nil
      expect { purge(inbox) }.not_to raise_error
    end

    it 'is a safe no-op for an unknown / already-deleted inbox id' do
      expect { described_class.purge!(account_id: account.id, inbox_id: -1) }.not_to raise_error
    end

    it 'completes on a retry after a partial run (setup already removed)' do
      inbox, _channel, setup = managed_inbox
      setup.destroy! # simulate a prior run that removed the setup then failed before the inbox
      expect { purge(inbox) }.not_to raise_error
      expect(Inbox.exists?(inbox.id)).to be(false)
    end

    it 'emits a sanitized removal_succeeded audit event when the purge completes' do
      inbox, channel, = managed_inbox
      allow(Rails.logger).to receive(:info)
      purge(inbox)
      expect(Rails.logger).to have_received(:info)
        .with("[BLOOMWIRE WA DEPROVISION] removal_succeeded account=#{account.id} inbox=#{inbox.id} " \
              "channel=#{channel.id} actor=#{admin.id}")
    end

    # (finding 1) RecordNotFound gets the SAME fresh-state rule as RecordNotDestroyed.
    it 'RE-RAISES RecordNotFound (and logs removal_failed) when the inbox still exists (not a real race)' do
      inbox, = managed_inbox
      allow(Rails.logger).to receive(:warn)
      allow(Inbox).to receive(:find_by).and_call_original
      allow(Inbox).to receive(:find_by).with(id: inbox.id).and_return(inbox)
      allow(inbox).to receive(:destroy!).and_raise(ActiveRecord::RecordNotFound)

      expect { purge(inbox) }.to raise_error(ActiveRecord::RecordNotFound)
      expect(Inbox.exists?(inbox.id)).to be(true) # surviving inbox not falsely marked removed
      expect(Rails.logger).to have_received(:warn).with(/removal_failed .*reason=ActiveRecord::RecordNotFound/)
    end

    it 'swallows RecordNotFound ONLY when a fresh DB check proves the inbox is gone (true race)' do
      inbox, = managed_inbox
      allow(Inbox).to receive(:find_by).and_call_original
      allow(Inbox).to receive(:find_by).with(id: inbox.id).and_return(inbox)
      allow(inbox).to receive(:destroy!).and_raise(ActiveRecord::RecordNotFound)
      allow(Inbox).to receive(:exists?).with(inbox.id).and_return(false) # concurrent job already finished it

      expect { purge(inbox) }.not_to raise_error
    end

    # (finding 1) RED->GREEN: a RecordNotDestroyed while the inbox STILL EXISTS must NOT be marked successful — it is
    # logged (sanitized) and re-raised so Sidekiq retries.
    it 'RE-RAISES RecordNotDestroyed (and logs removal_failed) when the inbox survives' do
      inbox, = managed_inbox
      allow(Rails.logger).to receive(:warn)
      allow(Inbox).to receive(:find_by).and_call_original
      allow(Inbox).to receive(:find_by).with(id: inbox.id).and_return(inbox)
      allow(inbox).to receive(:destroy!).and_raise(ActiveRecord::RecordNotDestroyed.new(inbox))

      expect { purge(inbox) }.to raise_error(ActiveRecord::RecordNotDestroyed)
      expect(Inbox.exists?(inbox.id)).to be(true) # not falsely removed
      expect(Rails.logger).to have_received(:warn)
        .with(/removal_failed .*reason=ActiveRecord::RecordNotDestroyed/)
    end

    # If a fresh DB check proves the inbox is genuinely gone, a trailing RecordNotDestroyed is idempotent success.
    it 'treats RecordNotDestroyed as a no-op only when a fresh DB check proves the inbox is gone' do
      inbox, = managed_inbox
      allow(Inbox).to receive(:find_by).and_call_original
      allow(Inbox).to receive(:find_by).with(id: inbox.id).and_return(inbox)
      allow(inbox).to receive(:destroy!).and_raise(ActiveRecord::RecordNotDestroyed.new(inbox))
      allow(Inbox).to receive(:exists?).with(inbox.id).and_return(false) # fresh check: already gone

      expect { purge(inbox) }.not_to raise_error
    end

    it 'logs removal_failed and re-raises an UNEXPECTED error so Sidekiq retries the job' do
      inbox, = managed_inbox
      allow(Rails.logger).to receive(:warn)
      allow(Inbox).to receive(:find_by).and_call_original
      allow(Inbox).to receive(:find_by).with(id: inbox.id).and_return(inbox)
      allow(inbox).to receive(:destroy!).and_raise(StandardError, 'db down')

      expect { purge(inbox) }.to raise_error(StandardError, 'db down')
      expect(Rails.logger).to have_received(:warn).with(/removal_failed .*reason=StandardError/)
    end
  end
end
