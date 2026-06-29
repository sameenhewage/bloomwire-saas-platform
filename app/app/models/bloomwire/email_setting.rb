# Phase 15F: Bloomwire-owned outbound email (SMTP) configuration — the source of truth for the Platform
# Owner's email settings. ENV SMTP_* values are used ONLY as bootstrap defaults when no row/value exists.
#
# SECURITY DEBT (Phase 15F, documented): smtp_password is stored in PLAINTEXT because Active Record
# encryption is not yet configured here. The secret is never rendered in the UI, never logged (filtered via
# filter_parameter_logging), never printed, and never committed. Encryption-at-rest is a parked follow-up.
# == Schema Information
#
# Table name: bloomwire_email_settings
#
#  id                        :bigint           not null, primary key
#  enabled                   :boolean          default(FALSE), not null
#  from_email                :string
#  from_name                 :string
#  last_test_error           :string
#  last_test_sent_at         :datetime
#  last_test_status          :string           default("not_tested")
#  reply_to_email            :string
#  smtp_address              :string
#  smtp_authentication       :string           default("login")
#  smtp_domain               :string
#  smtp_enable_starttls_auto :boolean          default(TRUE), not null
#  smtp_password             :string
#  smtp_port                 :integer          default(587)
#  smtp_ssl                  :boolean          default(FALSE), not null
#  smtp_tls                  :boolean          default(FALSE), not null
#  smtp_username             :string
#  created_at                :datetime         not null
#  updated_at                :datetime         not null
#  last_updated_by_id        :bigint
#
# Indexes
#
#  index_bloomwire_email_settings_on_last_updated_by_id  (last_updated_by_id)
#
class Bloomwire::EmailSetting < ApplicationRecord
  self.table_name = 'bloomwire_email_settings'

  belongs_to :last_updated_by, class_name: 'User', optional: true

  AUTH_METHODS = %w[plain login cram_md5].freeze
  LAST_TEST_STATUSES = %w[not_tested success failed blocked_missing_config].freeze

  # Fields that must all be present before a real test send is attempted (preflight).
  REQUIRED_FOR_DELIVERY = %i[smtp_address smtp_port smtp_domain smtp_username smtp_password from_email].freeze

  # The singleton settings row, seeded from ENV bootstrap defaults when absent (NOT persisted until saved).
  def self.current
    first || new(default_attributes)
  end

  # ENV bootstrap defaults. Reading ENV here does not change global ActionMailer config; it only pre-fills
  # the owner's form the first time. The DB row becomes the source of truth once saved.
  def self.default_attributes
    {
      smtp_address: env_default('SMTP_ADDRESS', 'smtp.office365.com'),
      smtp_port: env_default('SMTP_PORT', '587').to_i,
      smtp_domain: env_default('SMTP_DOMAIN', 'bloomwire.lk'),
      smtp_username: env_default('SMTP_USERNAME', 'sameen@bloomwire.lk'),
      smtp_password: env_default('SMTP_PASSWORD', nil),
      smtp_authentication: env_default('SMTP_AUTHENTICATION', 'login'),
      smtp_enable_starttls_auto: env_bool('SMTP_ENABLE_STARTTLS_AUTO', true),
      smtp_tls: env_bool('SMTP_TLS', false),
      smtp_ssl: env_bool('SMTP_SSL', false),
      from_name: env_default('BLOOMWIRE_MAIL_FROM_NAME', 'Bloomwire'),
      from_email: env_default('SMTP_USERNAME', 'sameen@bloomwire.lk'),
      enabled: false,
      last_test_status: 'not_tested'
    }
  end

  # ENV value with a bootstrap fallback when the key is absent OR present-but-empty.
  def self.env_default(key, fallback)
    ENV.fetch(key, '').presence || fallback
  end

  def self.env_bool(key, default)
    raw = ENV.fetch(key, '')
    return default if raw.blank?

    ActiveModel::Type::Boolean.new.cast(raw)
  end

  def password_present?
    smtp_password.present?
  end

  # Required SMTP/from fields that are still blank (drives the honest "cannot send" preflight message).
  def missing_required_fields
    REQUIRED_FOR_DELIVERY.reject { |f| public_send(f).present? }
  end

  def deliverable?
    missing_required_fields.empty?
  end

  def effective_from_email
    from_email.presence || smtp_username
  end

  def effective_from_name
    from_name.presence || 'Bloomwire'
  end

  # Per-delivery SMTP settings used by the test mailer so we use THIS DB config (not the global ENV
  # initializer). Never logged. `.compact` drops blanks so ActionMailer applies its own defaults.
  def smtp_delivery_settings
    {
      address: smtp_address,
      port: smtp_port,
      domain: smtp_domain.presence,
      user_name: smtp_username.presence,
      password: smtp_password.presence,
      authentication: smtp_authentication.presence&.to_sym,
      enable_starttls_auto: smtp_enable_starttls_auto,
      ssl: smtp_ssl,
      tls: smtp_tls
    }.compact
  end

  # Records the outcome of a test send. The error message is truncated/sanitized and must never contain the
  # secret (callers pass an already-sanitized message).
  def record_test_result!(status:, error: nil, actor: nil)
    update!(
      last_test_status: status,
      last_test_sent_at: (status == 'success' ? Time.current : last_test_sent_at),
      last_test_error: error.to_s.presence&.truncate(240),
      last_updated_by: actor || last_updated_by
    )
  end
end
