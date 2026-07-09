# Slice 3 (ADR-0010 v3): scheduled recovery + TTL sweep for async onboarding attempts. Closes the enqueue gap and
# reclaims dead workers, and enforces that temporary credentials never linger. All thresholds are CONFIGURABLE via
# GlobalConfigService; the waiting-for-Meta budget is deliberately GENEROUS (never short).
#
# sweep! order matters: expire the truly-abandoned FIRST (so they leave the active set), THEN redrive the merely
# stalled, THEN clear any secret still held by a terminal attempt. Every step is idempotent.
class Bloomwire::WhatsappOnboardingRecovery
  Attempt = Bloomwire::WhatsappOnboardingAttempt
  # In-progress statuses eligible for the give-up TTL sweep. Deliberately EXCLUDES action_required (a persisted
  # setup awaiting the owner's Recheck must never be auto-expired) and the terminal statuses.
  SWEEPABLE_STATUSES = ([Attempt::WAITING_META] + Attempt::REDRIVABLE_STATUSES).freeze

  # Give-up TTL for a non-terminal attempt (abandoned Meta popup / stuck): generous by default (30 min).
  ABANDON_TTL_KEY = 'BLOOMWIRE_WHATSAPP_ONBOARDING_ABANDON_TTL_SECONDS'.freeze
  DEFAULT_ABANDON_TTL_SECONDS = 30.minutes.to_i
  # A redrivable attempt is only re-enqueued after this grace (avoids racing a worker that just claimed it).
  REDRIVE_GRACE_KEY = 'BLOOMWIRE_WHATSAPP_ONBOARDING_REDRIVE_GRACE_SECONDS'.freeze
  DEFAULT_REDRIVE_GRACE_SECONDS = 60

  def self.sweep!
    new.sweep!
  end

  def sweep!
    expire_abandoned!
    redrive_stalled!
    clear_terminal_secrets!
  end

  # Give-up TTL cleanup (incl. abandoned waiting_meta): expire the attempt and clear its secrets so no credential
  # lingers. Runs before redrive so an ancient attempt is not re-enqueued.
  def expire_abandoned!
    abandoned_scope.find_each do |attempt|
      attempt.transition!(Attempt::EXPIRED, error_code: 'onboarding_abandoned')
      attempt.clear_secrets!
    end
  end

  # Recovery: re-enqueue redrivable attempts (queued-but-never-enqueued, or processing whose worker died) that hold
  # no live lease and have been idle past the grace. The job + processor lease make a duplicate enqueue safe.
  def redrive_stalled!
    stalled_scope.find_each do |attempt|
      Bloomwire::WhatsappOnboardingJob.perform_later(attempt.id, attempt.submission_generation)
    end
  end

  # Defence in depth: a TERMINAL attempt must never still hold a secret.
  def clear_terminal_secrets!
    Attempt.where(status: Attempt::TERMINAL_STATUSES)
           .where('oauth_code IS NOT NULL OR access_token IS NOT NULL')
           .find_each(&:clear_secrets!)
  end

  private

  def abandoned_scope
    Attempt.where(status: SWEEPABLE_STATUSES).where(updated_at: ..abandon_ttl_seconds.seconds.ago)
  end

  def stalled_scope
    Attempt.where(status: Attempt::REDRIVABLE_STATUSES)
           .where('lease_expires_at IS NULL OR lease_expires_at < ?', Time.current)
           .where(updated_at: ..redrive_grace_seconds.seconds.ago)
  end

  def abandon_ttl_seconds
    GlobalConfigService.load(ABANDON_TTL_KEY, DEFAULT_ABANDON_TTL_SECONDS).to_i
  end

  def redrive_grace_seconds
    GlobalConfigService.load(REDRIVE_GRACE_KEY, DEFAULT_REDRIVE_GRACE_SECONDS).to_i
  end
end
