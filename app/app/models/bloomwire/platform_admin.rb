# Phase 15A — Bloomwire platform-admin approval (ADR-0007). Source of truth for "who may use the /super_admin
# console when Bloomwire Mode is ON". Identity (users.type = 'SuperAdmin', Rails STI) is necessary but NOT
# sufficient: a SuperAdmin must ALSO have an active approval row here (or be a bootstrap-allowlisted email).
# No secrets are stored here. Mode OFF => this gate is inert (stock Chatwoot; only SuperAdmin is required).
#
# Phase 15A.1 adds the ownership model + management primitives: role `owner` may manage platform admins
# (owner-only UI), the last active owner is protected from revoke/demote, and revocation is a SOFT revoke
# (kept for audit + re-grant). Business roles never live in users.type (see ADR-0007).
class Bloomwire::PlatformAdmin < ApplicationRecord
  # Raised when an operation would remove the last active platform owner (revoke or demote).
  class LastOwnerError < StandardError; end

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
  scope :active_owners, -> { active.owner }

  def active?
    enabled? && revoked_at.nil?
  end

  # True when this row is currently the ONLY active owner — protected from revoke/demote so the platform can
  # never be left with zero owners (covers both "revoke last owner" and "self-revoke leaving zero owners").
  def last_active_owner?
    return false unless owner? && active?

    self.class.active_owners.where.not(id: id).none?
  end

  # True when changing this row to `new_role` would demote the last active owner (owner -> non-owner). Used by
  # the grant/reactivate primitives so the invariant holds even when called directly (console/services/tests).
  def demotes_last_active_owner?(new_role)
    new_role.to_s != 'owner' && last_active_owner?
  end

  # Phase 15A.2: a row actually grants /super_admin access only if its user is a SuperAdmin (the 15A boundary).
  # A row whose user is missing or no longer a SuperAdmin (e.g., users.type edited away) is INCONSISTENT — the
  # owner UI surfaces it as "Needs repair" rather than hiding it.
  def identity_consistent?
    user.present? && user.type == 'SuperAdmin'
  end

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

  # Phase 15A.2: read-only platform-access status for a user, for the SuperAdmin Users table. Reflects the REAL
  # platform role (this table), NOT the users.type STI discriminator. Returns a symbol:
  # :owner / :admin / :support (active row) · :revoked (inactive row) · :not_approved (SuperAdmin, no row) ·
  # :no_access (normal/business user).
  def self.access_status_for(user)
    return :no_access if user.blank?

    row = find_by(user_id: user.id)
    return (user.type == 'SuperAdmin' ? :not_approved : :no_access) if row.nil?

    row.active? ? row.role.to_sym : :revoked
  end

  # --- Grant / revoke primitives. The owner-only UI authorization (who may call these) lives in the
  # controller/service; these enforce the data invariant (never zero active owners). ---

  # Create or reactivate an active approval row with the given role. Used by the owner setup service, the
  # invite/grant service, and seeds. Idempotent per user (one row per user). Enforces the last-owner invariant
  # at the primitive level: changing the only active owner to a non-owner role raises LastOwnerError.
  def self.grant!(user:, approved_by: nil, role: :admin, reason: nil)
    record = find_or_initialize_by(user_id: user.id)
    raise LastOwnerError, I18n.t('bloomwire.platform_admin.last_owner_protected') if record.demotes_last_active_owner?(role)

    record.assign_attributes(
      role: role, enabled: true, revoked_at: nil, reason: reason.presence || record.reason,
      approved_by_id: approved_by&.id, approved_at: Time.current
    )
    record.save!
    record
  end

  def self.revoke!(user:, reason: nil)
    record = find_by(user_id: user.id)
    return nil if record.nil?

    record.soft_revoke!(reason: reason)
  end

  # Soft revoke: keep the row (audit trail), flip it inactive. Refuses to remove the last active owner.
  def soft_revoke!(reason: nil)
    raise LastOwnerError, I18n.t('bloomwire.platform_admin.last_owner_protected') if last_active_owner?

    update!(enabled: false, revoked_at: Time.current, reason: reason.presence || self.reason)
    self
  end

  # Reactivate a previously revoked row (records the new role + reason). Re-grant path for the owner UI.
  # Also enforces the last-owner invariant: cannot demote the only active owner via reactivation.
  def reactivate!(role: nil, approved_by: nil, reason: nil)
    new_role = role.presence || self.role
    raise LastOwnerError, I18n.t('bloomwire.platform_admin.last_owner_protected') if demotes_last_active_owner?(new_role)

    update!(
      role: new_role, enabled: true, revoked_at: nil,
      approved_by_id: approved_by&.id, approved_at: Time.current, reason: reason.presence || self.reason
    )
    self
  end
end
