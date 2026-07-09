# Resumable async WhatsApp onboarding attempt (ADR-0010 v3).
#
# Holds ONLY non-secret onboarding state plus TWO temporary, encrypted operational secrets whose lifecycle is
# strictly bounded:
#   - oauth_code  : the short-lived Meta authorization code; stored on submit, CLEARED immediately after a
#                   successful exchange (or terminal expiry/cancel/failure).
#   - access_token: the operational token from the exchange; RETAINED across transient worker retries so a crash
#                   after exchange but before Channel persistence is resumable, then CLEARED once persisted to the
#                   Channel provider_config and verified.
# Both are ActiveRecord-encrypted at rest (ADR-0006) and filtered from #inspect. The full phone number is NEVER
# stored — only a pre-masked value (Guardrail 5). Guardrail 1: action_required counts as ACTIVE (one active
# attempt per account+phone). Guardrail 2: a short DB lease (with_lock) claims ownership without holding a lock
# across Meta HTTP calls; lock_version rejects stale writers.
# == Schema Information
#
# Table name: bloomwire_whatsapp_onboarding_attempts
#
#  id                      :bigint           not null, primary key
#  access_token            :text
#  code_exchanged_at       :datetime
#  code_expires_at         :datetime
#  code_received_at        :datetime
#  credential_persisted_at :datetime
#  job_enqueued_at         :datetime
#  lease_expires_at        :datetime
#  lock_version            :integer          default(0), not null
#  oauth_code              :text
#  phone_number_masked     :string
#  processing_owner        :string
#  processing_started_at   :datetime
#  public_uuid             :string           not null
#  retry_count             :integer          default(0), not null
#  safe_error_code         :string
#  secrets_cleared_at      :datetime
#  status                  :string           default("waiting_meta"), not null
#  step                    :string
#  submission_generation   :integer          default(0), not null
#  created_at              :datetime         not null
#  updated_at              :datetime         not null
#  account_id              :bigint           not null
#  business_id             :string
#  channel_whatsapp_id     :bigint
#  inbox_id                :bigint
#  phone_number_id         :string
#  waba_id                 :string
#
# Indexes
#
#  idx_bw_wa_onboarding_active_account_phone                    (account_id,phone_number_id) UNIQUE WHERE ((phone_number_id IS NOT NULL) AND ((status)::text = ANY ((ARRAY['waiting_meta'::character varying, 'queued'::character varying, 'exchanging_code'::character varying, 'processing'::character varying, 'action_required'::character varying])::text[])))
#  idx_on_account_id_status_5cbf651981                          (account_id,status)
#  idx_on_channel_whatsapp_id_385ab6258a                        (channel_whatsapp_id)
#  idx_on_status_updated_at_263de0c310                          (status,updated_at)
#  index_bloomwire_whatsapp_onboarding_attempts_on_account_id   (account_id)
#  index_bloomwire_whatsapp_onboarding_attempts_on_inbox_id     (inbox_id)
#  index_bloomwire_whatsapp_onboarding_attempts_on_public_uuid  (public_uuid) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (channel_whatsapp_id => channel_whatsapp.id)
#  fk_rails_...  (inbox_id => inboxes.id)
#
class Bloomwire::WhatsappOnboardingAttempt < ApplicationRecord
  self.table_name = 'bloomwire_whatsapp_onboarding_attempts'

  # TODO: remove the guard once encryption keys are mandatory (mirrors the other channel secret columns).
  if Chatwoot.encryption_configured?
    encrypts :oauth_code
    encrypts :access_token
  end
  # Defence in depth: never surface either secret in log/console inspection even when decrypted in memory.
  self.filter_attributes += %i[oauth_code access_token]

  belongs_to :account
  belongs_to :channel_whatsapp, class_name: 'Channel::Whatsapp', optional: true
  belongs_to :inbox, optional: true

  WAITING_META = 'waiting_meta'.freeze
  QUEUED = 'queued'.freeze
  EXCHANGING_CODE = 'exchanging_code'.freeze
  PROCESSING = 'processing'.freeze
  COMPLETED = 'completed'.freeze
  ACTION_REQUIRED = 'action_required'.freeze
  EXPIRED = 'expired'.freeze
  FAILED = 'failed'.freeze
  CANCELLED = 'cancelled'.freeze

  STATUSES = [WAITING_META, QUEUED, EXCHANGING_CODE, PROCESSING, COMPLETED, ACTION_REQUIRED, EXPIRED, FAILED, CANCELLED].freeze
  # Guardrail 1: action_required is ACTIVE (a persisted-but-incomplete setup must be resumed, not re-onboarded).
  ACTIVE_STATUSES = [WAITING_META, QUEUED, EXCHANGING_CODE, PROCESSING, ACTION_REQUIRED].freeze
  TERMINAL_STATUSES = [COMPLETED, EXPIRED, FAILED, CANCELLED].freeze
  # Statuses from which the recovery worker may re-drive a job (a queued/in-flight attempt with no live worker).
  REDRIVABLE_STATUSES = [QUEUED, EXCHANGING_CODE, PROCESSING].freeze

  DEFAULT_LEASE_SECONDS = 120

  before_validation :assign_public_uuid, on: :create
  validates :public_uuid, presence: true, uniqueness: true
  validates :status, inclusion: { in: STATUSES }

  scope :active, -> { where(status: ACTIVE_STATUSES) }
  scope :for_account, ->(account) { where(account_id: account.id) }

  def active?
    ACTIVE_STATUSES.include?(status)
  end

  def terminal?
    TERMINAL_STATUSES.include?(status)
  end

  # --- Target binding (Guardrail 5: store only a masked number) --------------------------------------------
  def bind_target!(waba_id:, phone_number_id:, business_id: nil, phone_number: nil)
    self.waba_id = waba_id if waba_id.present?
    self.phone_number_id = phone_number_id if phone_number_id.present?
    self.business_id = business_id if business_id.present?
    self.phone_number_masked = self.class.mask_phone(phone_number) if phone_number.present?
    save!
  end

  def self.mask_phone(number)
    digits = number.to_s.gsub(/\D/, '')
    return if digits.blank?

    "****#{digits.last(4)}"
  end

  def masked_phone
    phone_number_masked
  end

  # --- Temporary secret lifecycle -------------------------------------------------------------------------
  def store_code!(code)
    update!(oauth_code: code, code_received_at: Time.current)
  end

  def clear_code!
    update!(oauth_code: nil)
  end

  # After a successful exchange: persist the operational token (retained for retries) and IMMEDIATELY drop the code.
  def store_access_token!(token)
    update!(access_token: token, oauth_code: nil, code_exchanged_at: Time.current)
  end

  # After the token is written to the Channel provider_config AND verified: drop the attempt-level token.
  def mark_credential_persisted!
    update!(access_token: nil, credential_persisted_at: Time.current, secrets_cleared_at: Time.current)
  end

  # Terminal cleanup — clear BOTH secrets (expiry / cancel / final failure).
  def clear_secrets!
    update!(oauth_code: nil, access_token: nil, secrets_cleared_at: Time.current)
  end

  def secrets_present?
    oauth_code.present? || access_token.present?
  end

  # --- Submission generation (stale-job guard) ------------------------------------------------------------
  def bump_generation!
    update!(submission_generation: submission_generation + 1)
  end

  # --- Short ownership lease (Guardrail 2) --------------------------------------------------------------
  # Briefly locks the row to claim/renew ownership, then RELEASES the DB connection so the caller performs Meta
  # HTTP calls OUTSIDE any transaction/lock. Returns true if this worker now owns the lease.
  def claim_lease!(owner:, ttl_seconds: DEFAULT_LEASE_SECONDS, expected_generation: nil)
    claimed = false
    with_lock do
      if claimable?(owner, expected_generation)
        update!(processing_owner: owner, lease_expires_at: Time.current + ttl_seconds)
        claimed = true
      end
    end
    claimed
  rescue ActiveRecord::StaleObjectError
    false
  end

  def claimable?(owner, expected_generation)
    active? &&
      (expected_generation.nil? || submission_generation == expected_generation.to_i) &&
      !leased_by_other?(owner)
  end

  def leased_by_other?(owner)
    processing_owner.present? && processing_owner != owner && lease_expires_at.present? && lease_expires_at.future?
  end

  def lease_held_by?(owner)
    processing_owner == owner && lease_expires_at.present? && lease_expires_at.future?
  end

  def release_lease!
    update!(processing_owner: nil, lease_expires_at: nil)
  end

  # --- Status transitions ------------------------------------------------------------------------------
  def transition!(new_status, step: nil, error_code: nil)
    attrs = { status: new_status }
    attrs[:step] = step if step
    attrs[:safe_error_code] = error_code if error_code
    update!(attrs)
  end

  # --- Safe DTO (no secrets; masked phone only) --------------------------------------------------------
  def to_status_dto
    {
      attempt_id: public_uuid,
      status: status,
      step: step,
      phone: masked_phone,
      inbox_id: inbox_id,
      channel_id: channel_whatsapp_id,
      action_required: status == ACTION_REQUIRED,
      error_code: safe_error_code
    }.compact
  end

  private

  def assign_public_uuid
    self.public_uuid ||= SecureRandom.uuid
  end
end
