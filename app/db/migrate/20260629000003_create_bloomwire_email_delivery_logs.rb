# Phase 15F.1: per-send delivery log for owner-initiated "Send from Template" emails. Bloomwire-owned table
# (NOT a Chatwoot/Enterprise table and NOT a conversation/message store). Records one row per send attempt —
# success / failed / blocked — so the Email Logs tab shows real history instead of a single overwritten result.
# SECURITY: this table NEVER stores SMTP credentials; `error_message` is sanitized before insert (password
# filtered + truncated by the caller). Template text/subjects are not secrets.
class CreateBloomwireEmailDeliveryLogs < ActiveRecord::Migration[7.1]
  def up
    create_table :bloomwire_email_delivery_logs do |t|
      t.bigint :email_template_id          # nullable: the template may be deleted later; we keep the log
      t.string :template_key
      t.string :template_name
      t.string :recipient_email            # nullable: a "missing recipient" blocked attempt has none
      t.string :subject
      t.string :status, null: false        # success / failed / blocked
      t.text :error_message                # sanitized only (never the SMTP password)
      t.bigint :actor_id                    # super_admin who triggered the send (nullable)
      t.datetime :sent_at

      t.timestamps
    end

    add_index :bloomwire_email_delivery_logs, :email_template_id
    add_index :bloomwire_email_delivery_logs, :status
    add_index :bloomwire_email_delivery_logs, :created_at
  end

  def down
    drop_table :bloomwire_email_delivery_logs
  end
end
