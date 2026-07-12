require 'rails_helper'
require 'timeout'

RSpec.describe Bloomwire::WhatsappOnboardingProcessor, '#persist_and_finalize' do
  self.use_transactional_tests = false

  let(:owner) { 'fence-worker' }
  let(:generation) { 0 }
  let(:cleanup_account_ids) { [] }

  after do
    account_ids = cleanup_account_ids
    next if account_ids.empty?

    Bloomwire::WhatsappSetupRequest.where(account_id: account_ids).find_each do |request|
      request.update!(bloomwire_whatsapp_setup: nil)
    end
    Bloomwire::WhatsappOnboardingAttempt.where(account_id: account_ids).delete_all
    Bloomwire::WhatsappSetup.where(account_id: account_ids).delete_all
    Inbox.where(account_id: account_ids).delete_all
    Channel::Whatsapp.where(account_id: account_ids).delete_all
    Account.where(id: account_ids).destroy_all
  end

  def build_context(existing_aggregate: true, bound_audit: false)
    account = create(:account)
    cleanup_account_ids << account.id
    phone_number_id = "PNID-FENCE-#{SecureRandom.hex(4)}"
    phone_digits = "1555#{SecureRandom.random_number(10_000_000).to_s.rjust(7, '0')}"
    setup = build_setup(account, phone_number_id, phone_digits) if existing_aggregate
    seed_original_credential(setup) if setup
    bound_attempt = build_bound_attempt(account, setup, phone_number_id) if bound_audit
    attempt = build_attempt(account, phone_number_id)
    target = persistence_target(phone_number_id, "+#{phone_digits}")
    { account: account, setup: setup, attempt: attempt, bound_attempt: bound_attempt, target: target }
  end

  def build_setup(account, phone_number_id, phone_digits)
    create(
      :bloomwire_whatsapp_setup,
      :ready_for_webhook,
      account: account,
      aligned_phone_number_id: phone_number_id,
      aligned_display_phone_number: phone_digits
    )
  end

  def seed_original_credential(setup)
    channel = setup.channel_whatsapp
    channel.provider_config = channel.provider_config.merge('api_key' => 'ORIGINAL-FENCE-TOKEN')
    channel.save!(validate: false)
  end

  def build_attempt(account, phone_number_id)
    Bloomwire::WhatsappOnboardingAttempt.create!(
      account: account,
      status: Bloomwire::WhatsappOnboardingAttempt::PROCESSING,
      waba_id: 'WABA-FENCE',
      phone_number_id: phone_number_id,
      processing_owner: owner,
      lease_expires_at: 5.minutes.from_now,
      submission_generation: generation
    )
  end

  def build_bound_attempt(account, setup, phone_number_id)
    Bloomwire::WhatsappOnboardingAttempt.create!(
      account: account,
      status: Bloomwire::WhatsappOnboardingAttempt::COMPLETED,
      waba_id: 'WABA-FENCE',
      phone_number_id: phone_number_id,
      inbox: setup.inbox,
      channel_whatsapp: setup.channel_whatsapp
    )
  end

  def persistence_target(phone_number_id, phone_number)
    {
      waba_id: 'WABA-FENCE',
      phone_info: { phone_number_id: phone_number_id, phone_number: phone_number, business_name: 'Fence Test' }
    }
  end

  def processor_for(context, persister: Bloomwire::WhatsappOnboardingPersister.new(context[:account]))
    Bloomwire::WhatsappOnboardingProcessor.new(
      attempt: context[:attempt], owner: owner, generation: generation, persister: persister
    )
  end

  def pause_after_final_renewal(attempt, entered:, resume:)
    renewal = attempt.method(:renew_lease!)
    attempt.define_singleton_method(:renew_lease!) do |**kwargs|
      renewed = renewal.call(**kwargs)
      entered << :renewed
      resume.pop
      renewed
    end
  end

  def pausing_inside_persistence(account, entered:, resume:)
    Class.new(Bloomwire::WhatsappOnboardingPersister) do
      define_method(:initialize) do |target_account|
        super(target_account)
        @entered = entered
        @resume = resume
      end

      define_method(:persist) do |*args|
        @entered << :fence_acquired
        @resume.pop
        super(*args)
      end
    end.new(account)
  end

  def persistence_step(processor, context)
    capability = Bloomwire::WhatsappMessagingCapability::Result.new(status: :ready)
    processor.send(:persist_and_finalize, 'FAKE-FENCE-TOKEN', context[:target], nil, capability)
  rescue Bloomwire::WhatsappOnboardingAttempt::StaleWorkerError, ActiveRecord::StaleObjectError
    :stale
  ensure
    Bloomwire::WhatsappOnboardingAttempt.find(context[:attempt].id)
                                        .release_lease!(owner: owner, expected_generation: generation)
  end

  def wait_for_database_block_or_completion(thread, backend_pid)
    Timeout.timeout(5) do
      loop do
        blockers = ActiveRecord::Base.connection.select_value(
          "SELECT cardinality(pg_blocking_pids(#{Integer(backend_pid)}))"
        ).to_i
        return :blocked if blockers.positive?
        return :completed unless thread.alive?

        Thread.pass
      end
    end
  end

  def finish_threads(*threads)
    Timeout.timeout(10) { threads.each(&:value) }
  end

  def stale_outcome
    yield
  rescue Bloomwire::WhatsappOnboardingAttempt::StaleWorkerError, ActiveRecord::StaleObjectError
    :stale
  end

  it 'does not recreate an aggregate when purge commits after final lease renewal but before persistence' do
    context = build_context
    entered = Queue.new
    resume = Queue.new
    pause_after_final_renewal(context[:attempt], entered: entered, resume: resume)
    processor = processor_for(context)
    expect(context[:attempt].inbox_id).to be_nil
    expect(context[:attempt].channel_whatsapp_id).to be_nil
    expect(Whatsapp::FacebookApiClient).not_to receive(:new)

    worker = Thread.new do
      ActiveRecord::Base.connection_pool.with_connection { persistence_step(processor, context) }
    end

    entered.pop
    begin
      Bloomwire::WhatsappInboxDeprovisionService.purge!(
        account_id: context[:account].id, inbox_id: context[:setup].inbox_id
      )
    ensure
      resume << :continue
    end
    worker.value

    audit = context[:attempt].reload
    aggregate_failures do
      expect(audit.status).to eq(Bloomwire::WhatsappOnboardingAttempt::CANCELLED)
      expect(audit.inbox_id).to be_nil
      expect(audit.channel_whatsapp_id).to be_nil
      expect(Inbox.where(account_id: context[:account].id)).to be_empty
      expect(Channel::Whatsapp.where(account_id: context[:account].id)).to be_empty
      expect(Bloomwire::WhatsappSetup.where(account_id: context[:account].id)).to be_empty
    end
  end

  it 'lets persistence commit under the fence before purge waits and removes the complete aggregate' do
    context = build_context(bound_audit: true)
    fence_acquired = Queue.new
    resume = Queue.new
    locked_attempt_ids = Queue.new
    persister = pausing_inside_persistence(context[:account], entered: fence_acquired, resume: resume)
    processor = processor_for(context, persister: persister)
    allow(Bloomwire::WhatsappInboxDeprovisionService).to receive(:delete_inbox!).and_wrap_original do |original, *args, **kwargs|
      locked_attempt_ids << kwargs.fetch(:attempts).map(&:id)
      original.call(*args, **kwargs)
    end
    expect(context[:attempt].inbox_id).to be_nil
    expect(context[:attempt].channel_whatsapp_id).to be_nil
    expect(context[:bound_attempt].id).to be < context[:attempt].id
    expect(Whatsapp::FacebookApiClient).not_to receive(:new)
    worker = Thread.new do
      ActiveRecord::Base.connection_pool.with_connection { persistence_step(processor, context) }
    end
    fence_acquired.pop

    purge_pid = Queue.new
    purge = Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do |connection|
        purge_pid << connection.raw_connection.backend_pid
        Bloomwire::WhatsappInboxDeprovisionService.purge!(
          account_id: context[:account].id, inbox_id: context[:setup].inbox_id
        )
      end
    end

    outcome = wait_for_database_block_or_completion(purge, purge_pid.pop)
    resume << :continue
    finish_threads(worker, purge)

    audit = context[:attempt].reload
    bound_audit = context[:bound_attempt].reload
    aggregate_failures do
      expect(outcome).to eq(:blocked)
      expect(locked_attempt_ids.pop(true)).to eq([bound_audit.id, audit.id].sort)
      expect(audit.inbox_id).to be_nil
      expect(audit.channel_whatsapp_id).to be_nil
      expect(audit.processing_owner).to be_nil
      expect(audit.lease_expires_at).to be_nil
      expect(bound_audit.inbox_id).to be_nil
      expect(bound_audit.channel_whatsapp_id).to be_nil
      expect(Inbox.where(account_id: context[:account].id)).to be_empty
      expect(Channel::Whatsapp.where(account_id: context[:account].id)).to be_empty
      expect(Bloomwire::WhatsappSetup.where(account_id: context[:account].id)).to be_empty
    end
  end

  {
    'cancelled status' => lambda { |attempt|
      attempt.update!(status: Bloomwire::WhatsappOnboardingAttempt::CANCELLED,
                      processing_owner: nil, lease_expires_at: nil)
    },
    'different owner' => ->(attempt) { attempt.update!(processing_owner: 'new-owner') },
    'different generation' => ->(attempt) { attempt.update!(submission_generation: 1) },
    'expired lease' => ->(attempt) { attempt.update!(lease_expires_at: 1.minute.ago) }
  }.each do |condition, invalidate|
    it "rejects #{condition} inside the persistence transaction before creating local records" do
      context = build_context(existing_aggregate: false)
      invalidate.call(context[:attempt])
      context[:attempt].define_singleton_method(:renew_lease!) { |**| true }

      outcome = persistence_step(processor_for(context), context)

      aggregate_failures do
        expect(outcome).to eq(:stale)
        expect(Channel::Whatsapp.where(account_id: context[:account].id)).to be_empty
        expect(Inbox.where(account_id: context[:account].id)).to be_empty
        expect(Bloomwire::WhatsappSetup.where(account_id: context[:account].id)).to be_empty
      end
    end
  end

  it 'guards mark_processing against a worker that no longer owns the attempt' do
    context = build_context(existing_aggregate: false)
    context[:attempt].update!(processing_owner: 'new-owner')

    outcome = stale_outcome { processor_for(context).send(:mark_processing) }

    aggregate_failures do
      expect(outcome).to eq(:stale)
      expect(context[:attempt].reload.status).to eq(Bloomwire::WhatsappOnboardingAttempt::PROCESSING)
      expect(context[:attempt].safe_error_code).to be_nil
    end
  end

  it 'guards record_safe_error against a worker that no longer owns the attempt' do
    context = build_context(existing_aggregate: false)
    context[:attempt].update!(processing_owner: 'new-owner')

    outcome = stale_outcome { processor_for(context).send(:record_safe_error, :meta_timeout) }

    aggregate_failures do
      expect(outcome).to eq(:stale)
      expect(context[:attempt].reload.safe_error_code).to be_nil
      expect(context[:attempt].status).to eq(Bloomwire::WhatsappOnboardingAttempt::PROCESSING)
    end
  end

  it 'guards terminal status and secret cleanup against a worker that no longer owns the attempt' do
    context = build_context(existing_aggregate: false)
    context[:attempt].update!(processing_owner: 'new-owner')

    outcome = stale_outcome { processor_for(context).send(:terminal_missing_code) }

    aggregate_failures do
      expect(outcome).to eq(:stale)
      expect(context[:attempt].reload.status).to eq(Bloomwire::WhatsappOnboardingAttempt::PROCESSING)
      expect(context[:attempt].safe_error_code).to be_nil
    end
  end

  it 'rolls mapping writes back with the attempt linkage when finalization fails inside the fence' do
    context = build_context
    original_setup = context[:setup].reload.attributes
    original_channel = context[:setup].channel_whatsapp.reload.attributes
    original_links = [context[:attempt].inbox_id, context[:attempt].channel_whatsapp_id]
    context[:attempt].define_singleton_method(:finalize_persisted_setup!) do |*, **|
      raise 'forced attempt finalization failure'
    end

    expect(persistence_step(processor_for(context), context)).to be_nil

    audit = context[:attempt].reload
    aggregate_failures do
      expect(context[:setup].reload.attributes).to eq(original_setup)
      expect(context[:setup].channel_whatsapp.reload.attributes).to eq(original_channel)
      expect([audit.inbox_id, audit.channel_whatsapp_id]).to eq(original_links)
      expect(audit.status).to eq(Bloomwire::WhatsappOnboardingAttempt::PROCESSING)
      expect(audit.safe_error_code).to eq('meta_error')
      expect(Inbox.where(account_id: context[:account].id).count).to eq(1)
      expect(Channel::Whatsapp.where(account_id: context[:account].id).count).to eq(1)
      expect(Bloomwire::WhatsappSetup.where(account_id: context[:account].id).count).to eq(1)
    end
  end
end
