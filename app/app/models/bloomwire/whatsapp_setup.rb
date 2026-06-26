# Bloomwire-Ops-owned WhatsApp setup readiness tracker (Bloomwire WhatsApp Setup Mapping foundation).
# It REFERENCES existing Chatwoot records (account / inbox / Channel::Whatsapp) and stores only non-secret
# routing identifiers + a setup status. Secrets (api_key, webhook_verify_token) are NEVER stored here —
# they remain solely in Channel::Whatsapp#provider_config (protected by Bloomwire Phase 2A/2B/2C). This
# row also seeds the future Global Meta WhatsApp Webhook Router (lookup by phone_number_id / waba_id).
class Bloomwire::WhatsappSetup < ApplicationRecord
  self.table_name = 'bloomwire_whatsapp_setups'

  SETUP_STATUSES = %w[pending configured ready_for_webhook blocked].freeze

  belongs_to :account
  belongs_to :inbox, optional: true
  belongs_to :channel_whatsapp, class_name: 'Channel::Whatsapp', optional: true

  validates :setup_status, presence: true, inclusion: { in: SETUP_STATUSES }
  validates :channel_whatsapp_id, uniqueness: true, allow_nil: true

  scope :ready_for_webhook, -> { where(setup_status: 'ready_for_webhook') }
end
