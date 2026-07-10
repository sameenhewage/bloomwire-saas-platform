# Slice 3 (ADR-0010 v3): drives ONE async onboarding attempt off the request via the resumable processor. High
# priority (user-facing, near-realtime). Idempotent + retry-safe: the processor claims a short lease, reconciles
# Meta state before every mutation, and no-ops when the attempt is already terminal — so a duplicate enqueue or a
# Sidekiq retry after a partial failure is safe. Args contain only the attempt id + non-secret submission_generation;
# credentials/provider payloads never enter the job. A superseded generation no-ops here and at the processor lease.
class Bloomwire::WhatsappOnboardingJob < ApplicationJob
  queue_as :high

  def perform(attempt_id, expected_generation = nil)
    attempt = Bloomwire::WhatsappOnboardingAttempt.find_by(id: attempt_id)
    return if attempt.nil? || attempt.terminal?
    return if expected_generation.present? && attempt.submission_generation != expected_generation.to_i

    Bloomwire::WhatsappOnboardingProcessor.new(
      attempt: attempt,
      owner: "onboarding-job-#{provider_job_id.presence || SecureRandom.hex(6)}",
      generation: expected_generation
    ).process
  end
end
