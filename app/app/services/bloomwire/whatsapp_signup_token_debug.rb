require 'openssl'

# DEV-only, SANITIZED inspection of the exact Embedded Signup token used for managed onboarding. Answers the Meta
# (#10 / #100) authority question directly — "is this token a USER/SYSTEM_USER, for which app, and does it actually
# hold whatsapp_business_management / whatsapp_business_messaging on the SELECTED WABA?" — plus the WABA's owner
# business, without any manual Graph Explorer call.
#
# SECURITY (do not weaken): NEVER logs the token / app secret / raw body. It logs only sanitized identifiers already
# treated as non-secret elsewhere (token type, actor/app/business ids, boolean scope-on-WABA flags, asset-task names).
# Gated OFF by default (BLOOMWIRE_WHATSAPP_TOKEN_DEBUG) and HARD-BLOCKED on real production (BLOOMWIRE_ENV=production),
# so it is inert unless a non-production operator explicitly turns it on. It works on DEV (which runs RAILS_ENV=production).
class Bloomwire::WhatsappSignupTokenDebug
  EVENT = 'bloomwire.whatsapp.signup_token_debug'.freeze
  FLAG = 'BLOOMWIRE_WHATSAPP_TOKEN_DEBUG'.freeze
  MANAGEMENT_SCOPE = 'whatsapp_business_management'.freeze
  MESSAGING_SCOPE = 'whatsapp_business_messaging'.freeze

  # Enabled ONLY when the flag is explicitly 'true' AND this is not real production. DEV runs RAILS_ENV=production, so
  # we gate on BLOOMWIRE_ENV (unset on DEV, set to 'production' on the real prod host) rather than Rails.env.
  def self.enabled?
    return false if ENV.fetch('BLOOMWIRE_ENV', '').to_s.casecmp?('production')

    GlobalConfigService.load(FLAG, 'false').to_s == 'true'
  end

  # Best-effort: a debug failure never affects onboarding (it only writes a sanitized log line).
  def self.log(client:, token:, waba_id:, phone_number_id:, stage: nil)
    return unless enabled?

    new(client: client, token: token, waba_id: waba_id, phone_number_id: phone_number_id, stage: stage).log
  rescue StandardError => e
    Rails.logger.warn("[BLOOMWIRE SIGNUP TOKEN DEBUG] #{{ event: EVENT, error: e.class.name }.to_json}")
  end

  def initialize(client:, token:, waba_id:, phone_number_id:, stage: nil)
    @client = client
    @token = token
    @waba_id = waba_id.to_s
    @phone_number_id = phone_number_id
    @stage = stage
  end

  def log
    data = @client.debug_token(@token)['data'] || {}
    granular = data['granular_scopes'] || []
    Rails.logger.warn("[BLOOMWIRE SIGNUP TOKEN DEBUG] #{event_hash(data, granular).to_json}")
  end

  private

  def event_hash(data, granular)
    management_target_ids = target_ids(granular, MANAGEMENT_SCOPE)
    messaging_target_ids = target_ids(granular, MESSAGING_SCOPE)
    actor_waba_tasks = safe_actor_tasks(data['user_id'])
    {
      event: EVENT, stage: @stage, token_fingerprint: token_fingerprint, token_type: data['type'],
      app_id: data['app_id'], actor_id: data['user_id'], is_valid: data['is_valid'],
      scopes: Array(data['scopes']), granular_scopes: granular.pluck('scope'),
      management_target_ids: management_target_ids, messaging_target_ids: messaging_target_ids,
      waba_in_management: management_target_ids.include?(@waba_id),
      waba_in_messaging: messaging_target_ids.include?(@waba_id),
      actor_waba_tasks: actor_waba_tasks, actor_has_manage: Array(actor_waba_tasks).include?('MANAGE'),
      selected_waba: @waba_id, phone_number_id: @phone_number_id, waba_owner_business_id: safe_waba_owner
    }
  end

  def safe_actor_tasks(actor_id)
    return nil if actor_id.blank?

    @client.waba_user_tasks(@waba_id, actor_id)
  rescue StandardError
    nil
  end

  def target_ids(granular, scope_name)
    Array((granular.find { |scope| scope['scope'] == scope_name } || {})['target_ids']).map(&:to_s)
  end

  def token_fingerprint
    OpenSSL::HMAC.hexdigest('SHA256', fingerprint_key, @token.to_s).first(16)
  end

  def fingerprint_key
    Rails.application.secret_key_base.presence || 'bloomwire-token-debug'
  end

  def safe_waba_owner
    @client.waba_owner_business_id(@waba_id)
  rescue StandardError
    nil
  end
end
