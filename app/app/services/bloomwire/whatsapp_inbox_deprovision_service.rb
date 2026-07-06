# Admin-facing "Remove WhatsApp Inbox" deprovision for Bloomwire managed mode. Permanently removes ALL Bloomwire
# database data owned by a managed WhatsApp inbox — WITHOUT touching Meta (no WABA delete, no number deregister, no
# webhook unsubscribe) and WITHOUT deleting shared Contact records.
#
# Order (routing safety):
#   1. Block the Bloomwire::WhatsappSetup (setup_status -> 'blocked', committed immediately) so the GLOBAL webhook
#      router stops resolving this phone_number_id to the inbox being deleted (the router only routes
#      `ready_for_webhook` rows).
#   2. Destroy the setup mapping explicitly (it has NO dependent cleanup from inbox/channel, so it would orphan).
#   3. Destroy the inbox, which cascades its owned dependents (conversations, messages, contact_inboxes, inbox
#      members, reporting events, webhooks, campaigns) and the Channel::Whatsapp (Inbox `belongs_to :channel,
#      dependent: :destroy`). Shared Contact records are preserved (only the ContactInbox join rows are removed).
#
# Meta boundary: only channels created by the managed flow (`provider_config['source'] == 'bloomwire_managed'`) are
# deprovisioned. Those channels SKIP `Channel::Whatsapp#teardown_webhooks` (which only fires for `embedded_signup`
# source), so destroying them makes NO Meta call. A non-managed channel is refused (:not_managed).
#
# Idempotent: re-running after the inbox is gone is a safe no-op at the controller (404); a mid-way retry re-finds
# state and skips already-removed rows. Never raises to the caller — returns a safe Result.
class Bloomwire::WhatsappInboxDeprovisionService
  MANAGED_SOURCE = 'bloomwire_managed'.freeze
  BLOCKED_STATUS = 'blocked'.freeze
  BATCH_SIZE = 5_000

  Result = Struct.new(:error, :inbox_id, keyword_init: true) do
    def success?
      error.nil?
    end
  end

  def initialize(account:, inbox:, actor: nil)
    @account = account
    @inbox = inbox
    @actor = actor
  end

  def perform
    error = precheck
    return Result.new(error: error) if error

    channel = @inbox.channel
    setup = Bloomwire::WhatsappSetup.find_by(channel_whatsapp_id: channel.id)
    inbox_id = @inbox.id
    channel_id = channel.id

    # 1) Block routing FIRST and commit it immediately so the router stops now. The row is still fully valid at
    #    this point (only the status changes to a non-routeable value), so update! is safe and re-validates cleanly.
    setup.update!(setup_status: BLOCKED_STATUS) if setup && setup.setup_status != BLOCKED_STATUS

    # 2) + 3) Remove the mapping and the inbox (+ cascaded dependents + channel) atomically.
    ActiveRecord::Base.transaction do
      setup&.destroy!
      purge_heavy_children(@inbox)
      @inbox.destroy!
    end

    audit(inbox_id: inbox_id, channel_id: channel_id)
    Result.new(inbox_id: inbox_id)
  rescue ActiveRecord::RecordNotFound
    # A concurrent deprovision already removed it — idempotent, treat as gone.
    Result.new(error: :not_found)
  end

  private

  def precheck
    return :not_found if @inbox.nil? || @inbox.account_id != @account.id

    channel = @inbox.channel
    return :not_whatsapp unless channel.is_a?(Channel::Whatsapp)
    # Meta safety: only managed-source channels (they skip the Meta webhook teardown on destroy).
    return :not_managed unless (channel.provider_config || {})['source'] == MANAGED_SOURCE

    nil
  end

  # Pre-purge the heavy owned children synchronously in batches (the inbox's own dependents are `destroy_async`,
  # which would otherwise fan out into background jobs). Ordered by FK dependency: messages -> conversations ->
  # contact_inboxes -> reporting_events. These are inbox-OWNED rows; shared Contacts are NEVER touched here (only
  # the ContactInbox join rows are removed).
  def purge_heavy_children(inbox)
    [inbox.messages, inbox.conversations, inbox.contact_inboxes, inbox.reporting_events].each do |relation|
      relation.find_in_batches(batch_size: BATCH_SIZE) do |batch|
        batch.each(&:destroy!)
      end
    end
  end

  # Sanitized audit trail: internal ids + actor only. NEVER the phone number, phone_number_id, WABA id, or any token.
  def audit(inbox_id:, channel_id:)
    Rails.logger.info(
      '[BLOOMWIRE WA DEPROVISION] removed managed WhatsApp inbox ' \
      "account=#{@account.id} inbox=#{inbox_id} channel=#{channel_id} actor=#{@actor&.id || 'system'}"
    )
  end
end
