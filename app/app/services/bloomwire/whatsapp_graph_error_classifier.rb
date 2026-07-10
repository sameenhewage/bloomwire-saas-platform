# Pure, sanitized classification of a Meta Graph error as TRANSIENT (retryable) vs a TERMINAL OAuth failure.
# Uses ONLY the existing Whatsapp::GraphApiError safe fields (is_transient / http_status / error_type) plus the
# GraphApiTimeoutError type — no invented Meta code-number mappings. Shared by the async processor (OAuth-exchange
# stage) and, later, the Slice 3 job's retry decision. Never inspects/logs the raw response body or any secret.
module Bloomwire::WhatsappGraphErrorClassifier
  module_function

  # A Meta-confirmed OAuthException that is NOT flagged transient — i.e. an invalid/expired authorization code.
  def terminal_oauth?(error)
    error.is_a?(Whatsapp::GraphApiError) && !transient?(error) && error.error_type.to_s == 'OAuthException'
  end

  # A network/read timeout, Meta's own is_transient flag, an HTTP 5xx, or an HTTP 429 rate limit.
  def transient?(error)
    return true if error.is_a?(Whatsapp::GraphApiTimeoutError)
    return false unless error.is_a?(Whatsapp::GraphApiError)

    ActiveModel::Type::Boolean.new.cast(error.is_transient) ||
      error.http_status.to_i >= 500 ||
      error.http_status.to_i == 429
  end
end
