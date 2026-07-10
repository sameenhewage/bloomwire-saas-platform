# Single source of truth for the Meta Graph API HTTP timeouts (open/read), config-driven at RUNTIME via
# GlobalConfigService. The async onboarding mutation-lease budget DERIVES from this same provider (see
# Bloomwire::WhatsappOnboardingLeasable.mutation_lease_seconds), so a change to the Graph timeout configuration
# AUTOMATICALLY widens/narrows the lease budget — no duplicated hardcoded lease timeout. Runtime validation:
# non-positive/blank config is clamped to the safe default, so the effective values are always usable and the
# derived lease (max_call + positive margin) always exceeds the single-call maximum.
module Whatsapp::GraphApiTimeouts
  DEFAULT_OPEN_SECONDS = 5
  DEFAULT_READ_SECONDS = 25
  OPEN_TIMEOUT_KEY = 'WHATSAPP_GRAPH_OPEN_TIMEOUT_SECONDS'.freeze
  READ_TIMEOUT_KEY = 'WHATSAPP_GRAPH_READ_TIMEOUT_SECONDS'.freeze

  module_function

  def open_seconds
    positive_or_default(OPEN_TIMEOUT_KEY, DEFAULT_OPEN_SECONDS)
  end

  def read_seconds
    positive_or_default(READ_TIMEOUT_KEY, DEFAULT_READ_SECONDS)
  end

  # The maximum bounded duration of a single Graph call (connection + read).
  def max_call_seconds
    open_seconds + read_seconds
  end

  def positive_or_default(key, default)
    value = GlobalConfigService.load(key, default).to_i
    value.positive? ? value : default
  end
end
