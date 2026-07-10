# Persistence seam for the async onboarding processor. Reuses the shared, idempotent persistence mixin
# (Bloomwire::WhatsappSignupPersistence) so the processor NEVER re-implements DB persistence: exactly one
# Channel/Inbox/Setup, reconnect-safe (a retry refreshes the existing records instead of duplicating). Injectable,
# so the processor spec can substitute a fake without touching the real DB persist path. No Meta calls happen here.
class Bloomwire::WhatsappOnboardingPersister
  include Bloomwire::WhatsappSignupPersistence

  def initialize(account)
    @account = account
  end

  # Returns the created/reconnected Bloomwire::WhatsappSetup, or a safe Symbol error (never raises for a mapping
  # conflict). The mixin writes the token ONLY to Channel::Whatsapp#provider_config (encrypted, ADR-0006).
  def call(token:, waba_id:, phone_info:, verification_pin:, capability:)
    persist(token, waba_id, phone_info, verification_pin, capability)
  end
end
