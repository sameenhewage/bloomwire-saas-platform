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
class Bloomwire::WhatsappOnboardingAttempt < ApplicationRecord
  self.table_name = 'bloomwire_whatsapp_onboarding_attempts'

  # Fail-closed: raised (with NO secret material) when a secret write is attempted while ActiveRecord encryption
  # is unavailable. oauth_code/access_token are NEVER persisted in plaintext.
  class SecretStorageUnavailableError < StandardError; end

  # Raised when a worker whose lease/generation is no longer current attempts to write credentials, so a stale
  # worker can never clear or clobber a newer submission's secret.
  class StaleWorkerError < StandardError; end

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

  # Guardrail 5: phone_number_masked may only hold a masked value (e.g. "****1234") or be blank — a full number
  # must never be storable, even via a direct update that bypasses #bind_target!.
  MASKED_PHONE_FORMAT = /\A\*{2,}\d{1,4}\z/
  # Fail-closed refusal message (carries NO secret material).
  SECRET_ENCRYPTION_REQUIRED = 'onboarding secret write refused: ActiveRecord encryption is not configured'.freeze

  before_validation :assign_public_uuid, on: :create
  before_save :guard_secret_encryption!
  validates :public_uuid, presence: true, uniqueness: true
  validates :status, inclusion: { in: STATUSES }
  validates :phone_number_masked, format: { with: MASKED_PHONE_FORMAT }, allow_blank: true

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
  # Fail-closed on encryption for BOTH the explicit call and (via #guard_secret_encryption!) any raw write.
  def store_code!(code)
    ensure_secret_storage_available!
    update!(oauth_code: code, code_received_at: Time.current)
  end

  def clear_code!
    update!(oauth_code: nil)
  end

  # After a successful exchange: persist the operational token (retained for retries) and IMMEDIATELY drop the code.
  # Guarded (Guardrail 2 / stale-worker): only the current lease owner on the current submission_generation may
  # write; the verify + write run under ONE short row lock (DB-only, no network) so a concurrent submit that
  # bumped the generation cannot be clobbered.
  def store_access_token!(token, owner:, expected_generation:)
    ensure_secret_storage_available!
    owner_guarded_write!(owner, expected_generation) do
      update!(access_token: token, oauth_code: nil, code_exchanged_at: Time.current)
    end
  end

  # After the token is written to the Channel provider_config AND verified: drop the attempt-level token. Guarded
  # so a stale worker cannot clear a newer submission's credential.
  def mark_credential_persisted!(owner:, expected_generation:)
    owner_guarded_write!(owner, expected_generation) do
      update!(access_token: nil, credential_persisted_at: Time.current, secrets_cleared_at: Time.current)
    end
  end

  # Terminal cleanup — clear BOTH secrets (expiry / cancel / final failure / Slice 3 TTL sweep). Intentionally
  # UNGUARDED: clearing is always security-safe and must work for owner-less callers (TTL sweep, user cancel).
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

  # Comprehensive fail-closed backstop: refuse to persist a NON-nil oauth_code/access_token when AR encryption is
  # unavailable. Runs on EVERY save, so it also covers raw update!(oauth_code:/access_token:) — not just the
  # lifecycle methods. Clearing a secret (writing nil) is always allowed.
  def guard_secret_encryption!
    return if Chatwoot.encryption_configured?
    return unless will_persist_secret_plaintext?

    raise SecretStorageUnavailableError, SECRET_ENCRYPTION_REQUIRED
  end

  def will_persist_secret_plaintext?
    (will_save_change_to_oauth_code? && oauth_code.present?) ||
      (will_save_change_to_access_token? && access_token.present?)
  end

  def ensure_secret_storage_available!
    raise SecretStorageUnavailableError, SECRET_ENCRYPTION_REQUIRED unless Chatwoot.encryption_configured?
  end

  # Verify (under a short row lock, DB-only, NO network) that this worker still owns the active lease on the
  # expected generation, then perform the credential write atomically. A stale/non-owning worker raises
  # StaleWorkerError BEFORE any write, so a newer submission's credential is never cleared or overwritten.
  def owner_guarded_write!(owner, expected_generation)
    with_lock do
      unless active_credential_owner?(owner, expected_generation)
        raise StaleWorkerError, 'credential write refused: not the current lease owner on the current generation'
      end

      yield
    end
  end

  def active_credential_owner?(owner, expected_generation)
    !terminal? && submission_generation == expected_generation.to_i && lease_held_by?(owner)
  end
end
