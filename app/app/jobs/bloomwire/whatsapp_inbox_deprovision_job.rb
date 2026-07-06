# Async, retry-safe, idempotent deletion of a managed WhatsApp inbox (Admin "Remove WhatsApp Inbox"). The request
# path (Bloomwire::WhatsappInboxDeprovisionService#prepare) has already blocked routing and enqueued this job; here
# we do the heavy purge off the request. `.purge!` re-verifies state on every run and no-ops when the inbox is
# already gone, so a duplicate enqueue or a Sidekiq retry after a partial failure is safe.
class Bloomwire::WhatsappInboxDeprovisionJob < ApplicationJob
  queue_as :low

  def perform(account_id:, inbox_id:, actor_id: nil)
    Bloomwire::WhatsappInboxDeprovisionService.purge!(
      account_id: account_id, inbox_id: inbox_id, actor_id: actor_id
    )
  end
end
