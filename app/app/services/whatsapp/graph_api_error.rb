# Structured, sanitized error for a failed Meta WhatsApp Graph API call. Raised by
# Whatsapp::FacebookApiClient#register_phone_number so a caller can log the SPECIFIC Meta failure
# (HTTP status + Meta error code / subcode / type / is_transient / fbtrace_id / message) without ever
# re-parsing an opaque string or logging the raw response body, request body, access token, or PIN.
#
# The exception MESSAGE is kept byte-identical to the legacy `handle_response` format ("<context>: <raw body>")
# so existing callers/specs that only match on the message prefix (e.g. native Whatsapp::WebhookSetupService,
# which logs `e.message`, and specs asserting /Phone registration failed/) are unchanged. Only the added
# structured attributes are new, and only the Bloomwire managed path reads them (via #to_safe_h) to emit a
# sanitized structured log event.
class Whatsapp::GraphApiError < StandardError
  MAX_MESSAGE_LENGTH = 300

  attr_reader :http_status, :error_code, :error_subcode, :error_type, :is_transient, :fbtrace_id, :safe_message

  # Builds the error from an HTTParty response, extracting only the allow-listed Meta error fields.
  def self.from_response(context, response)
    meta = extract_meta_error(response.body)
    new("#{context}: #{response.body}", {
          http_status: response.code,
          error_code: meta['code'],
          error_subcode: meta['error_subcode'],
          error_type: meta['type'],
          is_transient: meta['is_transient'],
          fbtrace_id: meta['fbtrace_id'],
          safe_message: sanitize_message(meta['message'])
        })
  end

  def self.extract_meta_error(body)
    parsed = JSON.parse(body.to_s)
    parsed.is_a?(Hash) && parsed['error'].is_a?(Hash) ? parsed['error'] : {}
  rescue StandardError
    {}
  end
  private_class_method :extract_meta_error

  def self.sanitize_message(message)
    return if message.blank?

    message.to_s.truncate(MAX_MESSAGE_LENGTH)
  end
  private_class_method :sanitize_message

  def initialize(message, fields = {})
    super(message)
    @http_status = fields[:http_status]
    @error_code = fields[:error_code]
    @error_subcode = fields[:error_subcode]
    @error_type = fields[:error_type]
    @is_transient = fields[:is_transient]
    @fbtrace_id = fields[:fbtrace_id]
    @safe_message = fields[:safe_message]
  end

  # Secret-free fields safe to log. NEVER includes the raw body/message, request body, token, or PIN.
  def to_safe_h
    {
      http_status: http_status,
      meta_error_code: error_code,
      meta_error_subcode: error_subcode,
      meta_error_type: error_type,
      is_transient: is_transient,
      fbtrace_id: fbtrace_id,
      meta_error_message: safe_message
    }
  end
end
