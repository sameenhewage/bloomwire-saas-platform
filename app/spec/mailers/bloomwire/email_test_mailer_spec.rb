require 'rails_helper'

# Phase 15F: the test-email mailer builds a plain-text message from the DB-backed sender identity.
# Building the message does not open an SMTP connection, so this never sends real email.
RSpec.describe Bloomwire::EmailTestMailer do
  let(:setting) do
    Bloomwire::EmailSetting.new(
      smtp_address: 'smtp.example.com', smtp_port: 587, smtp_username: 'u@example.com',
      smtp_password: 'pw', smtp_domain: 'example.com', from_email: 'from@example.com', from_name: 'Bloomwire'
    )
  end

  it 'builds a plain-text test email addressed from the configured sender' do
    mail = described_class.test_email(to: 'to@example.com', setting: setting)
    expect(mail.to).to eq(['to@example.com'])
    expect(mail.from).to eq(['from@example.com'])
    expect(mail.subject).to match(/test/i)
    expect(mail.body.encoded).to include('test email')
  end

  # Phase 15F.1: the template send is multipart HTML + text and renders the SHARED branded partial
  # (the same partial the composer preview uses), so the delivered email matches the preview.
  describe '#template_email' do
    subject(:mail) do
      described_class.template_email(
        to: 'jane@example.com', setting: setting, subject: 'Welcome Jane',
        body: "Hi Jane Doe,\n\nYou are invited to join Acme Co.", cta_label: 'Accept Invitation',
        cta_url: 'https://app.bloomwire.lk/i/abc'
      )
    end

    it 'is a multipart message with both an HTML part and a text part' do
      expect(mail.to).to eq(['jane@example.com'])
      expect(mail.from).to eq(['from@example.com'])
      expect(mail.subject).to eq('Welcome Jane')
      expect(mail.html_part).to be_present
      expect(mail.text_part).to be_present
    end

    it 'renders the HTML part with replaced values, a CTA button, branding and footer (no raw placeholders)' do
      html = mail.html_part.body.to_s
      expect(html).to include('Jane Doe')
      expect(html).to include('Acme Co')
      expect(html).to include('https://app.bloomwire.lk/i/abc') # CTA href
      expect(html).to include('Accept Invitation')              # CTA label
      expect(html).to include('Bloomwire')                      # branding from shared partial
      expect(html).to include('All rights reserved')            # footer from shared partial
      expect(html).not_to include('{{')                         # no leaked placeholders
    end

    it 'renders a text fallback part with the same key values and CTA' do
      text = mail.text_part.body.to_s
      expect(text).to include('Jane Doe')
      expect(text).to include('Acme Co')
      expect(text).to include('Accept Invitation: https://app.bloomwire.lk/i/abc')
      expect(text).not_to include('{{')
    end
  end
end
