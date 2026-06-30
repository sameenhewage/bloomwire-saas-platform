require 'rails_helper'

# Phase 15F.1: real "Send from Template" send. Preflight + enabled-gated; writes ONE delivery log per attempt
# (success/failed/blocked); never fakes success; the SMTP password never appears in a log or returned message.
# The mailer is stubbed for the delivery paths so no real SMTP connection is opened in the suite.
RSpec.describe Bloomwire::SendTemplateEmailService do
  before { ActionMailer::Base.deliveries.clear }

  let(:template) do
    Bloomwire::EmailTemplate.create!(
      key: 'svc_tpl', name: 'Service Template', subject: 'Hi {{recipient_name}}',
      body: 'Hello {{recipient_name}} at {{business_name}}'
    )
  end
  let(:complete_setting) do
    Bloomwire::EmailSetting.create!(
      Bloomwire::EmailSetting.default_attributes.merge(
        smtp_address: 'smtp.example.com', smtp_domain: 'example.com', smtp_username: 'u@example.com',
        smtp_password: 'secret-pw', from_email: 'from@example.com', enabled: true
      )
    )
  end

  def composition(recipient: 'to@example.com')
    described_class::Composition.new(
      template: template, recipient: recipient, subject: 'Hi Jane', body: 'Hello Jane at Acme',
      cta_label: 'Accept', cta_url: 'https://app.bloomwire.lk/i/abc'
    )
  end

  it 'delivers and creates a SUCCESS delivery log (mailer stubbed — no real send)' do
    delivery = instance_double(ActionMailer::MessageDelivery, deliver_now: true)
    allow(Bloomwire::EmailTestMailer).to receive(:template_email).and_return(delivery)

    result = nil
    expect { result = described_class.new(setting: complete_setting, composition: composition).call }
      .to change(Bloomwire::EmailDeliveryLog, :count).by(1)

    expect(result.status).to eq('success')
    log = Bloomwire::EmailDeliveryLog.last
    expect(log.status).to eq('success')
    expect(log.recipient_email).to eq('to@example.com')
    expect(log.template_name).to eq('Service Template')
    expect(log.template_key).to eq('svc_tpl')
    expect(log.sent_at).to be_present
  end

  it 'creates a FAILED log with a sanitized error (no password) when delivery raises' do
    allow(Bloomwire::EmailTestMailer).to receive(:template_email).and_raise(StandardError.new('smtp boom for secret-pw'))

    result = described_class.new(setting: complete_setting, composition: composition).call

    expect(result.status).to eq('failed')
    expect(result.message).not_to include('secret-pw')
    log = Bloomwire::EmailDeliveryLog.last
    expect(log.status).to eq('failed')
    expect(log.error_message).to include('[FILTERED]')
    expect(log.error_message).not_to include('secret-pw')
    expect(ActionMailer::Base.deliveries).to be_empty
  end

  it 'blocks (blocked log) when the recipient is missing — no delivery attempted' do
    result = described_class.new(setting: complete_setting, composition: composition(recipient: '')).call
    expect(result.status).to eq('blocked')
    expect(Bloomwire::EmailDeliveryLog.last.status).to eq('blocked')
    expect(Bloomwire::EmailDeliveryLog.last.error_message).to match(/recipient/i)
    expect(ActionMailer::Base.deliveries).to be_empty
  end

  it 'blocks (blocked log) when SMTP is incomplete — no delivery attempted' do
    incomplete = Bloomwire::EmailSetting.create!(
      Bloomwire::EmailSetting.default_attributes.merge(
        smtp_password: nil, smtp_address: 'h', smtp_domain: 'd', smtp_username: 'u', from_email: 'f@x.com', enabled: true
      )
    )
    result = described_class.new(setting: incomplete, composition: composition).call
    expect(result.status).to eq('blocked')
    expect(Bloomwire::EmailDeliveryLog.last.status).to eq('blocked')
    expect(ActionMailer::Base.deliveries).to be_empty
  end

  it 'blocks (blocked log) when outbound email is disabled — no delivery attempted' do
    complete_setting.update!(enabled: false)
    result = described_class.new(setting: complete_setting, composition: composition).call
    expect(result.status).to eq('blocked')
    log = Bloomwire::EmailDeliveryLog.last
    expect(log.status).to eq('blocked')
    expect(log.error_message).to match(/disabled/i)
    expect(ActionMailer::Base.deliveries).to be_empty
  end

  it 'blocks an invalid recipient email BEFORE opening SMTP (Phase 15F.2)' do
    expect(Bloomwire::EmailTestMailer).not_to receive(:template_email)
    result = described_class.new(setting: complete_setting, composition: composition(recipient: 'not-an-email')).call
    expect(result.status).to eq('blocked')
    expect(Bloomwire::EmailDeliveryLog.last.error_message).to match(/valid/i)
    expect(ActionMailer::Base.deliveries).to be_empty
  end

  it 'blocks when the rendered email still contains an unfilled {{placeholder}} (Phase 15F.2)' do
    expect(Bloomwire::EmailTestMailer).not_to receive(:template_email)
    comp = described_class::Composition.new(
      template: template, recipient: 'to@example.com', subject: 'Hi {{recipient_name}}',
      body: 'Hello {{recipient_name}} at Acme', cta_label: 'Go', cta_url: 'https://x.test'
    )
    result = described_class.new(setting: complete_setting, composition: comp).call
    expect(result.status).to eq('blocked')
    expect(Bloomwire::EmailDeliveryLog.last.error_message).to match(/variable|placeholder/i)
    expect(ActionMailer::Base.deliveries).to be_empty
  end
end
