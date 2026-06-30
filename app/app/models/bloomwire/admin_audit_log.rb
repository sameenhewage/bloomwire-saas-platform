# Phase 15G.3 (Auth Go-Live Guardrails): one row per admin mutation of a user record (e.g. SuperAdmin Users
# edit). Bloomwire-owned audit trail — NOT a Chatwoot/Enterprise table, NOT a conversation/message store.
#
# SECURITY: stores **field NAMES only**, never values. `changed_fields` = columns that changed;
# `blocked_fields` = auth-sensitive params that were submitted but stripped by the controller. NEVER stores
# passwords, encrypted_password, reset tokens, secrets, or raw hashes.
# == Schema Information
#
# Table name: bloomwire_admin_audit_logs
#
#  id             :bigint           not null, primary key
#  action         :string
#  blocked_fields :jsonb            not null
#  changed_fields :jsonb            not null
#  controller     :string
#  created_at     :datetime         not null
#  updated_at     :datetime         not null
#  actor_id       :bigint
#  target_user_id :bigint
#
# Indexes
#
#  index_bloomwire_admin_audit_logs_on_actor_id        (actor_id)
#  index_bloomwire_admin_audit_logs_on_created_at      (created_at)
#  index_bloomwire_admin_audit_logs_on_target_user_id  (target_user_id)
#
class Bloomwire::AdminAuditLog < ApplicationRecord
  self.table_name = 'bloomwire_admin_audit_logs'

  belongs_to :actor, class_name: 'User', optional: true
  belongs_to :target_user, class_name: 'User', optional: true

  scope :recent, -> { order(created_at: :desc) }
end
