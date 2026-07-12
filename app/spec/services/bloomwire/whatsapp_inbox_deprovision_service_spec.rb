require 'rails_helper'

# Two-phase Bloomwire WhatsApp inbox removal (ANY source: managed, embedded_signup, legacy/manual, or missing): a
# short synchronous #prepare (authorize/verify, block routing, enqueue) and an async, retry-safe, idempotent
# .purge! (heavy deletion, no orphans, no shared-Contact loss, and NO Meta call for any source).
RSpec.describe Bloomwire::WhatsappInboxDeprovisionService do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }

  # A WhatsApp inbox for the given source (managed / embedded_signup / legacy-missing): a whatsapp_cloud channel
  # (+ its inbox) and, by default, an aligned routeable Bloomwire::WhatsappSetup. Fake routing identifiers only.
  # source: nil omits the provider_config 'source' key (legacy); api_key/waba_id: nil model a dead/asset-gone inbox.
  # rubocop:disable Metrics/ParameterLists
  def whatsapp_inbox(on: account, phone_number: '+15551230001', phone_number_id: 'PNID-1', waba_id: 'WABA-1',
                     source: 'bloomwire_managed', api_key: 'FAKE-KEY', with_setup: true)
    channel = create(:channel_whatsapp, account: on, provider: 'whatsapp_cloud', phone_number: phone_number,
                                        sync_templates: false, validate_provider_config: false)
    channel.provider_config = {
      'source' => source, 'phone_number_id' => phone_number_id,
      'business_account_id' => waba_id, 'api_key' => api_key
    }.compact
    channel.save!(validate: false)
    inbox = channel.inbox
    setup = with_setup && create(:bloomwire_whatsapp_setup, account: on, inbox: inbox, channel_whatsapp: channel,
                                                            phone_number_id: phone_number_id, waba_id: waba_id,
                                                            display_phone_number: phone_number,
                                                            setup_status: 'ready_for_webhook')
    [inbox, channel, setup || nil]
  end
  # rubocop:enable Metrics/ParameterLists

  # Backwards-compatible alias: the managed-source inbox used across the existing examples.
  def managed_inbox(**)
    whatsapp_inbox(source: 'bloomwire_managed', **)
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

    it 'ACCEPTS an embedded_signup WhatsApp channel (no longer managed-only): blocks routing + enqueues' do
      inbox, _channel, setup = whatsapp_inbox(source: 'embedded_signup')
      expect do
        expect(service(inbox).prepare).to be_success
      end.to have_enqueued_job(Bloomwire::WhatsappInboxDeprovisionJob)
      expect(setup.reload.setup_status).to eq('blocked')
    end

    it 'ACCEPTS a legacy WhatsApp channel with NO source key and no routing row' do
      inbox, = whatsapp_inbox(source: nil, with_setup: false)
      expect { expect(service(inbox).prepare).to be_success }
        .to have_enqueued_job(Bloomwire::WhatsappInboxDeprovisionJob)
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
    it 'detaches a terminal onboarding attempt and removes the complete inbox aggregate' do
      inbox, channel, setup = managed_inbox
      attempt = Bloomwire::WhatsappOnboardingAttempt.create!(
        account: account, status: 'completed', inbox: inbox, channel_whatsapp: channel
      )

      expect { purge(inbox) }.not_to raise_error

      aggregate_failures do
        expect(attempt.reload.inbox_id).to be_nil
        expect(attempt.channel_whatsapp_id).to be_nil
        expect(Inbox.exists?(inbox.id)).to be(false)
        expect(Channel::Whatsapp.exists?(channel.id)).to be(false)
        expect(Bloomwire::WhatsappSetup.exists?(setup.id)).to be(false)
      end
    end

    it 'cancels and detaches an active onboarding attempt before removing its aggregate' do
      inbox, channel, = managed_inbox
      attempt = Bloomwire::WhatsappOnboardingAttempt.create!(
        account: account, status: 'processing', inbox: inbox, channel_whatsapp: channel,
        processing_owner: 'worker-1', lease_expires_at: 1.minute.from_now, job_enqueued_at: Time.current
      )

      purge(inbox)

      aggregate_failures do
        expect(attempt.reload.status).to eq('cancelled')
        expect(attempt.inbox_id).to be_nil
        expect(attempt.channel_whatsapp_id).to be_nil
        expect(attempt.processing_owner).to be_nil
        expect(attempt.lease_expires_at).to be_nil
        expect(attempt.job_enqueued_at).to be_nil
        expect(attempt.secrets_cleared_at).to be_present
      end
    end

    it 'detaches a linked setup request before removing its technical setup' do
      inbox, channel, setup = managed_inbox
      setup_request = Bloomwire::WhatsappSetupRequest.create!(
        account: account, status: 'completed', bloomwire_whatsapp_setup: setup
      )

      expect { purge(inbox) }.not_to raise_error

      aggregate_failures do
        expect(setup_request.reload.bloomwire_whatsapp_setup_id).to be_nil
        expect(Inbox.exists?(inbox.id)).to be(false)
        expect(Channel::Whatsapp.exists?(channel.id)).to be(false)
        expect(Bloomwire::WhatsappSetup.exists?(setup.id)).to be(false)
      end
    end

    it 'rolls back every local mutation when a destructive step fails' do
      inbox, channel, setup = managed_inbox
      contact = create(:contact, account: account)
      contact_inbox = create(:contact_inbox, contact: contact, inbox: inbox)
      conversation = create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox)
      message = create(:message, account: account, inbox: inbox, conversation: conversation)
      reporting_event = create(:reporting_event, account: account, inbox: inbox, conversation: conversation)
      setup_request = Bloomwire::WhatsappSetupRequest.create!(
        account: account, status: 'completed', bloomwire_whatsapp_setup: setup
      )
      attempt = Bloomwire::WhatsappOnboardingAttempt.create!(
        account: account, status: 'completed', inbox: inbox, channel_whatsapp: channel
      )
      allow(Rails.logger).to receive(:warn)
      allow(described_class).to receive(:purge_heavy_children).and_wrap_original do |original, target|
        original.call(target)
        raise StandardError, 'FAKE-TOKEN +15551230001 RAW-CUSTOMER-PAYLOAD'
      end

      expect { purge(inbox) }.to raise_error(StandardError)

      aggregate_failures do
        expect(Bloomwire::WhatsappSetup.exists?(setup.id)).to be(true)
        expect(setup.reload.setup_status).to eq('ready_for_webhook')
        expect(setup_request.reload.bloomwire_whatsapp_setup_id).to eq(setup.id)
        expect(Inbox.exists?(inbox.id)).to be(true)
        expect(Channel::Whatsapp.exists?(channel.id)).to be(true)
        expect(ContactInbox.exists?(contact_inbox.id)).to be(true)
        expect(Conversation.exists?(conversation.id)).to be(true)
        expect(Message.exists?(message.id)).to be(true)
        expect(ReportingEvent.exists?(reporting_event.id)).to be(true)
        expect(attempt.reload.inbox_id).to eq(inbox.id)
        expect(attempt.channel_whatsapp_id).to eq(channel.id)
      end
      expect(Rails.logger).to have_received(:warn).with(
        satisfy do |line|
          line.include?('removal_failed') && line.include?('reason=StandardError') &&
            line.exclude?('FAKE-TOKEN') && line.exclude?('15551230001') && line.exclude?('RAW-CUSTOMER-PAYLOAD')
        end
      )
    end

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

    it 'leaves another account and its inbox aggregate untouched' do
      inbox, = managed_inbox(phone_number: '+15551230001', phone_number_id: 'PNID-1')
      other_account = create(:account)
      keep_inbox, keep_channel, keep_setup = managed_inbox(
        on: other_account, phone_number: '+15559990000', phone_number_id: 'PNID-2'
      )
      keep_conversation = create(:conversation, account: other_account, inbox: keep_inbox)
      keep_attempt = Bloomwire::WhatsappOnboardingAttempt.create!(
        account: other_account, status: 'completed', inbox: keep_inbox, channel_whatsapp: keep_channel
      )

      purge(inbox)

      aggregate_failures do
        expect(Inbox.exists?(keep_inbox.id)).to be(true)
        expect(Channel::Whatsapp.exists?(keep_channel.id)).to be(true)
        expect(Bloomwire::WhatsappSetup.exists?(keep_setup.id)).to be(true)
        expect(Conversation.exists?(keep_conversation.id)).to be(true)
        expect(keep_attempt.reload.inbox_id).to eq(keep_inbox.id)
        expect(keep_attempt.channel_whatsapp_id).to eq(keep_channel.id)
      end
    end

    it 'stops the global webhook router from resolving the number once removed' do
      inbox, _channel, setup = managed_inbox(phone_number_id: 'PNID-ROUTE')
      payload = { 'entry' => [{ 'changes' => [{ 'value' => { 'metadata' => { 'phone_number_id' => 'PNID-ROUTE' } } }] }] }
      expect(Bloomwire::Webhooks::WhatsappRouter.resolve(payload)&.id).to eq(setup.id)

      purge(inbox)

      expect(Bloomwire::Webhooks::WhatsappRouter.resolve(payload)).to be_nil
    end

    it 'makes no Meta, registration, webhook, onboarding, or provider API call' do
      inbox, = managed_inbox
      expect(Whatsapp::FacebookApiClient).not_to receive(:new)
      expect(Whatsapp::WebhookTeardownService).not_to receive(:new)
      expect(Whatsapp::WebhookSetupService).not_to receive(:new)
      expect(Whatsapp::TokenExchangeService).not_to receive(:new)
      expect(Bloomwire::WhatsappOnboardingProcessor).not_to receive(:new)
      purge(inbox)
    end

    # The crux of the generalization: an embedded_signup channel WITH live-looking creds would normally fire
    # Channel::Whatsapp#teardown_webhooks -> a real Meta unsubscribe call. The Bloomwire delete must skip it.
    it 'makes NO Meta call for an embedded_signup channel (webhook teardown is skipped for every source)' do
      inbox, = whatsapp_inbox(source: 'embedded_signup', api_key: 'FAKE-KEY', waba_id: 'WABA-EMBED')
      expect(Whatsapp::FacebookApiClient).not_to receive(:new)
      purge(inbox)
      expect(Inbox.exists?(inbox.id)).to be(false)
    end

    it 'removes a legacy inbox whose Meta assets are already gone (missing source, no creds) without failing' do
      inbox, channel, = whatsapp_inbox(source: nil, api_key: nil, waba_id: nil, with_setup: false)
      expect(Whatsapp::FacebookApiClient).not_to receive(:new)
      expect { purge(inbox) }.not_to raise_error
      aggregate_failures do
        expect(Inbox.exists?(inbox.id)).to be(false)
        expect(Channel::Whatsapp.exists?(channel.id)).to be(false)
      end
    end

    it 'destroys an orphan-prone setup mapping keyed only by inbox_id (no orphaned routing row)' do
      inbox, channel, = whatsapp_inbox(with_setup: false)
      setup = create(:bloomwire_whatsapp_setup, account: account, inbox: inbox, setup_status: 'pending')
      purge(inbox)
      aggregate_failures do
        expect(Bloomwire::WhatsappSetup.exists?(setup.id)).to be(false)
        expect(Inbox.exists?(inbox.id)).to be(false)
        expect(Channel::Whatsapp.exists?(channel.id)).to be(false)
      end
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
      inbox, channel, = managed_inbox
      attempt = Bloomwire::WhatsappOnboardingAttempt.create!(
        account: account, status: 'completed', inbox: inbox, channel_whatsapp: channel
      )
      purge(inbox)
      detached_attributes = attempt.reload.attributes

      expect { purge(inbox) }.not_to raise_error
      aggregate_failures do
        expect(Inbox.find_by(id: inbox.id)).to be_nil
        expect(Channel::Whatsapp.find_by(id: channel.id)).to be_nil
        expect(attempt.reload.attributes).to eq(detached_attributes)
      end
    end

    it 'is a safe no-op for an unknown / already-deleted inbox id' do
      expect { described_class.purge!(account_id: account.id, inbox_id: -1) }.not_to raise_error
    end

    it 'safely completes on retry after a rolled-back destructive failure' do
      inbox, channel, setup = managed_inbox
      conversation = create(:conversation, account: account, inbox: inbox)
      message = create(:message, account: account, inbox: inbox, conversation: conversation)
      attempt = Bloomwire::WhatsappOnboardingAttempt.create!(
        account: account, status: 'completed', inbox: inbox, channel_whatsapp: channel
      )
      purge_calls = 0
      allow(described_class).to receive(:purge_heavy_children).and_wrap_original do |original, target|
        original.call(target)
        purge_calls += 1
        raise StandardError, 'transient database failure' if purge_calls == 1
      end

      expect { purge(inbox) }.to raise_error(StandardError, 'transient database failure')
      expect { purge(inbox) }.not_to raise_error

      aggregate_failures do
        expect(Inbox.exists?(inbox.id)).to be(false)
        expect(Channel::Whatsapp.exists?(channel.id)).to be(false)
        expect(Bloomwire::WhatsappSetup.exists?(setup.id)).to be(false)
        expect(Conversation.exists?(conversation.id)).to be(false)
        expect(Message.exists?(message.id)).to be(false)
        expect(attempt.reload.inbox_id).to be_nil
        expect(attempt.channel_whatsapp_id).to be_nil
      end
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
      allow(described_class).to receive(:delete_inbox!).and_raise(ActiveRecord::RecordNotFound)

      expect { purge(inbox) }.to raise_error(ActiveRecord::RecordNotFound)
      expect(Inbox.exists?(inbox.id)).to be(true) # surviving inbox not falsely marked removed
      expect(Rails.logger).to have_received(:warn).with(/removal_failed .*reason=ActiveRecord::RecordNotFound/)
    end

    it 'swallows RecordNotFound ONLY when a fresh DB check proves the inbox is gone (true race)' do
      inbox, = managed_inbox
      allow(described_class).to receive(:delete_inbox!).and_raise(ActiveRecord::RecordNotFound)
      allow(Inbox).to receive(:exists?).with(inbox.id).and_return(false) # concurrent job already finished it

      expect { purge(inbox) }.not_to raise_error
    end

    # (finding 1) RED->GREEN: a RecordNotDestroyed while the inbox STILL EXISTS must NOT be marked successful — it is
    # logged (sanitized) and re-raised so Sidekiq retries.
    it 'RE-RAISES RecordNotDestroyed (and logs removal_failed) when the inbox survives' do
      inbox, = managed_inbox
      allow(Rails.logger).to receive(:warn)
      allow(described_class).to receive(:delete_inbox!).and_raise(ActiveRecord::RecordNotDestroyed.new(inbox))

      expect { purge(inbox) }.to raise_error(ActiveRecord::RecordNotDestroyed)
      expect(Inbox.exists?(inbox.id)).to be(true) # not falsely removed
      expect(Rails.logger).to have_received(:warn)
        .with(/removal_failed .*reason=ActiveRecord::RecordNotDestroyed/)
    end

    # If a fresh DB check proves the inbox is genuinely gone, a trailing RecordNotDestroyed is idempotent success.
    it 'treats RecordNotDestroyed as a no-op only when a fresh DB check proves the inbox is gone' do
      inbox, = managed_inbox
      allow(described_class).to receive(:delete_inbox!).and_raise(ActiveRecord::RecordNotDestroyed.new(inbox))
      allow(Inbox).to receive(:exists?).with(inbox.id).and_return(false) # fresh check: already gone

      expect { purge(inbox) }.not_to raise_error
    end

    it 'logs removal_failed and re-raises an UNEXPECTED error so Sidekiq retries the job' do
      inbox, = managed_inbox
      allow(Rails.logger).to receive(:warn)
      allow(described_class).to receive(:delete_inbox!).and_raise(StandardError, 'db down')

      expect { purge(inbox) }.to raise_error(StandardError, 'db down')
      expect(Rails.logger).to have_received(:warn).with(/removal_failed .*reason=StandardError/)
    end
  end
end
