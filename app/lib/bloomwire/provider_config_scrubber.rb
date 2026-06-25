# Centralized, output-only scrubber for Channel#provider_config (ADR-0003, Phase 2B).
# When Bloomwire privacy hardening is effectively ON (master AND-gated via Bloomwire::Features),
# sensitive provider_config values (secrets/tokens/API keys) are dropped from outbound API/JSON/browser
# responses. It NEVER mutates the stored config and is a no-op (stock Chatwoot) when the feature is OFF.
module Bloomwire::ProviderConfigScrubber
  # provider_config keys whose values are credentials and must not be exposed in responses.
  SENSITIVE_KEYS = %w[api_key webhook_verify_token].freeze
  SENSITIVE_KEY_PATTERN = /(?:secret|token|password|api_key)/i

  module_function

  # The provider_config to render in an outbound response: stock (unchanged) unless privacy hardening
  # is ON, in which case sensitive keys are dropped. Reads the toggle only via Bloomwire::Features.
  def for_response(provider_config)
    return provider_config unless Bloomwire::Features.enabled?(:privacy_hardening)

    scrub(provider_config)
  end

  # A copy of provider_config without sensitive keys. Non-Hash input (e.g. nil) is returned unchanged.
  # Never mutates the input, so the stored config is untouched.
  def scrub(provider_config)
    return provider_config unless provider_config.is_a?(Hash)

    provider_config.reject { |key, _value| sensitive_key?(key) }
  end

  def sensitive_key?(key)
    name = key.to_s.downcase
    SENSITIVE_KEYS.include?(name) || name.match?(SENSITIVE_KEY_PATTERN)
  end
end
