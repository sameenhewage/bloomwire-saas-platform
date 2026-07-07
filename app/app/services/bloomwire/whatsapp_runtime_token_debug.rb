# TEMPORARY (Phase 5 diagnostic) — REMOVE after the runtime-token evidence is captured.
#
# Flag-gated, DEV-only introspection of the EXACT runtime token returned by the embedded-signup OAuth code
# exchange. It runs Meta `debug_token` on that token BEFORE the Cloud API `/register` call and logs ONLY
# allow-listed, secret-free fields, so we can prove whether the token carries `whatsapp_business_management` (and
# `whatsapp_business_messaging`) with the selected WABA present in its granular `target_ids`. This is the missing
# read-only proof for why `/register` returns Meta `(#100) Need either permission on WhatsApp Business Account or
# owner business`.
#
# Guarantees:
# - Best-effort: it NEVER raises into onboarding and NEVER changes onboarding behavior (register / readiness gate /
#   resolver / subscription / persistence are untouched).
# - DEV-only: gated by the BLOOMWIRE_WHATSAPP_TOKEN_DEBUG flag (default OFF) and hard-blocked on any deployment
#   explicitly labelled `BLOOMWIRE_ENV=production`, so it can never run in production even if the flag is mis-set.
# - NEVER logged: the runtime access-token value, the app access token, the app secret, the OAuth code, the PIN,
#   Authorization headers, cookies, the raw request URL, or the raw response body. On failure ONLY the exception
#   class name is logged (never the message/body, which can echo the token).
class Bloomwire::WhatsappRuntimeTokenDebug
  EVENT = 'bloomwire.whatsapp.runtime_token_debug'.freeze
  FLAG = 'BLOOMWIRE_WHATSAPP_TOKEN_DEBUG'.freeze
  MANAGEMENT_SCOPE = 'whatsapp_business_management'.freeze
  MESSAGING_SCOPE = 'whatsapp_business_messaging'.freeze

  def self.enabled?
    return false if ENV['BLOOMWIRE_ENV'].to_s.casecmp('production').zero?

    ActiveModel::Type::Boolean.new.cast(GlobalConfigService.load(FLAG, false))
  end

  def initialize(client:, token:, selected_waba_id:)
    @client = client
    @token = token
    @selected_waba_id = selected_waba_id.to_s
  end

  # Best-effort: logs the sanitized event, never raises, never leaks secrets.
  def log
    Rails.logger.warn("[BLOOMWIRE EMBEDDED SIGNUP] #{safe_event(debug_data).to_json}")
  rescue StandardError => e
    Rails.logger.warn("[BLOOMWIRE EMBEDDED SIGNUP] #{failure_event(e).to_json}")
  end

  private

  # Uses the EXACT exchanged runtime token; debug_token authenticates with the app access token internally.
  def debug_data
    @client.debug_token(@token)['data'] || {}
  end

  def safe_event(data)
    granular = granular_scopes(data)
    {
      event: EVENT,
      operation: 'runtime_token_debug',
      selected_waba_id: @selected_waba_id,
      app_id: data['app_id'],
      token_type: data['type'],
      is_valid: data['is_valid'],
      expires_at: data['expires_at'],
      data_access_expires_at: data['data_access_expires_at'],
      scopes: Array(data['scopes']),
      granular_scopes: granular,
      management_scope_present: scope_present?(data, MANAGEMENT_SCOPE),
      messaging_scope_present: scope_present?(data, MESSAGING_SCOPE),
      selected_waba_in_management_targets: waba_in_scope?(granular, MANAGEMENT_SCOPE),
      selected_waba_in_messaging_targets: waba_in_scope?(granular, MESSAGING_SCOPE)
    }
  end

  # Each granular scope: its name plus its allow-listed target_ids (WABA/asset ids — not secrets).
  def granular_scopes(data)
    Array(data['granular_scopes']).map do |scope|
      { scope: scope['scope'], target_ids: Array(scope['target_ids']) }
    end
  end

  def scope_present?(data, scope_name)
    Array(data['scopes']).include?(scope_name) ||
      Array(data['granular_scopes']).any? { |scope| scope['scope'] == scope_name }
  end

  def waba_in_scope?(granular, scope_name)
    granular.any? do |scope|
      scope[:scope] == scope_name && scope[:target_ids].map(&:to_s).include?(@selected_waba_id)
    end
  end

  # Class only — never the message/body (a failed debug_token echoes the raw response, which can contain the token).
  def failure_event(error)
    { event: EVENT, operation: 'runtime_token_debug', selected_waba_id: @selected_waba_id,
      error: true, exception_class: error.class.name }
  end
end
