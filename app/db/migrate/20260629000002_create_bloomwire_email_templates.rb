# Phase 15F: Bloomwire-owned reusable email templates (owner-managed from the Email Settings page).
# Template text is NOT a secret, so DB persistence is straightforward. Seeded with 6 system defaults
# (see Bloomwire::EmailTemplate.seed_defaults!). Bloomwire-owned table — not a Chatwoot/Enterprise table,
# and NOT a conversation/message store (no chat data duplication).
class CreateBloomwireEmailTemplates < ActiveRecord::Migration[7.1]
  def up
    create_table :bloomwire_email_templates do |t|
      t.string :key, null: false
      t.string :name, null: false
      t.string :category
      t.string :subject
      t.text :body
      t.string :cta_label # optional call-to-action button label (rendered in preview when present)
      t.string :cta_url   # optional CTA target (may itself contain a {{variable}})
      t.boolean :active, default: true, null: false
      t.boolean :system, default: false, null: false
      t.integer :position, default: 0, null: false
      t.bigint :last_updated_by_id

      t.timestamps
    end

    add_index :bloomwire_email_templates, :key, unique: true
    add_index :bloomwire_email_templates, :last_updated_by_id

    # Seed the 6 system default templates so the Email Settings page is usable immediately after deploy.
    # Idempotent (only inserts missing keys); safe to re-run.
    Bloomwire::EmailTemplate.reset_column_information
    Bloomwire::EmailTemplate.seed_defaults!
  end

  def down
    drop_table :bloomwire_email_templates
  end
end
