# Phase 17B: read-only, SECRET-FREE summary of the global WhatsApp platform config for the SuperAdmin
# "Global WhatsApp Config" page. Values are sourced via GlobalConfigService (DB InstallationConfig → ENV
# fallback) and Bloomwire::Features.
#
# Security (do not weaken): the global secrets — WHATSAPP_APP_SECRET and BLOOMWIRE_WHATSAPP_GLOBAL_VERIFY_TOKEN —
# are reported ONLY as present?/missing; their VALUES are never read, returned, or rendered. This surface stores
# nothing, edits nothing, and never calls Meta. The Meta App ID (WHATSAPP_APP_ID) is a PUBLIC identifier (already
# exposed to the dashboard frontend via window.chatwootConfig), so it may be shown. Global secrets stay
# ENV/ops-managed (there is no encrypted global-secret store — see ADR-0008 / 17B discovery); this page is
# read-only and does NOT provide a way to save them.
class Bloomwire::GlobalWhatsappConfig
  CALLBACK_PATH = '/bloomwire/webhooks/whatsapp'.freeze
  APP_SECRET_KEY = 'WHATSAPP_APP_SECRET'.freeze
  VERIFY_TOKEN_KEY = 'BLOOMWIRE_WHATSAPP_GLOBAL_VERIFY_TOKEN'.freeze
  PUBLIC_HOST_KEY = 'BLOOMWIRE_WHATSAPP_PUBLIC_CALLBACK_HOST'.freeze
  APP_ID_KEY = 'WHATSAPP_APP_ID'.freeze
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

  # Human-readable NAMES only of missing global prerequisites — never a secret value.
  def blockers
    @blockers ||= [].tap do |list|
      list << 'Bloomwire mode is OFF' unless Bloomwire::Features.master_enabled?
      list << 'Global webhook router is OFF' unless Bloomwire::Features.enabled?(:global_webhook_router)
      list << "#{APP_SECRET_KEY} is missing" unless config_present?(APP_SECRET_KEY)
      list << "#{VERIFY_TOKEN_KEY} is missing" unless config_present?(VERIFY_TOKEN_KEY)
      list << "#{PUBLIC_HOST_KEY} is missing/invalid" unless public_host_valid?
    end
  end

  def connected_inbox_count
    Bloomwire::WhatsappSetup.where(setup_status: 'ready_for_webhook').count
  end
end
