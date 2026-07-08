# TEMPORARY (Stage 1 controlled register-PIN test) — REMOVE after the one-attempt PIN evidence is captured.
#
# DEV-ONLY, flag-gated, EXACT-TARGET override of the Cloud API /register 2FA PIN used by the Bloomwire managed
# embedded-signup (Bloomwire::WhatsappEmbeddedSignupService#register_number, inherited by the Coexistence
# service). Its sole purpose is Stage 1 of the /register-failure diagnosis: hold the partner SYSTEM_USER token
# path identical and change ONLY the PIN — from a fresh random value to the known WhatsAway source constant
# 123456 — for exactly ONE target number on the DEV deployment.
#
# Guarantees (ALL four must hold or the caller keeps its existing random PIN):
# - NOT production: hard-blocked on any deployment labelled BLOOMWIRE_ENV=production (mirrors
#   Bloomwire::WhatsappRuntimeTokenDebug), so it can never fire in production even if the flag is mis-set.
# - EXACT WABA: the selected WABA equals the one target WABA.
# - EXACT phone: the phone_number_id equals the one target number.
# - EXPLICIT flag: the temporary InstallationConfig flag BLOOMWIRE_WHATSAPP_REGISTER_PIN_OVERRIDE is ON
#   (default OFF).
# Otherwise .pin_for returns nil and the caller falls back to SecureRandom, so every other environment, WABA,
# phone, and the flag-off case are unchanged. The constant is the already-known WhatsAway source PIN; nothing
# here logs the PIN, token, or any secret.
class Bloomwire::WhatsappRegistrationPinOverride
  FLAG = 'BLOOMWIRE_WHATSAPP_REGISTER_PIN_OVERRIDE'.freeze
  TARGET_WABA_ID = '1029255689498274'.freeze
  TARGET_PHONE_NUMBER_ID = '1249446648242795'.freeze
  OVERRIDE_PIN = '123456'.freeze

  # The override PIN when active for the EXACT DEV target, otherwise nil (caller uses a fresh random PIN).
  def self.pin_for(waba_id:, phone_number_id:)
    active?(waba_id: waba_id, phone_number_id: phone_number_id) ? OVERRIDE_PIN : nil
  end

  def self.active?(waba_id:, phone_number_id:)
    return false if production_deployment?
    return false unless waba_id.to_s == TARGET_WABA_ID
    return false unless phone_number_id.to_s == TARGET_PHONE_NUMBER_ID

    flag_enabled?
  end

  # Mirrors Bloomwire::WhatsappRuntimeTokenDebug: a deployment explicitly labelled production can never override.
  def self.production_deployment?
    ENV['BLOOMWIRE_ENV'].to_s.casecmp('production').zero?
  end

  def self.flag_enabled?
    ActiveModel::Type::Boolean.new.cast(GlobalConfigService.load(FLAG, false))
  end
end
