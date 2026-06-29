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
end
