class CreateBloomwireOnboardingSteps < ActiveRecord::Migration[7.1]
  def change
    create_table :bloomwire_onboarding_steps do |t|
      t.references :bloomwire_business_profile, null: false, foreign_key: true
      t.string :step_key, null: false
      t.string :status, null: false, default: 'pending'
      t.integer :position, null: false, default: 0

      t.timestamps
    end

    add_index :bloomwire_onboarding_steps,
              %i[bloomwire_business_profile_id step_key],
              unique: true,
              name: 'index_bloomwire_onboarding_steps_on_profile_and_key'
  end
end
