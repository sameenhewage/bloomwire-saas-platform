# Strict, Bloomwire-ONLY WhatsApp phone registration/readiness check, run by the
# Bloomwire adapter AFTER webhook setup (ADR 0005, PR #23 P2 round 2).
#
# Why this exists: the shared Whatsapp::WebhookSetupService#register_phone_number RESCUES
# Meta phone-registration errors (only logs a warning) and still proceeds to subscribe the
# WABA webhook. That lenient behavior is INTENTIONAL for the existing Chatwoot/tenant
# embedded-signup flow and is left untouched here. But it means a webhook subscribe returning
# does NOT prove the number is actually registered/usable on the Cloud API — so the Bloomwire
# orchestrator could flip BloomwireChannelIntegration to active while the number is still
# unregistered. Only the stricter Bloomwire SuperAdmin path verifies readiness here; the
# tenant/Chatwoot path keeps the old lenient behavior unchanged.
#
# It reuses the failure-surfacing Whatsapp::HealthService (which RAISES on a non-200 Meta
# response, unlike the swallowed registration call) and confirms the number is verified and
# provisioned, mirroring BOTH signals Whatsapp::WebhookSetupService#phone_number_in_pending_state?
# uses to decide a number still "needs registration" (platform_type AND throughput.level), plus
# code_verification_status — so "ready" here is the exact inverse of "registration was needed",
# which a silently-failed /register leaves true (an unprovisioned number reports platform_type or
# throughput.level NOT_APPLICABLE, or omits throughput entirely).
#
# It never persists anything and never surfaces raw provider data: provider/transport errors
# are logged server-side and only a machine-readable symbol is returned (nil when ready). It
# reads secrets only from the channel's provider_config (HealthService uses provider_config['api_key']).
class Bloomwire::ChannelSetup::WhatsappReadinessValidator
  def initialize(channel)
    @channel = channel
  end

  # nil  -> the phone number is registered/verified and provisioned; safe to mark active.
  # else -> a coded error symbol the adapter turns into a Bloomwire::ChannelSetup::SetupError:
  #   :phone_registration_unverifiable -> Meta could not be queried for the number's health
  #   :phone_not_ready                 -> Meta answered but the number is not verified/provisioned
  def error_code
    health = health_status
    return :phone_registration_unverifiable if health.nil?
    return :phone_not_ready unless ready?(health)

    nil
  end

  private

  # Ready = code-verified AND provisioned on a platform AND assigned messaging throughput. This
  # is the exact inverse of the signals Whatsapp::WebhookSetupService uses to decide a number
  # still needs registration (phone_number_verified? + phone_number_in_pending_state?, the latter
  # flagging platform_type OR throughput.level == NOT_APPLICABLE). If the swallowed /register call
  # failed, the number stays unverified, or platform_type / throughput.level NOT_APPLICABLE, which
  # we catch here so the Bloomwire path never reports a channel active when sends are not ready.
  def ready?(health)
    health[:code_verification_status] == 'VERIFIED' &&
      provisioned?(health[:platform_type]) &&
      provisioned?(throughput_level(health))
  end

  # Meta reports NOT_APPLICABLE (or omits the field) for an attribute that is not fully
  # provisioned; a usable number reports a concrete value.
  def provisioned?(value)
    value.present? && value != 'NOT_APPLICABLE'
  end

  # Whatsapp::HealthService returns throughput as raw parsed Meta JSON — a nested object whose
  # inner key is a STRING ("level"), under a symbol top-level key — while other callers/specs use
  # symbol keys. Read BOTH shapes so a missing OR NOT_APPLICABLE level is caught either way.
  def throughput_level(health)
    throughput = health[:throughput] || health['throughput']
    return nil unless throughput.is_a?(Hash)

    throughput[:level] || throughput['level']
  end

  # Whatsapp::HealthService raises on a non-200 Meta response (unlike the swallowed
  # registration call), so a provider/transport failure surfaces here. We treat any failure as
  # "cannot verify readiness" and never leak the raw provider error into the response.
  def health_status
    Whatsapp::HealthService.new(@channel).fetch_health_status
  rescue StandardError => e
    Rails.logger.error("[BLOOMWIRE] WhatsApp phone readiness verification failed: #{e.message}")
    nil
  end
end
