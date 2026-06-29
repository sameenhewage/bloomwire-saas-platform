# Phase 15F: Bloomwire-owned outbound email (SMTP) configuration. DB becomes the source of truth for the
# Bloomwire Platform Owner's email settings (ENV SMTP_* values are used only as bootstrap defaults).
#
# SECURITY DEBT (documented, Phase 15F): smtp_password is stored in PLAINTEXT for now because Active Record
# encryption is not yet configured on this install. It is never shown in the UI, never logged (filtered),
# never printed, and never committed. Encryption-at-rest is a parked Phase 15F security-hardening follow-up.
class CreateBloomwireEmailSettings < ActiveRecord::Migration[7.1]
  def change # rubocop:disable Metrics/MethodLength
    create_table :bloomwire_email_settings do |t|
      t.string :smtp_address
      t.integer :smtp_port, default: 587
      t.string :smtp_domain
      t.string :smtp_username
      t.string :smtp_password # plaintext for now — see security debt note above
      t.string :smtp_authentication, default: 'login'
      t.boolean :smtp_enable_starttls_auto, default: true, null: false
      t.boolean :smtp_tls, default: false, null: false
      t.boolean :smtp_ssl, default: false, null: false
      t.string :from_name
      t.string :from_email
      t.string :reply_to_email
      t.boolean :enabled, default: false, null: false
      t.string :last_test_status, default: 'not_tested'
      t.datetime :last_test_sent_at
      t.string :last_test_error # sanitized message only — never the raw secret
      t.bigint :last_updated_by_id

      t.timestamps
    end

    add_index :bloomwire_email_settings, :last_updated_by_id
  end
end
