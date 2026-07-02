# Phase 17B: read-only, SECRET-FREE summary of the global WhatsApp platform config for the SuperAdmin
# "Global WhatsApp Config" page. Values are sourced via GlobalConfigService (DB InstallationConfig → ENV
# fallback) and Bloomwire::Features.
#
# Security (do not weaken): the global secrets — WHATSAPP_APP_SECRET and BLOOMWIRE_WHATSAPP_GLOBAL_VERIFY_TOKEN —
# are reported ONLY as present?/missing; their VALUES are never read, returned, or rendered. This surface stores
# nothing, edits nothing, and never calls Meta. The Meta App ID (WHATSAPP_APP_ID) is a PUBLIC identifier (already
# exposed to the dashboard frontend via window.chatwootConfig), so it may be shown. Global secrets stay
# ENV/ops-managed (there is no encrypted global-secret store — see ADR-0008 / 17B discovery); this page is
# read-only and does NOT provide a way to save them. The Meta App ID is also a required platform-readiness
# prerequisite (customer onboarding in PR C is Embedded Signup first, which needs the app id) — its presence
# gates platform_ready and, when missing, is named in blockers.
class Bloomwire::GlobalWhatsappConfig
  CALLBACK_PATH = '/bloomwire/webhooks/whatsapp'.freeze
  APP_SECRET_KEY = 'WHATSAPP_APP_SECRET'.freeze
  VERIFY_TOKEN_KEY = 'BLOOMWIRE_WHATSAPP_GLOBAL_VERIFY_TOKEN'.freeze
  PUBLIC_HOST_KEY = 'BLOOMWIRE_WHATSAPP_PUBLIC_CALLBACK_HOST'.freeze
  APP_ID_KEY = 'WHATSAPP_APP_ID'.freeze
  CONFIGURATION_ID_KEY = 'WHATSAPP_CONFIGURATION_ID'.freeze
  PUBLIC_HOST_FORMAT = /\A[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?(?:\.[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?)*(?::\d{1,5})?\z/i

  def result
    {
      bloomwire_mode_enabled: Bloomwire::Features.master_enabled?,
      router_enabled: Bloomwire::Features.enabled?(:global_webhook_router),
      privacy_hardening_enabled: Bloomwire::Features.raw_enabled?(:privacy_hardening),
      callback_url: callback_url,
      callback_host_present: public_host.present?,
      callback_host_valid: public_host_valid?,
      verify_token_present: config_present?(VERIFY_TOKEN_KEY),
      app_secret_present: config_present?(APP_SECRET_KEY),
      app_id_present: config_present?(APP_ID_KEY),
      app_id: app_id_value, # public identifier — safe to display
      configuration_id_present: config_present?(CONFIGURATION_ID_KEY), # presence-only (Embedded Signup config id)
      platform_ready: blockers.empty?,
      blockers: blockers,
      connected_inbox_count: connected_inbox_count,
      last_webhook_received: nil # PR B: not tracked (no webhook-path write); UI renders "Not tracked yet"
    }
  end

  private

  # Presence only — NEVER returns the secret value.
  def config_present?(key)
    GlobalConfigService.load(key, nil).present?
  end

  # Meta App ID is a public Meta identifier (already surfaced to the dashboard frontend); not a secret.
  def app_id_value
    GlobalConfigService.load(APP_ID_KEY, nil).presence
  end

  def public_host
    @public_host ||= GlobalConfigService.load(PUBLIC_HOST_KEY, nil).to_s.strip.presence
  end

  def public_host_valid?
    public_host.present? && public_host.match?(PUBLIC_HOST_FORMAT)
  end

  def callback_url
    public_host_valid? ? "https://#{public_host}#{CALLBACK_PATH}" : nil
  end

  # Human-readable NAMES only of missing global prerequisites — never a secret value. WHATSAPP_APP_ID is a
  # required prerequisite because customer onboarding (PR C) is Embedded Signup first, which needs the Meta app id.
  def blockers
    @blockers ||= readiness_checks.reject { |passed, _message| passed }.map { |_passed, message| message }
  end

  # [passed?, message] pairs — data-driven so adding a prerequisite never grows branch complexity.
  def readiness_checks
    [
      [Bloomwire::Features.master_enabled?, 'Bloomwire mode is OFF'],
      [Bloomwire::Features.enabled?(:global_webhook_router), 'Global webhook router is OFF'],
      [config_present?(APP_ID_KEY), "#{APP_ID_KEY} is missing"],
      [config_present?(CONFIGURATION_ID_KEY), "#{CONFIGURATION_ID_KEY} is missing"],
      [config_present?(APP_SECRET_KEY), "#{APP_SECRET_KEY} is missing"],
      [config_present?(VERIFY_TOKEN_KEY), "#{VERIFY_TOKEN_KEY} is missing"],
      [public_host_valid?, "#{PUBLIC_HOST_KEY} is missing/invalid"]
    ]
  end

  def connected_inbox_count
    Bloomwire::WhatsappSetup.where(setup_status: 'ready_for_webhook').count
  end
end
