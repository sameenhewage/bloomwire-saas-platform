# Slice 3 (ADR-0010 v3): scheduled sweep that recovers stalled async onboarding attempts (enqueue-gap + dead
# worker), expires abandoned ones past the configurable TTL, and clears any lingering terminal secret. Idempotent;
# safe to run on a fixed cadence. Delegates all logic to Bloomwire::WhatsappOnboardingRecovery.
class Bloomwire::WhatsappOnboardingSweepJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform
    Bloomwire::WhatsappOnboardingRecovery.sweep!
  end
end
