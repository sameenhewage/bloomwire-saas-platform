class CreateBloomwireChannelIntegrations < ActiveRecord::Migration[7.1]
  def change # rubocop:disable Metrics/MethodLength
    create_table :bloomwire_channel_integrations do |t|
      t.references :bloomwire_business_profile, null: false, foreign_key: true,
                                                index: { name: 'index_bw_channel_integrations_on_profile_id' }
      t.references :account, null: false, foreign_key: true
      t.references :inbox, null: false, foreign_key: true, index: { unique: true }
      t.references :channelable, polymorphic: true, null: false
      t.string :app_kind, null: false
      t.string :provider, null: false
      t.string :status, null: false, default: 'pending'
      t.boolean :managed_by_bloomwire, null: false, default: true
      t.string :routing_key
      t.string :phone_number
      t.string :phone_number_id
      t.string :business_account_id
      t.references :created_by_super_admin, foreign_key: { to_table: :users },
                                            index: { name: 'index_bw_channel_integrations_on_created_by_sa_id' }

      t.timestamps
    end

    add_index :bloomwire_channel_integrations, :status
    add_index :bloomwire_channel_integrations, %i[app_kind provider]
    add_index :bloomwire_channel_integrations, :routing_key,
              unique: true,
              where: 'routing_key IS NOT NULL',
              name: 'index_bw_channel_integrations_on_routing_key'
    add_index :bloomwire_channel_integrations, :phone_number_id,
              where: 'phone_number_id IS NOT NULL',
              name: 'index_bw_channel_integrations_on_phone_number_id'
    add_index :bloomwire_channel_integrations, :business_account_id,
              where: 'business_account_id IS NOT NULL',
              name: 'index_bw_channel_integrations_on_business_account_id'
  end
end
