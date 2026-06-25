# Centralized redactor for explicit log / error / debug output (ADR-0003, Phase 2C). When Bloomwire privacy
# hardening is effectively ON (master AND-gated via Bloomwire::Features), sensitive token/secret values are
# replaced with [FILTERED]. With privacy hardening OFF (or master OFF) it is a no-op (stock Chatwoot).
# It NEVER mutates the input and must be used ONLY at explicit log boundaries — never before business logic
# reads the data, so services/controllers always receive the original values internally.
module Bloomwire::SensitiveDataRedactor
  FILTERED = '[FILTERED]'.freeze
  SENSITIVE_KEYS = %w[access_token api_key app_secret client_secret webhook_verify_token authorization].freeze
  SENSITIVE_KEY_PATTERN = /(?:token|secret|api_key|password|authorization)/i

  module_function

  # Redact sensitive values from a hash/array (or any value) for logging. Returns the input unchanged
  # unless privacy hardening is ON. Non-mutating.
  def redact(value)
    return value unless Bloomwire::Features.enabled?(:privacy_hardening)

    deep_redact(value)
  end

  # The provider response body to log: the stock raw body unless privacy hardening is ON, in which case the
  # parsed JSON body has its sensitive keys redacted. Falls back to the raw body when it is not parseable.
  def redact_response_body(response)
    body = response.try(:body)
    return body unless Bloomwire::Features.enabled?(:privacy_hardening)

    parsed = response.try(:parsed_response)
    parsed = safe_json_parse(body) if parsed.nil? && body.is_a?(String)
    return deep_redact(parsed) if parsed.is_a?(Hash) || parsed.is_a?(Array)

    body
  end

  def deep_redact(value)
    case value
    when Hash
      value.each_with_object({}) do |(key, val), result|
        result[key] = sensitive_key?(key) ? FILTERED : deep_redact(val)
      end
    when Array
      value.map { |element| deep_redact(element) }
    else
      value
    end
  end

  def sensitive_key?(key)
    name = key.to_s.downcase
    SENSITIVE_KEYS.include?(name) || name.match?(SENSITIVE_KEY_PATTERN)
  end

  def safe_json_parse(str)
    JSON.parse(str)
  rescue JSON::ParserError
    nil
  end
end
