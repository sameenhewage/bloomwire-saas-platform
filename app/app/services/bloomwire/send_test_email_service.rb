# Phase 15F: owner-initiated test-email send with PREFLIGHT validation. Never fakes success.
# - blank recipient / unsaved settings / missing required SMTP fields  => blocked (no send attempted)
# - otherwise attempts a real delivery via the DB-backed SMTP settings and reports the honest outcome
# The SMTP password is never included in any returned/recorded message (sanitized + filtered).
class Bloomwire::SendTestEmailService
  Result = Struct.new(:status, :message, keyword_init: true) do
    def success?
      status == 'success'
    end
  end

  def initialize(setting:, recipient:, actor: nil)
    @setting = setting
    @recipient = recipient.to_s.strip
    @actor = actor
  end

  def call
    return Result.new(status: 'blocked_missing_config', message: 'Enter a recipient email address.') if @recipient.blank?
    return Result.new(status: 'blocked_missing_config', message: 'Save your SMTP settings before sending a test email.') unless @setting.persisted?

    missing = @setting.missing_required_fields
    return blocked_missing(missing) if missing.any?

    deliver!
  rescue StandardError => e
    safe = sanitize_error(e)
    @setting.record_test_result!(status: 'failed', error: safe, actor: @actor)
    Result.new(status: 'failed', message: "Test email failed: #{safe}")
  end

  private

  def deliver!
    Bloomwire::EmailTestMailer.test_email(to: @recipient, setting: @setting).deliver_now
    @setting.record_test_result!(status: 'success', actor: @actor)
    Result.new(status: 'success', message: "Test email sent to #{@recipient}.")
  end

  def blocked_missing(missing)
    msg = "SMTP is not fully configured (missing: #{missing.join(', ')}). Test email cannot be sent."
    @setting.record_test_result!(status: 'blocked_missing_config', error: msg, actor: @actor)
    Result.new(status: 'blocked_missing_config', message: msg)
  end

  # Strips the secret from any error text and caps length so the password can never leak via an SMTP error.
  def sanitize_error(error)
    msg = "#{error.class}: #{error.message}"
    msg = msg.gsub(@setting.smtp_password.to_s, '[FILTERED]') if @setting.smtp_password.present?
    msg.truncate(200)
  end
end
