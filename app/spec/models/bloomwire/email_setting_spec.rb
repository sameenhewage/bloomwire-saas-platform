require 'rails_helper'

# Phase 15F: Bloomwire-owned SMTP settings model. ENV bootstrap defaults + delivery preflight + test result.
RSpec.describe Bloomwire::EmailSetting do
  describe '.current' do
    it 'returns an unsaved record pre-filled with bootstrap defaults when none exists' do
      setting = described_class.current
      expect(setting).not_to be_persisted
      expect(setting.smtp_address).to be_present
      expect(setting.smtp_port).to be_positive
    end

    it 'returns the persisted row once saved' do
      row = described_class.create!(described_class.default_attributes)
      expect(described_class.current.id).to eq(row.id)
    end
  end

  describe '#missing_required_fields / #deliverable?' do
    let(:base) do
      { smtp_address: 'h', smtp_port: 587, smtp_domain: 'd', smtp_username: 'u', from_email: 'f@x.com' }
    end

    it 'flags a blank password as missing and is not deliverable' do
      setting = described_class.new(base.merge(smtp_password: nil))
      expect(setting.missing_required_fields).to include(:smtp_password)
      expect(setting.deliverable?).to be(false)
    end

    it 'is deliverable when all required fields are present' do
      setting = described_class.new(base.merge(smtp_password: 'pw'))
      expect(setting.missing_required_fields).to be_empty
      expect(setting.deliverable?).to be(true)
    end
  end

  describe '#smtp_delivery_settings' do
    it 'symbolizes authentication and drops blank values' do
      setting = described_class.new(smtp_address: 'h', smtp_port: 587, smtp_authentication: 'login',
                                    smtp_username: 'u', smtp_password: 'pw', smtp_domain: '')
      settings = setting.smtp_delivery_settings
      expect(settings[:authentication]).to eq(:login)
      expect(settings[:address]).to eq('h')
      expect(settings).not_to have_key(:domain)
    end
  end

  describe '#record_test_result!' do
    it 'records success with a timestamp' do
      setting = described_class.create!(described_class.default_attributes)
      setting.record_test_result!(status: 'success')
      expect(setting.reload.last_test_status).to eq('success')
      expect(setting.last_test_sent_at).to be_present
    end

    it 'records a blocked status without a sent timestamp' do
      setting = described_class.create!(described_class.default_attributes)
      setting.record_test_result!(status: 'blocked_missing_config', error: 'missing password')
      expect(setting.reload.last_test_status).to eq('blocked_missing_config')
      expect(setting.last_test_sent_at).to be_nil
    end
  end
end
