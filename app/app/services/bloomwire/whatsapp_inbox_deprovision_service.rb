# Admin-facing "Remove WhatsApp Inbox" deprovision for Bloomwire managed mode. Permanently removes ALL Bloomwire
# database data owned by a managed WhatsApp inbox — WITHOUT touching Meta (no WABA delete, no number deregister, no
# webhook unsubscribe) and WITHOUT deleting shared Contact records.
#
# Two phases:
#   `#prepare` (SYNCHRONOUS, request path): authorize/verify account + managed source, BLOCK ROUTING (commit
#     Bloomwire::WhatsappSetup.setup_status -> 'blocked' so the global router — which routes only ready_for_webhook
#     rows — stops immediately), then enqueue the deletion job. Returns fast; the request never does heavy work.
#   `.purge!` (ASYNCHRONOUS, job): the heavy, retry-safe, idempotent deletion. Re-verifies state on every run,
#     removes the setup mapping (else orphaned) and destroys the inbox — which cascades its owned dependents
#     (conversations, messages, contact_inboxes, inbox members, reporting events, webhooks) and the
#     Channel::Whatsapp (Inbox `belongs_to :channel, dependent: :destroy`). Shared Contact records are preserved
#     (only ContactInbox join rows are removed). The historical purge is done in SMALL BATCHES — there is NO single
#     giant transaction wrapping the whole message/conversation history.
#
# Meta boundary: only channels created by the managed flow (`provider_config['source'] == 'bloomwire_managed'`) are
# deprovisioned. Those channels SKIP `Channel::Whatsapp#teardown_webhooks` (which only fires for `embedded_signup`
# source), so destroying them makes NO Meta call. A non-managed channel is refused (:not_managed).
#
# Concurrency / retries: `.purge!` re-fetches state and no-ops when the inbox is already gone, and rescues the races
# from a concurrent/duplicate job, so repeated or retried runs are safe.
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

  # SYNC: short request path — authorize/verify, block routing (committed), enqueue the async deletion.
  def prepare
    error = precheck
    return Result.new(error: error) if error

    self.class.block_routing!(setup_for(@inbox.channel))
    Bloomwire::WhatsappInboxDeprovisionJob.perform_later(
      account_id: @account.id, inbox_id: @inbox.id, actor_id: @actor&.id
    )
    Result.new
  end

  # ASYNC (job entrypoint): idempotent, retry-safe, NO giant transaction. Safe to run twice / concurrently.
  def self.purge!(account_id:, inbox_id:, actor_id: nil)
    inbox = Inbox.find_by(id: inbox_id)
    # Already gone (or a foreign id) -> nothing to do. This is the idempotent path for repeats/retries.
    return if inbox.nil? || inbox.account_id != account_id

    channel = inbox.channel
    # Defense in depth: never deprovision (and never Meta-call for) a non-managed channel.
    return unless channel.is_a?(Channel::Whatsapp) && managed?(channel)

    setup = Bloomwire::WhatsappSetup.find_by(channel_whatsapp_id: channel.id)
    block_routing!(setup) # keep routing blocked even if a retry lands after the setup was re-created
    setup&.destroy!

    # Batched purge — each record destroy! is its own small transaction (no single transaction over the whole
    # history). Ordered by FK dependency; shared Contacts are never touched (only ContactInbox joins).
    purge_heavy_children(inbox)

    inbox.destroy! # cascades remaining owned dependents + the Channel::Whatsapp
    audit(account_id: account_id, inbox_id: inbox_id, channel_id: channel.id, actor_id: actor_id)
  rescue ActiveRecord::RecordNotFound, ActiveRecord::RecordNotDestroyed
    # A concurrent/duplicate job already removed it mid-run — safe, idempotent no-op.
    nil
  end

  def self.managed?(channel)
    (channel.provider_config || {})['source'] == MANAGED_SOURCE
  end

  # Commit the routing block immediately (its own statement/transaction). The row is still valid at block time, so
  # update! re-validates cleanly; a routeable row simply becomes non-routeable (router only routes ready_for_webhook).
  def self.block_routing!(setup)
    setup.update!(setup_status: BLOCKED_STATUS) if setup && setup.setup_status != BLOCKED_STATUS
  end

  def self.purge_heavy_children(inbox)
    [inbox.messages, inbox.conversations, inbox.contact_inboxes, inbox.reporting_events].each do |relation|
      relation.find_in_batches(batch_size: BATCH_SIZE) do |batch|
        batch.each(&:destroy!)
      end
    end
  end

  # Sanitized audit trail: internal ids + actor only. NEVER the phone number, phone_number_id, WABA id, or any token.
  def self.audit(account_id:, inbox_id:, channel_id:, actor_id:)
    Rails.logger.info(
      '[BLOOMWIRE WA DEPROVISION] removed managed WhatsApp inbox ' \
      "account=#{account_id} inbox=#{inbox_id} channel=#{channel_id} actor=#{actor_id || 'system'}"
    )
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

  def setup_for(channel)
    Bloomwire::WhatsappSetup.find_by(channel_whatsapp_id: channel.id)
  end
end
