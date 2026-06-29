# Phase 15F.1: one row per owner-initiated "Send from Template" attempt (success / failed / blocked).
# Bloomwire-owned audit log — NOT a Chatwoot/Enterprise table and NOT a conversation/message store.
#
# SECURITY: never stores SMTP credentials. `error_message` must be pre-sanitized by the caller
# (Bloomwire::EmailSetting#sanitize_secret) so the SMTP password can never land here.
# == Schema Information
#
# Table name: bloomwire_email_delivery_logs
#
#  id                :bigint           not null, primary key
#  error_message     :text
#  recipient_email   :string
#  sent_at           :datetime
#  status            :string           not null
#  subject           :string
#  template_key      :string
#  template_name     :string
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#  actor_id          :bigint
#  email_template_id :bigint
#
# Indexes
#
#  index_bloomwire_email_delivery_logs_on_created_at         (created_at)
#  index_bloomwire_email_delivery_logs_on_email_template_id  (email_template_id)
#  index_bloomwire_email_delivery_logs_on_status             (status)
#
class Bloomwire::EmailDeliveryLog < ApplicationRecord
  self.table_name = 'bloomwire_email_delivery_logs'

  STATUSES = %w[success failed blocked].freeze

  belongs_to :email_template, class_name: 'Bloomwire::EmailTemplate', optional: true
  belongs_to :actor, class_name: 'User', optional: true

  validates :status, presence: true, inclusion: { in: STATUSES }

  scope :recent, -> { order(created_at: :desc) }

  def success?
    status == 'success'
  end

  def failed?
    status == 'failed'
  end

  def blocked?
    status == 'blocked'
  end
end
