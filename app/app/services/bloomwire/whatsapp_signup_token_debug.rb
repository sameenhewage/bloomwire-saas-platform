# DEV-only, SANITIZED inspection of the exact Embedded Signup token used for managed onboarding. Answers the Meta
# (#10 / #100) authority question directly — "is this token a USER/SYSTEM_USER, for which app, and does it actually
# hold whatsapp_business_management / whatsapp_business_messaging on the SELECTED WABA?" — plus the WABA's owner
# business, without any manual Graph Explorer call.
#
# SECURITY (do not weaken): NEVER logs the token / app secret / raw body. It logs only sanitized identifiers already
# treated as non-secret elsewhere (token type, actor/app/business ids, boolean scope-on-WABA flags). Gated OFF by
# default (BLOOMWIRE_WHATSAPP_TOKEN_DEBUG) and hard-blocked outside dev/test, so it is inert in production and CI.
class Bloomwire::WhatsappSignupTokenDebug
  EVENT = 'bloomwire.whatsapp.signup_token_debug'.freeze
  FLAG = 'BLOOMWIRE_WHATSAPP_TOKEN_DEBUG'.freeze
  MANAGEMENT_SCOPE = 'whatsapp_business_management'.freeze
  MESSAGING_SCOPE = 'whatsapp_business_messaging'.freeze

  # Enabled ONLY in dev/test AND when the flag is explicitly 'true'. Never in production.
  def self.enabled?
    (Rails.env.development? || Rails.env.test?) && GlobalConfigService.load(FLAG, 'false').to_s == 'true'
  end

  # Best-effort: a debug failure never affects onboarding (it only writes a sanitized log line).
  def self.log(client:, token:, waba_id:, phone_number_id:)
    return unless enabled?

    new(client: client, token: token, waba_id: waba_id, phone_number_id: phone_number_id).log
  rescue StandardError => e
    Rails.logger.warn("[BLOOMWIRE SIGNUP TOKEN DEBUG] #{{ event: EVENT, error: e.class.name }.to_json}")
  end

  def initialize(client:, token:, waba_id:, phone_number_id:)
    @client = client
    @token = token
    @waba_id = waba_id.to_s
    @phone_number_id = phone_number_id
  end

  def log
    data = @client.debug_token(@token)['data'] || {}
    granular = data['granular_scopes'] || []
    Rails.logger.warn("[BLOOMWIRE SIGNUP TOKEN DEBUG] #{event_hash(data, granular).to_json}")
  end

  private

  def event_hash(data, granular)
    {
      event: EVENT, token_type: data['type'], app_id: data['app_id'], actor_id: data['user_id'],
      is_valid: data['is_valid'], scopes: Array(data['scopes']), granular_scopes: granular.pluck('scope'),
      waba_in_management: target_ids(granular, MANAGEMENT_SCOPE).include?(@waba_id),
      waba_in_messaging: target_ids(granular, MESSAGING_SCOPE).include?(@waba_id),
      selected_waba: @waba_id, phone_number_id: @phone_number_id, waba_owner_business_id: safe_waba_owner
    }
  end

  def target_ids(granular, scope_name)
    Array((granular.find { |scope| scope['scope'] == scope_name } || {})['target_ids']).map(&:to_s)
  end

  def safe_waba_owner
    @client.waba_owner_business_id(@waba_id)
  rescue StandardError
    nil
  end
end
