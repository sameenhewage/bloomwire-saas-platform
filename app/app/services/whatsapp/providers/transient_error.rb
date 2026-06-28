# Bloomwire Phase 13B.2: raised by the WhatsApp Cloud provider on a transient (HTTP 429 / 5xx) send failure
# so SendReplyJob can retry within a bounded policy instead of marking the message failed immediately.
# Mirrors Webhooks::Trigger::RetryableError. The message is status-only (no secret / no provider body).
class Whatsapp::Providers::TransientError < StandardError
  attr_reader :status

  def initialize(status:, message:)
    @status = status
    super(message)
  end
end
