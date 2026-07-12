# Ownership-lease and DB-only persistence-fence primitives for the async onboarding attempt (Guardrail 2).
# The lease is claimed/renewed under a SHORT row lock and RELEASED before any Meta HTTP call; the mutation TTL
# outlasts the maximum bounded Graph call. Local persistence/finalization re-locks the Attempt and verifies active
# status + owner + submission_generation + valid lease in the same transaction as the guarded database writes.
module Bloomwire::WhatsappOnboardingLeasable
  extend ActiveSupport::Concern

  DEFAULT_LEASE_SECONDS = 120
  # Documented safety margin added on top of the maximum bounded Graph call to form the mutation-stage lease TTL.
  LEASE_SAFETY_MARGIN_SECONDS = 30

  class_methods do
    # Mutation-stage lease TTL, DERIVED AT RUNTIME from the single Graph-timeout provider (open + read) plus the
    # safety margin. A change to the Graph timeout config AUTOMATICALLY widens/narrows the lease budget (no
    # hardcoded duplication). Always > the single-call maximum (margin is positive), so the lease cannot expire
    # mid-call while the DB lock is released for the Meta HTTP call.
    def mutation_lease_seconds
      Whatsapp::GraphApiTimeouts.max_call_seconds + Bloomwire::WhatsappOnboardingLeasable::LEASE_SAFETY_MARGIN_SECONDS
    end
  end

  def mutation_lease_seconds
    self.class.mutation_lease_seconds
  end

  # Briefly locks the row to claim ownership, then RELEASES the DB connection so the caller performs Meta HTTP
  # calls OUTSIDE any transaction/lock. Returns true if this worker now owns the lease.
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

  # Guarded release: only the CURRENT owner on the CURRENT generation may release, under a short row lock, so a
  # stale worker can never clear a newer worker's lease. No-op otherwise.
  def release_lease!(owner:, expected_generation:)
    with_lock do
      update!(processing_owner: nil, lease_expires_at: nil) if lease_held_by?(owner) && submission_generation == expected_generation.to_i
    end
  end

  # Briefly (short row lock) extend THIS worker's lease before a mutation/network stage, but only while it still
  # owns the lease on the current generation and the attempt is active. Returns false if the lease was lost.
  def renew_lease!(owner:, expected_generation:, ttl_seconds: mutation_lease_seconds)
    renewed = false
    with_lock do
      if active? && lease_held_by?(owner) && submission_generation == expected_generation.to_i
        update!(lease_expires_at: Time.current + ttl_seconds)
        renewed = true
      end
    end
    renewed
  end

  def owner_guarded_update!(attributes, owner:, expected_generation:)
    owner_guarded_write!(owner, expected_generation) { update!(attributes) }
  end

  def with_persistence_fence!(owner:, expected_generation:, &)
    owner_guarded_write!(owner, expected_generation, &)
  end

  def finalize_persisted_setup!(setup, owner:, expected_generation:, credential_persisted: true)
    attributes = persisted_setup_attributes(setup, credential_persisted)
    owner_guarded_update!(attributes, owner: owner, expected_generation: expected_generation)
  end

  def owner_guarded_terminalize!(status, error_code:, owner:, expected_generation:)
    owner_guarded_update!(
      {
        status: status, safe_error_code: error_code, oauth_code: nil, access_token: nil,
        token_stage: nil, secrets_cleared_at: Time.current
      },
      owner: owner,
      expected_generation: expected_generation
    )
  end

  private

  def persisted_setup_attributes(setup, credential_persisted)
    attributes = {
      channel_whatsapp_id: setup.channel_whatsapp_id,
      inbox_id: setup.inbox_id,
      status: setup.setup_status == Bloomwire::WhatsappSetup::ROUTEABLE_STATUS ? self.class::COMPLETED : self.class::ACTION_REQUIRED
    }
    attributes[:waba_id] = setup.waba_id if setup.waba_id.present?
    attributes[:phone_number_id] = setup.phone_number_id if setup.phone_number_id.present?
    attributes[:phone_number_masked] = self.class.mask_phone(setup.display_phone_number) if setup.display_phone_number.present?
    if credential_persisted
      attributes.merge!(access_token: nil, token_stage: nil, credential_persisted_at: Time.current, secrets_cleared_at: Time.current)
    end
    attributes
  end
end
