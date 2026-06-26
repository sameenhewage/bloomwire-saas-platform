# Phase 11A: Bloomwire-managed WhatsApp setup REQUEST (Ops intake). When native WhatsApp setup is restricted
# (PR #40), a business/account admin requests managed setup; Bloomwire Ops then works the request through this
# lifecycle and, later, creates/links the technical Bloomwire::WhatsappSetup mapping + readiness.
#
# This record is intentionally SEPARATE from Bloomwire::WhatsappSetup: that model's setup_status is the
# router/readiness technical-readiness axis, whereas this tracks the Ops intake workflow. It stores ONLY
# non-secret intake fields (status, optional reason, requester, optional mapping link) — never any credentials.
# One ACTIVE request per account (active = not completed/blocked) is enforced by a partial unique index.
# == Schema Information
#
# Table name: bloomwire_whatsapp_setup_requests
#
#  id                          :bigint           not null, primary key
#  completed_at                :datetime
#  status                      :string           default("pending"), not null
#  status_reason               :text
#  created_at                  :datetime         not null
#  updated_at                  :datetime         not null
#  account_id                  :bigint           not null
#  bloomwire_whatsapp_setup_id :bigint
#  requested_by_id             :bigint
#
# Indexes
#
#  idx_bw_wa_setup_requests_one_active_per_account             (account_id) UNIQUE WHERE (active statuses only)
#  idx_on_bloomwire_whatsapp_setup_id_d6e0b0d31d               (bloomwire_whatsapp_setup_id)
#  index_bloomwire_whatsapp_setup_requests_on_account_id       (account_id)
#  index_bloomwire_whatsapp_setup_requests_on_requested_by_id  (requested_by_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (bloomwire_whatsapp_setup_id => bloomwire_whatsapp_setups.id)
#  fk_rails_...  (requested_by_id => users.id)
#
class Bloomwire::WhatsappSetupRequest < ApplicationRecord
  self.table_name = 'bloomwire_whatsapp_setup_requests'

  STATUSES = %w[pending in_progress waiting_for_client ready_for_setup blocked completed].freeze
  CLOSED_STATUSES = %w[completed blocked].freeze
  ACTIVE_STATUSES = (STATUSES - CLOSED_STATUSES).freeze

  belongs_to :account
  belongs_to :requested_by, class_name: 'User', optional: true
  belongs_to :bloomwire_whatsapp_setup, class_name: 'Bloomwire::WhatsappSetup', optional: true

  validates :status, presence: true, inclusion: { in: STATUSES }
  validate :bloomwire_whatsapp_setup_belongs_to_account
  validate :single_active_request_per_account

  before_save :stamp_completed_at

  scope :active, -> { where(status: ACTIVE_STATUSES) }

  # Idempotent intake: return the account's existing ACTIVE request, or create a new pending one. The model
  # validation and the partial unique index both close the create race (app-layer RecordInvalid or DB-layer
  # RecordNotUnique); on a concurrent active insert we re-find the existing active request.
  def self.request_for(account:, requested_by: nil)
    existing = active.find_by(account_id: account.id)
    return existing if existing

    create!(account: account, requested_by: requested_by, status: 'pending')
  rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
    active.find_by!(account_id: account.id)
  end

  def active?
    ACTIVE_STATUSES.include?(status)
  end

  private

  # The optionally-linked setup mapping must belong to the SAME account as the request — Ops must not link one
  # tenant's request to another tenant's WhatsApp setup mapping/readiness (cross-account data-integrity).
  def bloomwire_whatsapp_setup_belongs_to_account
    return if bloomwire_whatsapp_setup_id.blank?
    return if bloomwire_whatsapp_setup&.account_id == account_id

    errors.add(:bloomwire_whatsapp_setup_id, 'must belong to the same account as the request')
  end

  # Only one ACTIVE request may exist per account. This fails closed at the app layer (so reopening an old
  # closed request returns a 422 validation error instead of a DB RecordNotUnique 500); the partial unique
  # index remains the DB-level safety backstop for the create race.
  def single_active_request_per_account
    return if account_id.blank?
    return unless ACTIVE_STATUSES.include?(status)

    conflicting = self.class.active.where(account_id: account_id)
    conflicting = conflicting.where.not(id: id) if persisted?
    return unless conflicting.exists?

    errors.add(:status, 'cannot be set to active: another active setup request already exists for this account')
  end

  def stamp_completed_at
    return unless new_record? || will_save_change_to_status?

    self.completed_at = status == 'completed' ? (completed_at || Time.current) : nil
  end
end
