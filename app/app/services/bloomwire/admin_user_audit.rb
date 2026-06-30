# Phase 15G.3 (Auth Go-Live Guardrails): records an admin user-mutation audit entry.
#
# SECURITY CONTRACT (do not weaken): this service is given, and persists, **field NAMES only** — never values.
# Callers pass `changed_fields` (column names that changed) and `blocked_fields` (auth-sensitive param names
# that were submitted but stripped). It NEVER receives or stores passwords, encrypted_password, reset tokens,
# secrets, or raw hashes. Auditing must never break the user-facing request, so all errors are rescued.
class Bloomwire::AdminUserAudit
  # Defensive denylist: even if one of these column NAMES is passed as "changed", we re-classify it as a
  # blocked auth-sensitive field name (it must never be presented as a normal allowed change). Values are never
  # handled here regardless.
  AUTH_SENSITIVE_NAMES = %w[
    password password_confirmation encrypted_password reset_password_token reset_password_sent_at
  ].freeze
  IGNORED_NAMES = %w[updated_at created_at].freeze

  def self.record_update!(actor:, target:, changed_fields:, blocked_fields:, controller:, action: 'update') # rubocop:disable Metrics/ParameterLists
    changed = normalize(changed_fields)
    blocked = normalize(blocked_fields)
    # Re-classify any auth-sensitive NAME that slipped into "changed" as blocked (defense-in-depth).
    leaked = changed & AUTH_SENSITIVE_NAMES
    changed -= leaked
    blocked = (blocked + leaked).uniq

    Bloomwire::AdminAuditLog.create!(
      actor_id: actor&.id,
      target_user_id: target&.id,
      controller: controller,
      action: action,
      changed_fields: changed,
      blocked_fields: blocked
    )
  rescue StandardError => e
    # Never let an audit failure break the admin action.
    Rails.logger.warn("[bloomwire.audit] admin user audit not recorded: #{e.class}")
    nil
  end

  def self.normalize(names)
    Array(names).map(&:to_s).reject(&:blank?).uniq - IGNORED_NAMES
  end
end
