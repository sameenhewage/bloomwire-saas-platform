class CreateBloomwirePlatformAdmins < ActiveRecord::Migration[7.1]
  def change
    create_table :bloomwire_platform_admins do |t|
      # The approved SuperAdmin user. One approval row per user (unique). No secrets are stored here.
      t.bigint :user_id, null: false
      # Metadata only in Phase 15A (does not vary access): owner/admin/support.
      t.integer :role, null: false, default: 1
      t.boolean :enabled, null: false, default: true
      # Who approved + audit trail. Active approval == enabled AND revoked_at IS NULL.
      t.bigint :approved_by_id
      t.datetime :approved_at
      t.datetime :revoked_at
      t.text :reason

      t.timestamps
    end

    add_index :bloomwire_platform_admins, :user_id, unique: true
    add_index :bloomwire_platform_admins, :approved_by_id

    add_foreign_key :bloomwire_platform_admins, :users, column: :user_id, on_delete: :cascade
    add_foreign_key :bloomwire_platform_admins, :users, column: :approved_by_id, on_delete: :nullify
  end
end
