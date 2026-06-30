# Phase 15F.1: owner-initiated "Send from Template" send. Preflight-validated, enabled-gated, NEVER fakes
# success, and writes exactly ONE Bloomwire::EmailDeliveryLog row per attempt (success / failed / blocked) so
# the Email Logs tab shows real history. The SMTP password is never returned or stored — every error string is
# passed through Bloomwire::EmailSetting#sanitize_secret first.
class Bloomwire::SendTemplateEmailService
  # The fully-rendered email to send (subject/body already variable-interpolated by the caller).
  Composition = Struct.new(:template, :recipient, :subject, :body, :cta_label, :cta_url, keyword_init: true)

  Result = Struct.new(:status, :message, :log, keyword_init: true) do
    def success?
      status == 'success'
    end
  end

  BLOCK_MESSAGES = {
    missing_recipient: 'Enter a recipient email address.',
    invalid_email: 'Enter a valid recipient email address.',
    unfilled_variables: 'Some {{variables}} are not filled in. Fill every variable before sending.',
    incomplete_smtp: 'SMTP is not fully configured. Complete it in Configuration first.',
    smtp_disabled: 'Outbound email is disabled. Enable it in Configuration first.'
  }.freeze

  # Lightweight RFC-5321-ish recipient check — blocks obviously invalid addresses BEFORE opening SMTP.
  EMAIL_FORMAT = /\A[^@\s]+@[^@\s]+\.[^@\s]+\z/

  def initialize(setting:, composition:, actor: nil)
    @setting = setting
    @c = composition
    @actor = actor
  end

  def call
    reason = @setting.block_reason(recipient: @c.recipient, require_enabled: true) || composition_block_reason
    return blocked(reason) if reason

    deliver!
  rescue StandardError => e
    failed(@setting.sanitize_secret("#{e.class}: #{e.message}"))
  end

  private

  # Phase 15F.2: composition-level preflight (runs only after SMTP/recipient-presence checks pass).
  # Blocks an invalid recipient and any unfilled {{placeholder}} so we never send a half-rendered email.
  def composition_block_reason
    recipient = @c.recipient.to_s.strip
    return :invalid_email if recipient.present? && !recipient.match?(EMAIL_FORMAT)
    return :unfilled_variables if unresolved_placeholders?

    nil
  end

  # Any leftover `{{ ... }}` in the rendered output means a variable was not filled (or is malformed) — block,
  # so we never deliver an email containing raw placeholders.
  LEFTOVER_PLACEHOLDER = /\{\{.*?\}\}/m

  def unresolved_placeholders?
    [@c.subject, @c.body, @c.cta_label, @c.cta_url].any? { |t| t.to_s.match?(LEFTOVER_PLACEHOLDER) }
  end

  def deliver!
    Bloomwire::EmailTestMailer.template_email(
      to: @c.recipient.to_s.strip, setting: @setting,
      subject: @c.subject, body: @c.body, cta_label: @c.cta_label, cta_url: @c.cta_url
    ).deliver_now
    Result.new(status: 'success', message: "Email sent to #{@c.recipient.to_s.strip}.", log: record('success'))
  end

  def blocked(reason)
    msg = BLOCK_MESSAGES.fetch(reason, 'Email cannot be sent.')
    Result.new(status: 'blocked', message: msg, log: record('blocked', error: msg))
  end

  def failed(safe)
    Result.new(status: 'failed', message: "Email failed: #{safe}", log: record('failed', error: safe))
  end

  def record(status, error: nil)
    Bloomwire::EmailDeliveryLog.create!(log_attrs(status, error))
  rescue StandardError
    nil # an audit-log write failure must never change the user-facing send result
  end

  def log_attrs(status, error)
    {
      email_template: @c.template,
      template_key: @c.template&.key,
      template_name: @c.template&.name,
      recipient_email: trim(@c.recipient),
      subject: trim(@c.subject),
      status: status,
      error_message: error.presence,
      actor_id: @actor&.id,
      sent_at: (status == 'success' ? Time.current : nil)
    }
  end

  def trim(value)
    value.to_s.strip.presence&.truncate(255)
  end
end
