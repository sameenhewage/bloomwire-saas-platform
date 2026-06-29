# Phase 15F: sends an owner-initiated test email using the DB-backed Bloomwire SMTP settings.
#
# Inherits ActionMailer::Base directly (NOT ApplicationMailer) on purpose:
#   * ApplicationMailer rescues SMTP exceptions and only logs them — that would let a failed send look like a
#     success. For an honest "test email" we want SMTP errors to propagate to SendTestEmailService.
#   * We force :smtp with THIS record's settings so the test always exercises the saved DB config, regardless
#     of the global ENV-derived delivery method.
# Plain-text only; the SMTP password is never logged or rendered.
class Bloomwire::EmailTestMailer < ActionMailer::Base # rubocop:disable Rails/ApplicationMailer
  def test_email(to:, setting:, subject: nil, body: nil)
    @body = body.presence || default_body(setting)

    message = mail(
      to: to,
      from: email_address_with_name(setting.effective_from_email, setting.effective_from_name),
      reply_to: setting.reply_to_email.presence,
      subject: subject.presence || 'Bloomwire SMTP test email'
    ) do |format|
      format.text { render plain: @body }
    end

    # Use the saved DB SMTP settings for this delivery (not the global ENV initializer).
    message.delivery_method(:smtp, setting.smtp_delivery_settings)
    message
  end

  # Phase 15F.1: send a REAL template email as multipart HTML + plain-text. The HTML part renders the SAME
  # shared partial as the composer preview (app/views/bloomwire/email/_branded_email.html.erb) so the
  # delivered email matches the preview. `body` is already variable-interpolated; the password is never logged.
  def template_email(to:, setting:, subject:, body:, cta_label: nil, cta_url: nil) # rubocop:disable Metrics/ParameterLists
    @body = body
    @cta_label = cta_label
    @cta_url = cta_url
    @year = Date.current.year

    message = mail(
      to: to,
      from: email_address_with_name(setting.effective_from_email, setting.effective_from_name),
      reply_to: setting.reply_to_email.presence,
      subject: subject.presence || '(no subject)'
    )
    message.delivery_method(:smtp, setting.smtp_delivery_settings)
    message
  end

  private

  def default_body(setting)
    "This is a test email from the Bloomwire Email Settings page.\n\n" \
      "If you received this, your outbound SMTP configuration is working.\n\n" \
      "Sent from: #{setting.effective_from_email}\nProvider: #{setting.smtp_address}\n\n— Bloomwire"
  end
end
