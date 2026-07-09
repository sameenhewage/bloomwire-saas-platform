# Short ownership-lease primitives for the async onboarding attempt (Guardrail 2). Extracted so the model stays
# focused. The lease is claimed/renewed under a SHORT row lock (with_lock) and RELEASED before any Meta HTTP call;
# the mutation TTL outlasts the maximum bounded Graph call so the lease cannot expire mid-call. Release and renew
# are guarded by (owner + submission_generation) so a stale worker can never clear or extend a newer worker's lease.
module Bloomwire::WhatsappOnboardingLeasable
  extend ActiveSupport::Concern

  DEFAULT_LEASE_SECONDS = 120

  # Mutation-stage lease TTL must OUTLAST the maximum bounded Graph call so the lease cannot expire mid-call.
  # Bounded call = Graph open timeout + read timeout; a documented safety margin is added on top. Derived from the
  # single source of truth (Whatsapp::FacebookApiClient): (5 + 25) + 30 = 60s, comfortably > the 30s max call.
  GRAPH_MAX_CALL_SECONDS = Whatsapp::FacebookApiClient::OPEN_TIMEOUT_SECONDS + Whatsapp::FacebookApiClient::READ_TIMEOUT_SECONDS
  LEASE_SAFETY_MARGIN_SECONDS = 30
  MUTATION_LEASE_SECONDS = GRAPH_MAX_CALL_SECONDS + LEASE_SAFETY_MARGIN_SECONDS

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
  def renew_lease!(owner:, expected_generation:, ttl_seconds: MUTATION_LEASE_SECONDS)
    renewed = false
    with_lock do
      if active? && lease_held_by?(owner) && submission_generation == expected_generation.to_i
        update!(lease_expires_at: Time.current + ttl_seconds)
        renewed = true
      end
    end
    renewed
  end
end
