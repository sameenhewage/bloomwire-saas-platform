# Phase 15A — Bloomwire platform-admin approval (ADR-0007). Source of truth for "who may use the /super_admin
# console when Bloomwire Mode is ON". Identity (users.type = 'SuperAdmin', Rails STI) is necessary but NOT
# sufficient: a SuperAdmin must ALSO have an active approval row here (or be a bootstrap-allowlisted email).
# No secrets are stored here. Mode OFF => this gate is inert (stock Chatwoot; only SuperAdmin is required).
class Bloomwire::PlatformAdmin < ApplicationRecord
  self.table_name = 'bloomwire_platform_admins'

  # ENV-only bootstrap escape hatch (prevents self-lockout). Intentionally NOT readable from the in-app
  # SuperAdmin config UI — otherwise the gate could be bypassed from inside the console it protects.
  BOOTSTRAP_ENV_KEY = 'BLOOMWIRE_BOOTSTRAP_PLATFORM_ADMIN_EMAILS'.freeze

  belongs_to :user
  belongs_to :approved_by, class_name: 'User', optional: true

  enum role: { owner: 0, admin: 1, support: 2 }

  validates :user_id, uniqueness: true

  # Active approval == enabled AND not revoked.
  scope :active, -> { where(enabled: true, revoked_at: nil) }

  # --- Approval predicate (the single seam every guard/route reads) ---

  # True when this user is an approved Bloomwire platform admin: an active approval row OR a bootstrap email.
  # Callers (controller guard + route lambda) already require a SuperAdmin session, so SuperAdmin-ness is not
  # re-checked here.
  def self.approved?(user)
    return false if user.blank?

    active.exists?(user_id: user.id) || bootstrap_email?(user.email)
  end

  def self.bootstrap_emails
    ENV.fetch(BOOTSTRAP_ENV_KEY, '').to_s.split(',').map { |email| email.strip.downcase }.reject(&:blank?)
  end

  def self.bootstrap_email?(email)
    return false if email.blank?

    bootstrap_emails.include?(email.to_s.strip.downcase)
  end

  # --- Internal-only grant / revoke (console / seed; no public UI in Phase 15A) ---

  def self.grant!(user:, approved_by: nil, role: :admin, reason: nil)
    record = find_or_initialize_by(user_id: user.id)
    record.assign_attributes(
      role: role, enabled: true, revoked_at: nil, reason: reason,
      approved_by_id: approved_by&.id, approved_at: Time.current
    )
    record.save!
    record
  end

  def self.revoke!(user:, reason: nil)
    record = find_by(user_id: user.id)
    return nil if record.nil?

    record.update!(enabled: false, revoked_at: Time.current, reason: reason.presence || record.reason)
    record
  end
end
