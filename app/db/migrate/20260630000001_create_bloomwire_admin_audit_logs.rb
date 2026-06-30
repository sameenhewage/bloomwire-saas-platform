# Phase 15G.3 (Auth Go-Live Guardrails): a Bloomwire-owned audit trail for admin mutations of user records
# (e.g. edits via the SuperAdmin Users page). Created because the prior auth-integrity RCA had NO provable
# trail of who/what changed a user. Bloomwire-owned table — NOT a Chatwoot/Enterprise table, NOT a
# conversation/message store.
#
# SECURITY: this table stores **field NAMES only**, never values. `changed_fields` are the columns that were
# updated; `blocked_fields` are auth-sensitive params that were submitted but stripped (password, confirmed_at,
# etc.). It NEVER stores passwords, encrypted_password, reset tokens, secrets, or raw hashes.
class CreateBloomwireAdminAuditLogs < ActiveRecord::Migration[7.1]
  def up
    create_table :bloomwire_admin_audit_logs do |t|
      t.bigint :actor_id            # super_admin/user who performed the action (nullable)
      t.bigint :target_user_id      # user that was mutated (nullable)
      t.string :controller          # e.g. "super_admin/users"
      t.string :action              # e.g. "update"
      t.jsonb :changed_fields, null: false, default: []  # column NAMES changed (never values)
      t.jsonb :blocked_fields, null: false, default: []  # auth-sensitive param NAMES that were stripped

      t.timestamps
    end

    add_index :bloomwire_admin_audit_logs, :target_user_id
    add_index :bloomwire_admin_audit_logs, :actor_id
    add_index :bloomwire_admin_audit_logs, :created_at
  end

  def down
    drop_table :bloomwire_admin_audit_logs
  end
end
