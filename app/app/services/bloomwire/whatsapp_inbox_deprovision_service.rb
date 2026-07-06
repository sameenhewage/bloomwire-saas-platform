# Admin-facing "Remove WhatsApp Inbox" deprovision for Bloomwire managed mode. Permanently removes ALL Bloomwire
# database data owned by a managed WhatsApp inbox — WITHOUT touching Meta (no WABA delete, no number deregister, no
# webhook unsubscribe) and WITHOUT deleting shared Contact records.
#
# Two phases:
#   `#prepare` (SYNCHRONOUS, request path): authorize/verify account + managed source, BLOCK ROUTING (commit
#     Bloomwire::WhatsappSetup.setup_status -> 'blocked' so the global router — which routes only ready_for_webhook
#     rows — stops immediately), then ENQUEUE the deletion job and VERIFY the enqueue was accepted before returning
#     success. If the enqueue is NOT accepted, routing is RESTORED to its prior status (deterministic: nothing was
#     deleted, the inbox is fully routeable again) and a retriable error is returned — the caller never sees
#     `removal_started` for an unconfirmed job.
#   `.purge!` (ASYNCHRONOUS, job): the heavy, retry-safe, idempotent deletion. Re-verifies state on every run,
#     removes the setup mapping (else orphaned) and destroys the inbox — cascading its owned dependents
#     (conversations, messages, contact_inboxes, inbox members, reporting events, webhooks) and the
#     Channel::Whatsapp (Inbox `belongs_to :channel, dependent: :destroy`). Shared Contact records are preserved
#     (only ContactInbox join rows are removed). The historical purge is done in SMALL BATCHES — there is NO single
#     giant transaction over the whole message/conversation history.
#
# Meta boundary: only channels created by the managed flow (`provider_config['source'] == 'bloomwire_managed'`) are
# deprovisioned. Those channels SKIP `Channel::Whatsapp#teardown_webhooks` (which only fires for `embedded_signup`
# source), so destroying them makes NO Meta call. A non-managed channel is refused (:not_managed).
#
# Errors / retries: `.purge!` no-ops when the inbox is already gone (concurrent/duplicate/retried job). A
# `RecordNotFound` from a row vanishing mid-run is a safe no-op. A `RecordNotDestroyed` (e.g. a destroy callback
# aborted) is NOT treated as success unless a fresh DB check proves the inbox is already gone — otherwise it is
# logged (sanitized) and RE-RAISED so Sidekiq retries. All state transitions emit sanitized audit events.
class Bloomwire::WhatsappInboxDeprovisionService
  MANAGED_SOURCE = 'bloomwire_managed'.freeze
  BLOCKED_STATUS = 'blocked'.freeze
  BATCH_SIZE = 500

  Result = Struct.new(:error, keyword_init: true) do
    def success?
      error.nil?
    end
  end

  def initialize(account:, inbox:, actor: nil)
    @account = account
    @inbox = inbox
    @actor = actor
  end

  # SYNC: short request path — authorize/verify, then (SERIALIZED per setup row) block routing, enqueue, and verify
  # acceptance. The block/enqueue/restore decision runs under a row lock so two concurrent requests cannot
  # interleave; a failed request re-reads the CURRENT committed status under the lock, so it can never restore
  # (reopen) routing that another already-ACCEPTED request blocked.
  def prepare
    error = precheck
    return Result.new(error: error) if error

    channel = @inbox.channel
    setup = setup_for(channel)
    # No routing row -> nothing to serialize; just enqueue + verify.
    return finalize_enqueue(channel, setup: nil, prior_status: nil) if setup.nil?

    outcome = nil
    setup.with_lock do
      prior_status = setup.setup_status # committed current status, read under the row lock
      self.class.block_routing!(setup)
      outcome = finalize_enqueue(channel, setup: setup, prior_status: prior_status)
    end
    outcome
  end

  # ASYNC (job entrypoint): idempotent, retry-safe, NO giant transaction. Safe to run twice / concurrently.
  def self.purge!(account_id:, inbox_id:, actor_id: nil)
    inbox = Inbox.find_by(id: inbox_id)
    # Already gone (or a foreign id) -> nothing to do. Idempotent path for repeats/retries.
    return if inbox.nil? || inbox.account_id != account_id

    channel = inbox.channel
    # Defense in depth: never deprovision (and never Meta-call for) a non-managed channel.
    return unless channel.is_a?(Channel::Whatsapp) && managed?(channel)

    delete_managed_inbox!(inbox, channel)
    audit(:removal_succeeded, account_id: account_id, inbox_id: inbox_id, channel_id: channel.id, actor_id: actor_id)
  rescue ActiveRecord::RecordNotFound, ActiveRecord::RecordNotDestroyed => e
    # Neither exception is proof that another job removed the TARGET inbox — either can come from a vanished child,
    # a halted destroy callback, or a partial purge. Treat as idempotent success ONLY when a fresh DB check proves
    # the inbox is truly gone; otherwise log a sanitized failure and re-raise so Sidekiq retries (never mark a
    # surviving, partially-purged, blocked inbox "removed").
    return unless Inbox.exists?(inbox_id)

    audit(:removal_failed, account_id: account_id, inbox_id: inbox_id, actor_id: actor_id, reason: e.class.name)
    raise
  rescue StandardError => e
    audit(:removal_failed, account_id: account_id, inbox_id: inbox_id, actor_id: actor_id, reason: e.class.name)
    raise
  end

  def self.delete_managed_inbox!(inbox, channel)
    setup = Bloomwire::WhatsappSetup.find_by(channel_whatsapp_id: channel.id)
    block_routing!(setup) # keep routing blocked even if a retry lands after the setup was re-created
    setup&.destroy!
    # Batched purge — each record destroy! is its own small transaction (no single transaction over the whole
    # history). Ordered by FK dependency; shared Contacts are never touched (only ContactInbox joins).
    purge_heavy_children(inbox)
    inbox.destroy! # cascades remaining owned dependents + the Channel::Whatsapp
  end

  def self.managed?(channel)
    (channel.provider_config || {})['source'] == MANAGED_SOURCE
  end

  # Commit the routing block immediately (its own statement). The row is still valid at block time, so update!
  # re-validates cleanly; a routeable row simply becomes non-routeable (router only routes ready_for_webhook).
  def self.block_routing!(setup)
    setup.update!(setup_status: BLOCKED_STATUS) if setup && setup.setup_status != BLOCKED_STATUS
  end

  # Restore a previously-captured routing status (used to make the state deterministic when an enqueue fails).
  def self.restore_routing!(setup, prior_status)
    return if setup.nil? || prior_status.nil? || setup.setup_status == prior_status

    setup.update!(setup_status: prior_status)
  end

  def self.purge_heavy_children(inbox)
    [inbox.messages, inbox.conversations, inbox.contact_inboxes, inbox.reporting_events].each do |relation|
      relation.find_in_batches(batch_size: BATCH_SIZE) do |batch|
        batch.each(&:destroy!)
      end
    end
  end

  # ActiveJob#perform_later returns `false` when a callback halted enqueuing, otherwise the job (whose
  # `successfully_enqueued?` confirms the adapter accepted it). Treat anything else as a failed enqueue.
  def self.enqueue_accepted?(job)
    return false unless job
    return job.successfully_enqueued? if job.respond_to?(:successfully_enqueued?)

    true
  end

  # Sanitized audit trail: internal ids + actor + (for failures) the error class only. NEVER the phone number,
  # phone_number_id, WABA id, display number, or any token. `extra` may carry :channel_id, :actor_id, :reason.
  def self.audit(event, account_id:, inbox_id:, **extra)
    line = "[BLOOMWIRE WA DEPROVISION] #{event} account=#{account_id} inbox=#{inbox_id} " \
           "channel=#{extra[:channel_id] || '-'} actor=#{extra[:actor_id] || 'system'}"
    line += " reason=#{extra[:reason]}" if extra[:reason]
    event == :removal_failed ? Rails.logger.warn(line) : Rails.logger.info(line)
  end

  private

  def precheck
    return :not_found if @inbox.nil? || @inbox.account_id != @account.id

    channel = @inbox.channel
    return :not_whatsapp unless channel.is_a?(Channel::Whatsapp)
    # Meta safety: only managed-source channels (they skip the Meta webhook teardown on destroy).
    return :not_managed unless self.class.managed?(channel)

    nil
  end

  # Enqueue + verify acceptance. On a confirmed failure (false / not successfully_enqueued? / raised), restore the
  # prior routing status (deterministic) and emit a sanitized `removal_failed` audit; return a retriable error.
  def finalize_enqueue(channel, setup:, prior_status:)
    job = enqueue_deletion
    unless self.class.enqueue_accepted?(job)
      self.class.restore_routing!(setup, prior_status)
      self.class.audit(:removal_failed, account_id: @account.id, inbox_id: @inbox.id, channel_id: channel.id,
                                        actor_id: @actor&.id, reason: @enqueue_error || 'enqueue_not_accepted')
      return Result.new(error: :enqueue_failed)
    end

    self.class.audit(:removal_started, account_id: @account.id, inbox_id: @inbox.id, channel_id: channel.id,
                                       actor_id: @actor&.id)
    Result.new
  end

  def enqueue_deletion
    @enqueue_error = nil
    Bloomwire::WhatsappInboxDeprovisionJob.perform_later(
      account_id: @account.id, inbox_id: @inbox.id, actor_id: @actor&.id
    )
  rescue StandardError => e
    # A raised enqueue (adapter/broker error) is a confirmed failure — record the class for the audit.
    @enqueue_error = e.class.name
    nil
  end

  def setup_for(channel)
    Bloomwire::WhatsappSetup.find_by(channel_whatsapp_id: channel.id)
  end
end
