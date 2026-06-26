class CreateBloomwireWhatsappSetupRequests < ActiveRecord::Migration[7.1]
  def change
    create_table :bloomwire_whatsapp_setup_requests do |t|
      t.references :account, null: false, foreign_key: true
      # The User who requested managed setup (nullable: "if available"). FK to users.
      t.bigint :requested_by_id
      t.string :status, null: false, default: 'pending'
      t.text :status_reason
      # Optional link to the technical setup mapping once Bloomwire Ops creates one. No secrets are stored here.
      t.bigint :bloomwire_whatsapp_setup_id
      t.datetime :completed_at

      t.timestamps
    end

    add_index :bloomwire_whatsapp_setup_requests, :requested_by_id
    add_index :bloomwire_whatsapp_setup_requests, :bloomwire_whatsapp_setup_id

    # One ACTIVE request per account (active = status NOT IN completed/blocked). Multiple closed rows allowed,
    # so a brand-new request can be made after the previous one is completed or blocked.
    add_index :bloomwire_whatsapp_setup_requests, :account_id,
              unique: true,
              where: "status NOT IN ('completed', 'blocked')",
              name: 'idx_bw_wa_setup_requests_one_active_per_account'

    add_foreign_key :bloomwire_whatsapp_setup_requests, :users, column: :requested_by_id
    add_foreign_key :bloomwire_whatsapp_setup_requests, :bloomwire_whatsapp_setups, column: :bloomwire_whatsapp_setup_id
  end
end
