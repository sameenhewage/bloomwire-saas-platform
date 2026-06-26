class CreateBloomwireWhatsappSetups < ActiveRecord::Migration[7.1]
  def change
    create_table :bloomwire_whatsapp_setups do |t|
      t.references :account, null: false, foreign_key: true
      t.references :inbox, null: true, foreign_key: true
      t.references :channel_whatsapp, null: true,
                                      foreign_key: { to_table: :channel_whatsapp },
                                      index: { unique: true }
      t.string :setup_status, null: false, default: 'pending'
      t.text :status_reason
      # Non-secret routing identifiers (Bloomwire Ops tracking + seed for the future webhook router).
      # No secrets/tokens are stored here — credentials live in Channel::Whatsapp#provider_config.
      t.string :waba_id
      t.string :phone_number_id
      t.string :display_phone_number

      t.timestamps
    end

    add_index :bloomwire_whatsapp_setups, :phone_number_id
    add_index :bloomwire_whatsapp_setups, :setup_status
  end
end
