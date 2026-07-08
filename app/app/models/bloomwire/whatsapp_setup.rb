# Bloomwire-Ops-owned WhatsApp setup readiness tracker (Bloomwire WhatsApp Setup Mapping foundation).
# It REFERENCES existing Chatwoot records (account / inbox / Channel::Whatsapp) and stores only non-secret
# routing identifiers + a setup status. Secrets (api_key, webhook_verify_token) are NEVER stored here —
# they remain solely in Channel::Whatsapp#provider_config (protected by Bloomwire Phase 2A/2B/2C). This
# row also seeds the future Global Meta WhatsApp Webhook Router (lookup by phone_number_id / waba_id), which
# will TRUST this mapping — so cross-account/cross-channel mismatches and non-routeable "ready" rows are
# rejected at the model layer (and phone_number_id uniqueness is also enforced by a partial DB index).
class Bloomwire::WhatsappSetup < ApplicationRecord
  self.table_name = 'bloomwire_whatsapp_setups'

  SETUP_STATUSES = %w[pending configured ready_for_webhook action_required blocked].freeze
  ROUTEABLE_STATUS = 'ready_for_webhook'.freeze
  # Onboarding completed the CONNECTED number + records, but the stored-token actor lacks the WABA asset task
  # required to SEND (Meta #10). The inbox is intentionally NOT routeable-ready — an explicit Action-Required
  # state (never a silently receive-only inbox) preserved for resumption once the task is granted.
  ACTION_REQUIRED_STATUS = 'action_required'.freeze

  belongs_to :account
  belongs_to :inbox, optional: true
  belongs_to :channel_whatsapp, class_name: 'Channel::Whatsapp', optional: true

  # Normalize blank routing identifiers to nil BEFORE validation so a form-submitted empty string does not
  # collide with the partial unique index (which treats '' as a real value, unlike NULL).
  before_validation :normalize_blank_routing_identifiers

  validates :setup_status, presence: true, inclusion: { in: SETUP_STATUSES }
  validates :channel_whatsapp_id, uniqueness: true, allow_nil: true
  validates :phone_number_id, uniqueness: true, allow_blank: true

  validate :inbox_belongs_to_account
  validate :channel_belongs_to_account
  validate :inbox_matches_channel
  validate :routeable_when_ready_for_webhook

  scope :ready_for_webhook, -> { where(setup_status: ROUTEABLE_STATUS) }

  private

  # Coerce blank ('' / whitespace) routing identifiers to nil so NULL semantics apply at the DB (the
  # partial unique index is `where phone_number_id IS NOT NULL`, so multiple pending/blank rows are allowed).
  def normalize_blank_routing_identifiers
    self.phone_number_id = phone_number_id.presence
    self.waba_id = waba_id.presence
    self.display_phone_number = display_phone_number.presence
  end

  # The referenced inbox must belong to the same account as the setup (prevents cross-tenant routing).
  def inbox_belongs_to_account
    return if inbox_id.blank? || account_id.blank? || inbox&.account_id == account_id

    errors.add(:inbox_id, 'must belong to the same account as the setup')
  end

  # The referenced WhatsApp channel must belong to the same account as the setup.
  def channel_belongs_to_account
    return if channel_whatsapp_id.blank? || account_id.blank? || channel_whatsapp&.account_id == account_id

    errors.add(:channel_whatsapp_id, 'must belong to the same account as the setup')
  end

  # When both are present, the inbox must be the WhatsApp channel's own inbox (no mixed account/inbox/channel).
  def inbox_matches_channel
    return if inbox_id.blank? || channel_whatsapp_id.blank?
    return if inbox && inbox.channel_type == 'Channel::Whatsapp' && inbox.channel_id == channel_whatsapp_id

    errors.add(:inbox_id, 'must belong to the selected WhatsApp channel')
  end

  # A row is only routeable (ready_for_webhook) when the webhook router can resolve it end to end:
  # it needs the phone_number_id, the inbox, and the channel (consistency is enforced by the rules above).
  def routeable_when_ready_for_webhook
    return unless setup_status == ROUTEABLE_STATUS

    errors.add(:phone_number_id, 'is required when ready for webhook') if phone_number_id.blank?
    errors.add(:inbox_id, 'is required when ready for webhook') if inbox_id.blank?
    errors.add(:channel_whatsapp_id, 'is required when ready for webhook') if channel_whatsapp_id.blank?
  end
end
