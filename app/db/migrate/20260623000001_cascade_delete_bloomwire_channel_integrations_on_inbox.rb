class CascadeDeleteBloomwireChannelIntegrationsOnInbox < ActiveRecord::Migration[7.1]
  # 4.4-b-WA.2A is behavior-neutral and must not block the existing inbox-delete
  # workflow before the 2C deny slice. The ownership row is metadata owned by the
  # inbox/channel mapping, so deleting an inbox should cascade-delete its
  # integration instead of raising a foreign-key error in DeleteObjectJob.
  def up
    remove_foreign_key :bloomwire_channel_integrations, :inboxes
    add_foreign_key :bloomwire_channel_integrations, :inboxes, on_delete: :cascade
  end

  def down
    remove_foreign_key :bloomwire_channel_integrations, :inboxes
    add_foreign_key :bloomwire_channel_integrations, :inboxes
  end
end
