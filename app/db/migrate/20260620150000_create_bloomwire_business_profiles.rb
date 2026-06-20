class CreateBloomwireBusinessProfiles < ActiveRecord::Migration[7.1]
  def change
    create_table :bloomwire_business_profiles do |t|
      t.references :account, null: false, foreign_key: true, index: { unique: true }
      t.string :industry
      t.string :plan_name
      t.string :status, null: false, default: 'setup_pending'
      t.string :onboarding_status, null: false, default: 'not_started'

      t.timestamps
    end

    add_index :bloomwire_business_profiles, :status
    add_index :bloomwire_business_profiles, :onboarding_status
  end
end
