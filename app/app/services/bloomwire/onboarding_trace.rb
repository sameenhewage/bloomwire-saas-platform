# Structured, sanitized onboarding trace for the managed WhatsApp (Coexistence) flow.
#
# SECURITY CONTRACT (do not weaken): this writes an allow-listed set of NON-sensitive fields as one line of
# structured JSON to the Rails application log — NEVER to a customer-facing surface and NEVER a raw value. It
# must never receive or emit an auth code, access token, phone number, phone_number_id, WABA/business ID, App
# ID, Configuration ID, full Meta URL/query string, or any credential. Only the allow-listed metadata below is
# ever logged; every other key is dropped. Tracing must never break onboarding, so all errors are rescued.
class Bloomwire::OnboardingTrace
  LOG_TAG = '[bloomwire.onboarding_trace]'.freeze

  # The complete set of trace events. Anything not in this list is rejected (browser) / ignored (server).
  EVENTS = %w[
    onboarding_started
    sdk_initialization_started sdk_initialization_succeeded sdk_initialization_failed
    meta_popup_opened
    auth_callback_received auth_callback_cancelled auth_callback_failed
    business_message_received business_message_rejected
    first_signal_received both_signals_received
    signal_completion_timeout overall_signup_timeout
    create_request_started create_request_succeeded create_request_failed create_request_timeout
    frontend_success_transition frontend_error_transition
    attempt_cancelled attempt_finished
  ].freeze

  RESULTS = %w[pending started ok success failure timeout cancelled rejected error].freeze
  SOURCES = %w[browser controller service].freeze
  MODE = 'coexistence'.freeze

  # `error_code` is a short internal, non-sensitive classifier (e.g. "http_422", "meta_error", "timeout").
  ERROR_CODE = /\A[a-z0-9_.:-]{1,48}\z/
  # Meta/Chatwoot attempt correlation id — opaque, non-sensitive (a UUID/short token we generated).
  ATTEMPT_ID = /\A[A-Za-z0-9_-]{6,64}\z/

  # Emit one sanitized trace line. `fields` is a plain hash of already-safe scalars; sensitive values are never
  # accepted (only the allow-listed keys below are read). Callers may pass keywords — Ruby folds them into `fields`.
  def self.emit(fields = {})
    return false unless valid_event?(fields[:event]) && valid_source?(fields[:source])

    Rails.logger.info("#{LOG_TAG} #{build_payload(fields).to_json}")
    true
  rescue StandardError => e
    # Tracing must NEVER break onboarding.
    Rails.logger.warn("#{LOG_TAG} trace not recorded: #{e.class}")
    false
  end

  def self.build_payload(fields)
    identity(fields).merge(details(fields)).compact
  end

  def self.identity(fields)
    {
      tag: 'bloomwire_onboarding_trace',
      onboarding_attempt_id: sanitize_attempt_id(fields[:attempt_id]),
      account_id: fields[:account_id].presence && fields[:account_id].to_i,
      actor_user_id: fields[:actor_id].presence && fields[:actor_id].to_i,
      mode: MODE,
      event: fields[:event].to_s,
      source: fields[:source].to_s,
      build_sha: build_sha,
      ts: Time.current.utc.iso8601(3)
    }
  end

  def self.details(fields)
    {
      result: sanitize_enum(fields[:result], RESULTS),
      elapsed_ms: sanitize_ms(fields[:elapsed_ms]),
      http_status: sanitize_status(fields[:http_status]),
      error_code: sanitize_error_code(fields[:error_code])
    }
  end

  def self.valid_event?(event)
    EVENTS.include?(event.to_s)
  end

  def self.valid_source?(source)
    SOURCES.include?(source.to_s)
  end

  def self.sanitize_attempt_id(value)
    v = value.to_s
    ATTEMPT_ID.match?(v) ? v : nil
  end

  def self.sanitize_enum(value, allowed)
    v = value.to_s
    allowed.include?(v) ? v : nil
  end

  def self.sanitize_ms(value)
    return nil if value.nil?

    ms = Integer(value, exception: false)
    return nil if ms.nil? || ms.negative? || ms > 86_400_000 # cap at 24h

    ms
  end

  def self.sanitize_status(value)
    return nil if value.nil?

    code = Integer(value, exception: false)
    return nil if code.nil? || code < 100 || code > 599

    code
  end

  def self.sanitize_error_code(value)
    return nil if value.blank?

    v = value.to_s
    ERROR_CODE.match?(v) ? v : 'invalid_code'
  end

  def self.build_sha
    (ENV['GIT_SHA'].presence || (File.read(Rails.root.join('.git_sha')).strip if File.exist?(Rails.root.join('.git_sha'))))&.slice(0, 40)
  rescue StandardError
    nil
  end
end
