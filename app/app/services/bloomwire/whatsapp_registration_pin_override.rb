# TEMPORARY (Stage 1 controlled register-PIN test) — REMOVE after the one-attempt PIN evidence is captured.
#
# DEV-ONLY, flag-gated, EXACT-TARGET, ONE-SHOT override of the Cloud API /register 2FA PIN used by the Bloomwire
# managed embedded-signup (Bloomwire::WhatsappEmbeddedSignupService#register_number, inherited by the Coexistence
# service). Its sole purpose is Stage 1 of the /register-failure diagnosis: hold the partner SYSTEM_USER token
# path identical and change ONLY the PIN — from a fresh random value to the known WhatsAway source constant
# 123456 — for exactly ONE target number on the DEV deployment, for a single attempt.
#
# Safety (ALL must hold or the caller keeps its existing random PIN):
# - NOT production: hard-blocked on any deployment labelled BLOOMWIRE_ENV=production (mirrors
#   Bloomwire::WhatsappRuntimeTokenDebug), so it can never fire in production even if the flag is mis-set.
# - EXACT WABA + EXACT phone_number_id: only the one target number can ever be affected.
# - ARMED WINDOW with AUTO-TIMEOUT: the InstallationConfig flag BLOOMWIRE_WHATSAPP_REGISTER_PIN_OVERRIDE holds a
#   FUTURE ISO8601 expiry set by .arm! (window = ARM_WINDOW). Absent / blank / non-timestamp / past = OFF, so it
#   self-disables when no attempt occurs in the window, and a stray boolean toggle fails closed.
# - ONE-SHOT: serving the PIN deletes the flag (best-effort, never raising into onboarding), so a second attempt
#   — even a retry after a failure — cannot reuse the override.
# Otherwise .pin_for returns nil and the caller falls back to SecureRandom, so every other environment, WABA,
# phone, and the disarmed/expired case are unchanged. The constant is the already-known WhatsAway source PIN;
# nothing here logs the PIN, token, or any secret.
class Bloomwire::WhatsappRegistrationPinOverride
  FLAG = 'BLOOMWIRE_WHATSAPP_REGISTER_PIN_OVERRIDE'.freeze
  TARGET_WABA_ID = '1029255689498274'.freeze
  TARGET_PHONE_NUMBER_ID = '1249446648242795'.freeze
  OVERRIDE_PIN = '123456'.freeze
  ARM_WINDOW = 30.minutes

  # The override PIN when active for the EXACT DEV target within the armed window, otherwise nil (caller uses a
  # fresh random PIN). Serving the PIN consumes the arm (one-shot), so it can never apply to a second attempt.
  def self.pin_for(waba_id:, phone_number_id:)
    return nil unless active?(waba_id: waba_id, phone_number_id: phone_number_id)

    consume!
    OVERRIDE_PIN
  end

  def self.active?(waba_id:, phone_number_id:)
    return false if production_deployment?
    return false unless waba_id.to_s == TARGET_WABA_ID
    return false unless phone_number_id.to_s == TARGET_PHONE_NUMBER_ID

    armed?
  end

  # Armed only while the flag holds a FUTURE ISO8601 expiry (auto-expires; blank/absent/non-timestamp/past = off).
  def self.armed?
    expiry = parse_time(GlobalConfigService.load(FLAG, nil))
    expiry.present? && Time.current < expiry
  end

  # Arm the override for ARM_WINDOW from now (DEV operational step). Returns the ISO8601 expiry it stored.
  def self.arm!
    expiry = ARM_WINDOW.from_now.iso8601
    write_flag(expiry)
    expiry
  end

  # Fully remove the flag. Both the manual disable and the one-shot consume use this.
  def self.disarm!
    InstallationConfig.where(name: FLAG).destroy_all
    true
  end

  # Best-effort one-shot consume: never raises into onboarding if the disarm write fails.
  def self.consume!
    disarm!
  rescue StandardError => e
    Rails.logger.warn("[BLOOMWIRE EMBEDDED SIGNUP] register PIN override consume skipped: #{e.class}")
    false
  end

  # Mirrors Bloomwire::WhatsappRuntimeTokenDebug: a deployment explicitly labelled production can never override.
  def self.production_deployment?
    ENV['BLOOMWIRE_ENV'].to_s.casecmp('production').zero?
  end

  def self.write_flag(value)
    config = InstallationConfig.find_or_initialize_by(name: FLAG)
    config.locked = false
    config.value = value
    config.save!
  end

  def self.parse_time(value)
    return nil if value.blank?

    Time.zone.parse(value.to_s)
  rescue ArgumentError, TypeError
    nil
  end

  private_class_method :write_flag, :parse_time
end
