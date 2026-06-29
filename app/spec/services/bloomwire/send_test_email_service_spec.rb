require 'rails_helper'

# Phase 15F: preflight-validated test email. Never fakes success; never leaks the SMTP password.
# In the test environment ActionMailer uses :test delivery, so no real external email is sent.
RSpec.describe Bloomwire::SendTestEmailService do
  before { ActionMailer::Base.deliveries.clear }

  let(:complete_setting) do
    Bloomwire::EmailSetting.create!(
      Bloomwire::EmailSetting.default_attributes.merge(
        smtp_address: 'smtp.example.com', smtp_domain: 'example.com', smtp_username: 'u@example.com',
        smtp_password: 'secret-pw', from_email: 'from@example.com'
      )
    )
  end

  it 'blocks when the recipient is blank (no delivery)' do
    result = described_class.new(setting: complete_setting, recipient: '').call
    expect(result.status).to eq('blocked_missing_config')
    expect(ActionMailer::Base.deliveries).to be_empty
  end

  it 'blocks when the SMTP password is missing and records an honest status' do
    setting = Bloomwire::EmailSetting.create!(
      Bloomwire::EmailSetting.default_attributes.merge(
        smtp_password: nil, smtp_address: 'h', smtp_domain: 'd', smtp_username: 'u', from_email: 'f@x.com'
      )
    )
    result = described_class.new(setting: setting, recipient: 'to@example.com').call
    expect(result.status).to eq('blocked_missing_config')
    expect(result.message).to include('not fully configured')
    expect(setting.reload.last_test_status).to eq('blocked_missing_config')
    expect(ActionMailer::Base.deliveries).to be_empty
  end

  it 'delivers when fully configured and records success (mailer stubbed — no real send)' do
    delivery = instance_double(ActionMailer::MessageDelivery, deliver_now: true)
    allow(Bloomwire::EmailTestMailer).to receive(:test_email).and_return(delivery)

    result = described_class.new(setting: complete_setting, recipient: 'to@example.com').call

    expect(delivery).to have_received(:deliver_now)
    expect(result.status).to eq('success')
    expect(complete_setting.reload.last_test_status).to eq('success')
    expect(complete_setting.last_test_sent_at).to be_present
  end

  it 'never includes the SMTP password in a sanitized failure message' do
    allow(Bloomwire::EmailTestMailer).to receive(:test_email).and_raise(StandardError.new('connection failed for secret-pw'))
    result = described_class.new(setting: complete_setting, recipient: 'to@example.com').call
    expect(result.status).to eq('failed')
    expect(result.message).not_to include('secret-pw')
    expect(result.message).to include('[FILTERED]')
    expect(complete_setting.reload.last_test_error).not_to include('secret-pw')
  end

  # Phase 15F.1: composer-specific behaviour (require_enabled + rendered subject/body pass-through).
  it 'blocks a real send when outbound email is disabled (require_enabled) and does not deliver' do
    complete_setting.update!(enabled: false)
    result = described_class.new(setting: complete_setting, recipient: 'to@example.com', require_enabled: true, noun: 'Email').call
    expect(result.status).to eq('blocked_missing_config')
    expect(result.message).to match(/disabled/i)
    expect(complete_setting.reload.last_test_status).to eq('blocked_missing_config')
    expect(ActionMailer::Base.deliveries).to be_empty
  end

  it 'passes the rendered subject/body through to the mailer and uses the given noun' do
    complete_setting.update!(enabled: true) # required: composer sends are enabled-gated (require_enabled: true)
    delivery = instance_double(ActionMailer::MessageDelivery, deliver_now: true)
    captured = nil
    allow(Bloomwire::EmailTestMailer).to receive(:test_email) do |*args, **kwargs|
      captured = kwargs.any? ? kwargs : args.first
      delivery
    end

    result = described_class.new(
      setting: complete_setting, recipient: 'to@example.com',
      subject: 'Welcome Jane', body: 'Hello Jane, join Acme Co.', require_enabled: true, noun: 'Email'
    ).call

    expect(captured).to include(to: 'to@example.com', subject: 'Welcome Jane', body: 'Hello Jane, join Acme Co.')
    expect(captured[:setting]).to eq(complete_setting)
    expect(result.status).to eq('success')
    expect(result.message).to eq('Email sent to to@example.com.')
  end
end
